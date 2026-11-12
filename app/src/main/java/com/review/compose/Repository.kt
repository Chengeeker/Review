package com.review.compose

import android.app.Application
import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.disk.DiskCache
import coil.memory.MemoryCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.*
import org.json.JSONObject
import java.io.IOException
import java.security.KeyStore
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class ReviewApplication : Application(), ImageLoaderFactory {
    override fun newImageLoader() = ImageLoader.Builder(this)
        .components { if (android.os.Build.VERSION.SDK_INT >= 28) add(coil.decode.ImageDecoderDecoder.Factory()) else add(coil.decode.GifDecoder.Factory()) }
        .memoryCache { MemoryCache.Builder(this).maxSizePercent(0.15).build() }
        .diskCache { ManagedImageCache(DiskCache.Builder().directory(cacheDir.resolve("images")).maxSizeBytes(128L * 1024 * 1024).build()) }
        .okHttpClient { OkHttpClient.Builder().addInterceptor { chain ->
            chain.proceed(chain.request().newBuilder().header("Referer", "https://weibo.com/").build())
        }.addNetworkInterceptor { chain ->
            val request = chain.request()
            chain.proceed(request.newBuilder().removeHeader("Cookie").apply { MediaFiles.privateMediaCookie(request.url.toString(), request.header("Cookie").orEmpty()).takeIf(String::isNotBlank)?.let { header("Cookie", it) } }.build())
        }.build() }.crossfade(true).build()
}

class SessionStore(private val context: Context, private val namespace: String = "session", private val keyProvider: ((Boolean)->SecretKey)? = null) {
    private val prefs = context.getSharedPreferences(namespace, Context.MODE_PRIVATE)
    private fun key(create: Boolean = true): SecretKey {
        keyProvider?.let { return it(create) }
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("compose-$namespace", null) as? SecretKey)?.let { return it }
        if(!create)throw SecretReadFailure(SecretFailureKind.MISSING_KEY)
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("compose-$namespace", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    internal fun preserveBeforeReplacement(recoverUnreadable: Boolean) {
        try { load() } catch (e: SecretReadFailure) {
            if (!recoverUnreadable || !e.recoverable) throw e
            archiveEncryptedFile(context, java.io.File(context.applicationInfo.dataDir, "shared_prefs/$namespace.xml"))
        }
    }
    fun save(cookie: String, recoverUnreadable: Boolean = false) {
        preserveBeforeReplacement(recoverUnreadable)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val original=snapshot()
        val committed=prefs.edit().putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .putString("data", Base64.encodeToString(cipher.doFinal(cookie.toByteArray()), Base64.NO_WRAP)).commit()
        if(!committed){val failure=java.io.IOException("加密资料写入失败");try{rollback(snapshot(),original)}catch(e:Exception){failure.addSuppressed(e)};throw failure}
        if(namespace=="session")revision.incrementAndGet()
    }
    fun load(): String = readEncrypted {
        val data = prefs.getString("data", null) ?: return@readEncrypted ""
        require(Base64.decode(data,Base64.NO_WRAP).size in 16..(16*1024*1024) && Base64.decode(prefs.getString("iv",""),Base64.NO_WRAP).size==12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, Base64.decode(prefs.getString("iv", ""), Base64.NO_WRAP)))
        }
        String(cipher.doFinal(Base64.decode(data, Base64.NO_WRAP)), Charsets.UTF_8)
    }
    fun clear() { check(prefs.edit().clear().commit());if(namespace=="session")revision.incrementAndGet() }
    internal fun snapshot():Map<String,*> = prefs.all.toMap()
    internal fun rollback(expected:Map<String,*>, original:Map<String,*>) {
        check(prefs.all==expected){"账号资料已改变，保留最新资料"}
        check(prefs.edit().clear().also { edit->original.forEach{(key,value)->if(value is String)edit.putString(key,value)} }.commit())
        if(namespace=="session")revision.incrementAndGet()
    }
    companion object {
        internal val accountWrites=kotlinx.coroutines.sync.Mutex()
        internal val revision=java.util.concurrent.atomic.AtomicLong()
    }
}

data class VerifiedWebSession(val cookie: String, val mobileOnly: Boolean, val uid: String)

class Repository(
    private val native: com.review.weiboauth.WeiboAuthManager? = null,
    private val nativeRequest: (String, Map<String, String>) -> String? = { endpoint, params ->
        if (native?.hasNativeSession() == true) native.requestApi(endpoint, params) else null
    },
    private val oauthFollowingRequest: (String, Map<String, String>) -> String? = { uid, params ->
        native?.requestOAuthFollowing(uid, params)
    }
) {
    val api = ApiClient()
    var mobileOnly = false
    suspend fun get(path: String, cookie: String, parameters: Map<String, String> = emptyMap()): JSONObject {
        require(path.startsWith("/ajax/") && !path.contains(".."))
        return api.get(ApiClient.DESKTOP + path, cookie, parameters)
    }
    suspend fun nativeGet(endpoint: String, params: Map<String, String> = emptyMap()): JSONObject? = withContext(Dispatchers.IO) {
        nativeRequest(endpoint, params)?.let {
            val body = JSONObject(it)
            if (body.optString("errno") !in setOf("", "0")) throw IOException("原生接口拒绝了请求")
            ApiClient.requireSuccess(body)
        }
    }
    private fun requireSessionCookie(cookie: String) {
        require(cookie.length <= 32768 && cookie.all { it in ' '..'~' }) { "会话格式不正确" }
        require(Regex("(?:^|;\\s*)SUB=[^;]+").containsMatchIn(cookie)) { "会话缺少必要字段" }
    }
    private fun normalizeSessionCookie(input: String): String {
        val raw = input.trim()
        require(raw.length <= 32768 && raw.all { it in ' '..'~' }) { "会话格式不正确" }
        val cookie = if (';' !in raw && ('=' !in raw || raw.startsWith("_2A"))) "SUB=$raw" else raw.split(';').mapNotNull { part ->
            val name = part.substringBefore('=', "").trim()
            val value = part.substringAfter('=', "").trim()
            if (name.isBlank() || value.isBlank()) null else (when (name.lowercase()) { "sub" -> "SUB"; "subp" -> "SUBP"; else -> name }) to value
        }.distinctBy { it.first.lowercase() }.joinToString("; ") { (name, value) -> "$name=$value" }
        requireSessionCookie(cookie)
        return cookie
    }
    suspend fun importWebSession(input: String, expectedUid: String?): VerifiedWebSession {
        val cookie = normalizeSessionCookie(input)
        return verifyWebSession(expectedUid, cookie)
            ?: throw IOException("桌面和移动服务均未确认此 Cookie 的登录状态")
    }

    private suspend fun verifyDesktopSession(expectedUid: String?, cookie: String): VerifiedWebSession? {
        val groups = webSessionProbe("${ApiClient.DESKTOP}/ajax/feed/allGroups", cookie)
        val sections = groups?.optJSONArray("groups") ?: groups?.optJSONObject("data")?.optJSONArray("groups")
        val groupUids = sections.objects().flatMap { section ->
            section.optJSONArray("group").objects().mapNotNull { group ->
                val gid = group.optString("gid")
                gid.removePrefix("11000").takeIf { gid.startsWith("11000") && it.matches(Regex("[1-9][0-9]*")) }
            }
        }.distinct()
        if (groupUids.size > 1) throw IOException("账号分组返回了不一致的账号标识")
        val uid = groupUids.singleOrNull() ?: run {
            val profile = webSessionProbe("${ApiClient.DESKTOP}/ajax/profile/detail", cookie)?.optJSONObject("data") ?: return null
            val profileUid = listOf(Regex("(?:[?&])uid=([1-9][0-9]*)(?:[&#]|$)").find(profile.optString("verified_url"))?.groupValues?.get(1),
                profile.optString("uid"), profile.optString("id")).firstOrNull { it?.matches(Regex("[1-9][0-9]*")) == true } ?: return null
            require(expectedUid == null || profileUid == expectedUid) { "登录账号与返回会话不一致" }
            // Profile detail is only a candidate until the authenticated feed also responds.
            val feed = webSessionProbe("${ApiClient.DESKTOP}/ajax/feed/friendstimeline", cookie,
                mapOf("list_id" to "10001", "count" to "1", "page" to "1", "refresh" to "0"))
            if (feed?.optJSONArray("statuses").objects().isEmpty()) return null
            profileUid
        }
        require(expectedUid == null || uid == expectedUid) { "登录账号与返回会话不一致" }
        return VerifiedWebSession(cookie, false, uid)
    }
    suspend fun verifyWebSession(
        expectedUid: String?,
        cookie: String,
        desktopCookie: String = "",
        mobileCookie: String = ""
    ): VerifiedWebSession? {
        require(expectedUid == null || expectedUid.matches(Regex("[1-9][0-9]*"))) { "登录响应缺少有效的账号标识" }
        val desktop = ApiClient.DESKTOP
        val mobile = ApiClient.MOBILE
        val unscoped = cookie.takeIf { desktopCookie.isBlank() && mobileCookie.isBlank() }.orEmpty()
        fun normalized(value: String) = try { normalizeSessionCookie(value) } catch (_: IllegalArgumentException) { "" }
        val desktopCandidate = normalized(desktopCookie.ifBlank { unscoped })
        val mobileCandidate = normalized(mobileCookie.ifBlank { unscoped })
        var desktopProofChecked = false
        for (address in listOf("$desktop/ajax/getSpaConfig", "$desktop/ajax/config/getconfig", "$desktop/ajax/statuses/config", "$mobile/api/config")) {
            val isMobile = address.startsWith(mobile)
            if (isMobile && expectedUid != null && desktopCandidate.isNotBlank()) {
                desktopProofChecked = true
                verifyDesktopSession(expectedUid, desktopCandidate)?.let { return it }
            }
            val candidate = if (isMobile) mobileCandidate else desktopCandidate
            if (candidate.isBlank()) continue
            val config = webSessionProbe(address, candidate) ?: continue
            val uid = authenticatedUid(config, requireLoginFlag = isMobile) ?: continue
            require(expectedUid == null || uid == expectedUid) { "登录账号与返回会话不一致" }
            return VerifiedWebSession(candidate, isMobile, uid)
        }
        return if (!desktopProofChecked && desktopCandidate.isNotBlank()) verifyDesktopSession(expectedUid, desktopCandidate) else null
    }

    private suspend fun webSessionProbe(address: String, cookie: String, params: Map<String, String> = emptyMap()): JSONObject? {
        val xsrf = try { ApiClient.token(cookie) } catch (_: IllegalArgumentException) { null }
        val headers = if (xsrf != null && xsrf.all { it in ' '..'~' }) mapOf("X-XSRF-TOKEN" to xsrf) else emptyMap()
        return try { ApiClient.requireSuccess(api.raw(address, cookie, params, extraHeaders = headers, timeoutSeconds = 8).json()) }
        catch (_: IOException) { null }
    }
    suspend fun recoverWebSession(
        uid: String, saved: String, savedMobile: Boolean, nativeSession: Map<String, Any?>?,
        browserDesktop: String = "", browserMobile: String = ""
    ): VerifiedWebSession? {
        val nativeCookies = nativeSession?.takeIf { it["uid"] == uid }.orEmpty()
        val desktop = nativeCookies["desktopCookie"] as? String ?: ""
        val mobile = nativeCookies["mobileCookie"] as? String ?: ""
        val legacy = nativeCookies["cookie"] as? String ?: ""
        val candidates = listOf(
            Triple("", if (savedMobile) "" else saved, if (savedMobile) saved else ""),
            Triple("", browserDesktop, ""),
            Triple("", "", browserMobile),
            Triple("", desktop, ""),
            Triple("", "", mobile),
            Triple(legacy.takeIf { desktop.isBlank() && mobile.isBlank() && it != saved }.orEmpty(), "", "")
        )
        for ((unscoped, desktopCandidate, mobileCandidate) in candidates.distinct()) {
            if (unscoped.isBlank() && desktopCandidate.isBlank() && mobileCandidate.isBlank()) continue
            val result = try { verifyWebSession(uid, unscoped, desktopCandidate, mobileCandidate) }
                catch (_: IllegalArgumentException) { null }
            if (result != null) return result
        }
        return null
    }
    suspend fun feed(cookie: String, cursor: String, page: Int, group: String = "friends", ownerUid: String = ""): Page<Post> {
        val following = group in setOf("friends", "all_follow") || group.startsWith("11000") || group.startsWith("10001")
        val params = buildMap {
            put("page", page.toString()); put("count", "25"); put("trim_user", "0"); put("trim_page_recom", "1"); put("base_app", "0")
            if (!following) put("list_id", group)
            if (cursor != "0") put("max_id", cursor)
        }
        val hot = group.startsWith("102803") && !group.startsWith("102803_ctg1_-_ctg1_")
        val endpoints = when {
            hot -> emptyList()
            !following -> listOf("groups/timeline")
            page == 1 -> listOf("statuses/unread_friends_timeline", "statuses/friends/timeline")
            else -> listOf("statuses/friends/timeline")
        }
        var nativeEmpty = false
        var nativeReadDenied = false
        for (endpoint in endpoints) {
            try {
                val root = nativeGet(endpoint, params) ?: break
                val body = root.optJSONObject("data") ?: root
                val statuses = body.optJSONArray("statuses") ?: continue
                val posts = parsePosts(cookie, statuses.objects(), longText = false)
                if (posts.isNotEmpty()) {
                    return Page(posts, body.optString("max_id").takeIf { it.isNotBlank() && it != "0" } ?: posts.last().id)
                }
                nativeEmpty = true
            } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (failure: com.review.weiboauth.WeiboApi.ApiFailure) {
                if (failure.responseCode == "-105") { nativeReadDenied = true; break }
            }
            catch (_: Exception) { }
        }
        var oauthCode: String? = null
        suspend fun tryOAuthFollowing(): Page<Post>? {
            if (!nativeReadDenied || !following || !ownerUid.matches(Regex("[1-9][0-9]*"))) return null
            val pageParams = if (cursor.matches(Regex("[1-9][0-9]*"))) mapOf("max_id" to cursor) else mapOf("page" to "$page")
            val raw = try {
                withContext(Dispatchers.IO) { oauthFollowingRequest(ownerUid, pageParams + ("count" to "25")) }
            } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (failure: com.review.weiboauth.WeiboApi.ApiFailure) {
                oauthCode = failure.responseCode.orEmpty().takeIf { it.matches(Regex("-?[0-9]{1,12}")) }
                null
            } catch (_: Exception) { null }
            val statuses = raw?.let { JSONObject(it).optJSONArray("statuses") } ?: return null
            val posts = parsePosts(cookie, statuses.objects(), longText = false)
            val last = posts.mapNotNull { it.id.toBigIntegerOrNull() }.minOrNull()
            val next = if (statuses.length() >= 25 && last != null && last > java.math.BigInteger.ONE)
                (last - java.math.BigInteger.ONE).toString() else "0"
            return Page(posts, next)
        }
        fun nativeReadFailure(): IOException {
            val code = oauthCode
            return IOException(when (code) {
                null -> "内容服务拒绝原生关注流（-105），暂未找到可用的授权通道"
                "10014" -> "原生关注流被拒绝（-105），OAuth 关注流权限受限（10014）"
                else -> "内容服务拒绝原生关注流（-105），OAuth 关注流返回 $code"
            })
        }
        if (cookie.isBlank() && !hot) {
            tryOAuthFollowing()?.let { return it }
            if (nativeReadDenied) throw nativeReadFailure()
            if (nativeEmpty) return Page(emptyList())
            throw IOException("原生会话暂时无法读取关注流，请重试")
        }
        val path = if (following) "/ajax/feed/friendstimeline" else if (hot) "/ajax/feed/hottimeline" else "/ajax/feed/groupstimeline"
        val desktopParams = buildMap {
            put("list_id", if (following) "10001" else group); put("count", "25"); put("page", page.toString())
            if (hot) { put("group_id", group); put("containerid", group); put("extparam", "discover|new_feed"); put("count", "15") }
            put("refresh", if (page == 1) "0" else if (hot) "3" else "4"); if (cursor != "0") put("max_id", cursor)
        }
        var failure: Exception? = null
        var response = try { get(path, cookie, desktopParams) } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) { failure = e; null }
        if (following && page == 1 && response?.optJSONArray("statuses").objects().isEmpty()) {
            try { response = get("/ajax/feed/unreadfriendstimeline", cookie, desktopParams) } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) { if (failure == null) failure = e }
        }
        if (following && response?.optJSONArray("statuses").objects().isEmpty() && mobileOnly) {
            try { val mobile = api.get(ApiClient.MOBILE + "/feed/friends", cookie, params); response = mobile.optJSONObject("data") ?: mobile }
            catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) { if (failure == null) failure = e }
        }
        val body = response
        val array = body?.optJSONArray("statuses")
        if (array == null) {
            tryOAuthFollowing()?.let { return it }
            if (nativeReadDenied && following) throw nativeReadFailure()
            if (body == null) throw (failure ?: IOException("时间线暂不可用"))
            throw IOException("内容结构发生变化，请稍后重试")
        }
        val posts = parsePosts(cookie, array.objects(), longText = false)
        return Page(posts, body.optString("max_id").takeIf { it.isNotBlank() && it != "0" } ?: posts.lastOrNull()?.id ?: "0")
    }
    suspend fun groups(cookie: String): List<FeedGroup> {
        val nativeResult = try { nativeGet("groups/allgroups") } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled } catch (_: Exception) { null }
        if (nativeResult == null && cookie.isBlank()) throw IOException("原生会话暂时无法读取分组，请重试")
        val data = nativeResult ?: get("/ajax/feed/allGroups", cookie)
        val groups = data.optJSONArray("groups") ?: data.optJSONObject("data")?.optJSONArray("groups") ?: throw IOException("未返回分组列表")
        return groups.objects().flatMap { section -> section.optJSONArray("group").objects().mapNotNull { item ->
            val id = item.optString("gid").ifBlank { item.optString("id") }; val title = item.optString("title").ifBlank { item.optString("name") }
            if (id.isBlank() || title.isBlank()) null else FeedGroup(id, title, section.optString("title"))
        } }.distinctBy { it.id }
    }
    suspend fun verifyNativeAccount(uid: String): Boolean {
        if (!uid.matches(Regex("[1-9][0-9]*"))) return false
        val root = nativeGet("groups/allgroups") ?: return false
        val sections = root.optJSONArray("groups") ?: root.optJSONObject("data")?.optJSONArray("groups")
        val accountGroups = setOf("11000$uid", "10001$uid")
        return sections.objects().any { section ->
            section.optJSONArray("group").objects().any { it.optString("gid") in accountGroups }
        }
    }
    suspend fun search(cookie: String, query: String, page: Int): Page<Post> {
        val body = get("/ajax/statuses/search", cookie, mapOf("q" to query, "page" to page.toString(), "count" to "20"))
        val array = body.optJSONArray("statuses") ?: throw IOException("搜索暂不可用，请稍后重试")
        val posts = withContext(Dispatchers.Default) { array.objects().map(::parsePost) }
        return Page(posts, if (posts.isEmpty()) "0" else (page + 1).toString())
    }
    suspend fun detail(cookie: String, post: Post): Post {
        val body = if (cookie.isBlank() && native?.hasNativeSession() == true) {
            try {
                nativeGet("statuses/show", mapOf("id" to numericStatusId(post.id)))
                    ?: throw IOException("暂时无法读取正文")
            } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (_: Exception) { throw IOException("原生会话暂时无法读取正文，请重试") }
        } else if (mobileOnly) api.get(ApiClient.MOBILE + "/api/statuses/show", cookie, mapOf("id" to post.id))
        else get("/ajax/statuses/show", cookie, mapOf("id" to post.id))
        var result = withContext(Dispatchers.Default) { parsePost(body.optJSONObject("data") ?: body) }
        if (post.uid == result.uid && post.avatar.isNotEmpty()) result = result.copy(avatar = post.avatar)
        if (post.data.has("title")) result = result.copy(raw = JSONObject(result.raw).put("title", post.data.get("title")).toString())
        val images = mergeStatusMedia(post.images, result.images)
        result = result.copy(images = images, text = result.text.ifBlank { post.text }.withoutWebCardLinks(images))
        val detail = hydrateText(cookie, hydrateCards(cookie, result))
        val sourceFull = post.availableFullText()
        val complete = if (detail.id == post.id && detail.longText && sourceFull.length > detail.text.length && detail.availableFullText().isBlank())
            detail.copy(raw = JSONObject(detail.raw).put("full_text_raw", sourceFull).toString())
        else detail
        return retainStatusShortLinks(post, complete)
    }
    suspend fun comments(cookie: String, post: Post, cursor: String): Page<Comment> {
        val root = get("/ajax/statuses/buildComments", cookie, mapOf("id" to post.id, "uid" to post.uid,
            "is_reload" to "1", "is_show_bulletin" to "2", "is_mix" to "0", "count" to "20", "flow" to "0",
            "fetch_level" to "0", "locale" to "zh-CN", "max_id" to cursor))
        val body = root.optJSONObject("data") ?: root
        val array = body.optJSONArray("data") ?: throw IOException("评论暂不可用")
        return Page(array.objects().map {
            val user = it.optJSONObject("user") ?: JSONObject()
            Comment(it.optString("id"), user.optString("screen_name"), plainText(it.optString("text")),
                secureImage(user.optString("profile_image_url")), it.optInt("like_counts"))
        }, body.optString("max_id", "0"))
    }
}
