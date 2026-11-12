package com.review.compose

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

internal val backupNames = mapOf(
    "key_theme_color_index" to "palette", "key_is_pure_black_dark" to "pureBlack", "theme_mode" to "theme",
    "use_dynamic_color" to "dynamic", "use_floating_nav_bar" to "floating", "use_liquid_glass_effect" to "liquidGlass", "translucentNavigationGlass" to "translucentNavigationGlass",
    "key_enable_haptics" to "haptics", "key_use_custom_font_weight" to "customWeight", "key_custom_font_weight_delta" to "weight",
    "app_text_scale" to "textScale", "key_screen_refresh_rate_mode" to "refreshRate", "auto_clear_image_cache_threshold_mb" to "cacheLimit",
    "time_display_mode" to "timeMode", "show_weekday" to "weekday", "show_year" to "year", "show_timezone" to "timezone",
    "show_seconds" to "seconds", "show_source" to "source", "show_region" to "region", "weibo_suffix" to "suffix",
    "card_background_layout" to "cardLayout", "weibo_font_size" to "postFont", "weibo_font_line_height" to "postLine",
    "link_color_follow_theme" to "linkTheme", "show_remark_and_name" to "remark", "show_background_image" to "postBackground",
    "show_user_activity_icon" to "activityIcon", "large_image_mode" to "largeImages", "rounded_image_corners" to "roundImages",
    "show_menu_at_bottom" to "menuBottom", "show_ip_location_mode" to "ip", "show_profile_liked_tweets" to "profileLikes",
    "hot_search_vertical_layout" to "hotVertical"
)

fun validateBackup(data: JSONObject): JSONObject {
    require(data.optString("app") == "Review" && data.optString("version") in setOf("1.0", "2.0")) { "无效的 Review 备份" }
    if (data.getString("version") == "2.0") require(data.optString("backup_mode") in setOf("safe", "full")) { "无效的备份模式" }
    val values = data.optJSONObject("preferences") ?: error("备份缺少设置")
    for (key in values.keys()) {
        if (key !in BackupSchema.safe && key !in BackupSchema.credentials) continue
        val value = values.get(key)
        require(when (key) {
            in BackupSchema.booleans -> value is Boolean
            in BackupSchema.integers -> value is Number && value.toDouble().isFinite() && value.toDouble() == value.toLong().toDouble() && value.toLong() in Int.MIN_VALUE..Int.MAX_VALUE
            in BackupSchema.decimals -> value is Number && value.toDouble().isFinite()
            in BackupSchema.lists -> value is JSONArray && (0 until value.length()).all { value.get(it) is String }
            else -> value is String
        }) { "无效的备份设置：$key" }
    }
    val ranges=mapOf("theme_mode" to 0.0..2.0,"key_theme_color_index" to 0.0..7.0,"key_custom_font_weight_delta" to -300.0..300.0,
        "key_screen_refresh_rate_mode" to 0.0..8.0,"image_save_path_type" to 0.0..2.0,"video_save_path_type" to 0.0..2.0,"app_text_scale" to .8..1.5,
        "auto_clear_image_cache_threshold_mb" to 0.0..16384.0,"weibo_font_size" to 10.0..32.0,"weibo_font_line_height" to 1.0..3.0)
    ranges.forEach{(key,range)->if(values.has(key))require((values.get(key) as Number).toDouble() in range){"备份设置范围无效：$key"}}
    if (data.optString("backup_mode") == "full" && !data.isNull("native_session")) {
        require(data.get("native_session") is String) { "无效的原生会话" }
        val native = JSONObject(data.getString("native_session"))
        require(native.optString("uid").isNotBlank() && native.getString("uid") == values.optString("user_uid")) { "备份账号与原生会话不一致" }
    }
    for (key in listOf("weibo_full_cookie", "weibo_mobile_cookie", "weibo_desktop_cookie")) {
        val cookie = values.optString(key)
        require(cookie.length <= 32768 && cookie.all { it in ' '..'~' }) { "备份会话格式无效" }
    }
    return values
}

class BackupStore(private val context: Context, private val native: com.review.weiboauth.WeiboAuthManager,
    private val session:SessionStore=SessionStore(context),private val secret:SessionStore=SessionStore(context,"webdav")) {
    private val prefs = context.getSharedPreferences("preferences", 0)
    fun password() = secret.load()
    fun savePassword(value: String) = secret.save(value)

    suspend fun export(full: Boolean): JSONObject = withContext(Dispatchers.IO) {
        val revision=SessionStore.revision.get()
        val uid = prefs.getString("uid", "").orEmpty()
        val values = JSONObject()
        for (key in BackupSchema.safe) {
            val local = backupNames[key] ?: key
            val value: Any? = when (key) {
                "wb_browsing_history_statuses" -> JSONArray().apply { JSONArray(prefs.getString("history-$uid", "[]")).objects().forEach { put(Post.restore(it).data.toString()) } }
                "wb_browsing_history" -> JSONArray(JSONArray(prefs.getString("history-$uid", "[]")).objects().map { it.optString("id") })
                "blocked_user_ids" -> JSONArray(prefs.getStringSet("blocked-$uid", emptySet()).orEmpty().toList())
                "search_history_list" -> JSONArray(prefs.getString("searchHistory:$uid", "[]"))
                "muted_message_group_ids" -> JSONArray(prefs.all.filter { (key, value) -> key.startsWith("mute:$uid:") && value == true }.keys.map { it.removePrefix("mute:$uid:") })
                "message_unread_baselines_json", "message_contact_unread_baselines_json" -> {
                    val prefix = if (key == "message_unread_baselines_json") "read-interaction:$uid:" else "read:$uid:"
                    JSONObject().apply { prefs.all.forEach { (name, count) ->
                        if (name.startsWith(prefix) && count is Number) put(name.removePrefix(prefix).replace("direct_messages", "directMessages"), count.toInt())
                    } }.toString()
                }
                "image_save_path_type", "video_save_path_type" -> listOf("review", "self", "author").indexOf(prefs.getString(if (key.startsWith("image")) "imagePath" else "videoPath", "review")).coerceAtLeast(0)
                "key_current_preset_app_icon_id" -> listOf("default", "alias1", "alias2")[prefs.getFloat("icon", 0f).toInt().coerceIn(0, 2)]
                else -> prefs.all[local]?.let { if (it is Number && key in BackupSchema.integers) it.toInt() else it }
            }
            if (value != null) values.put(key, value)
        }
        if (full) {
            val cookie = if(uid.isNotEmpty())session.load()else ""
            values.put("user_uid", uid).put("is_logged_in", uid.isNotEmpty() && (cookie.isNotEmpty() || native.hasNativeSessionFor(uid)))
                .put("weibo_full_cookie", cookie).put(if (prefs.getBoolean("mobileOnly", false)) "weibo_mobile_cookie" else "weibo_desktop_cookie", cookie)
                .put("webdav_password", password())
        }
        JSONObject().put("app", "Review").put("version", "2.0").put("backup_mode", if (full) "full" else "safe")
            .put("exported_at", Instant.now().toString()).put("preferences", values).apply {
                if (full) put("native_session", if(uid.isNotEmpty())native.exportBackupSession(uid) ?: JSONObject.NULL else JSONObject.NULL)
                put("accountMode",if(uid.isEmpty())"GUEST"else"COOKIE")
                check(revision==SessionStore.revision.get()&&uid==prefs.getString("uid","").orEmpty()){ "账号已改变，请重新备份" }
            }
    }

    suspend fun restore(data: JSONObject,verifyWeb:suspend (String,String)->VerifiedWebSession={cookie,uid->Repository().importWebSession(cookie,uid)}): String = withContext(Dispatchers.IO) {
        val values = validateBackup(data)
        val full = data.optString("version") == "2.0" && data.optString("backup_mode") == "full"
        val oldPrefs = prefs.all.toMap()
        val oldUid = prefs.getString("uid", "").orEmpty()
        val revision=SessionStore.revision.get()
        val oldCookie=session.snapshot();val oldPassword=secret.snapshot()
        val oldNative=if(full)native.encryptedBackupSnapshot()else null
        val uid = if (full) values.optString("user_uid") else oldUid
        var verifiedWeb:VerifiedWebSession?=null
        var verifiedNative:String?=null
        val candidate=values.optString("weibo_desktop_cookie").ifBlank{values.optString("weibo_mobile_cookie")}.ifBlank{values.optString("weibo_full_cookie")}
        if(full && uid.isNotBlank()) {
            if(candidate.isNotBlank())try{verifiedWeb=verifyWeb(candidate,uid).also{check(it.uid==uid){"登录验证账号不匹配"}}}catch(e:kotlinx.coroutines.CancellationException){throw e}catch(_:Exception){}
            if(!data.isNull("native_session"))try{verifiedNative=native.verifyBackupSession(data.getString("native_session"),uid)}catch(e:kotlinx.coroutines.CancellationException){throw e}catch(_:Exception){}
        }
        kotlinx.coroutines.currentCoroutineContext().ensureActive()
        val restoreLogin=verifiedWeb!=null || verifiedNative!=null
        val editor = prefs.edit()
        for (key in values.keys()) {
            if (key !in BackupSchema.safe) continue
            val value = values.get(key)
            when (key) {
                "wb_browsing_history_statuses" -> editor.putString("history-$uid", JSONArray((value as JSONArray).let { array -> (0 until array.length()).map { parsePost(JSONObject(array.getString(it))).snapshot() } }).toString())
                "blocked_user_ids" -> editor.putStringSet("blocked-$uid", (value as JSONArray).let { array -> (0 until array.length()).map { array.getString(it) }.toSet() })
                "search_history_list" -> editor.putString("searchHistory:$uid", value.toString())
                "muted_message_group_ids" -> {
                    prefs.all.keys.filter { it.startsWith("mute:$uid:") }.forEach(editor::remove)
                    val ids = value as JSONArray
                    for (index in 0 until ids.length()) editor.putBoolean("mute:$uid:${ids.getString(index)}", true)
                }
                "message_unread_baselines_json", "message_contact_unread_baselines_json" -> {
                    val prefix = if (key == "message_unread_baselines_json") "read-interaction:$uid:" else "read:$uid:"
                    val counts = JSONObject(value as String)
                    prefs.all.keys.filter { it.startsWith(prefix) }.forEach(editor::remove)
                    counts.keys().forEach { name ->
                        val count = counts.get(name)
                        require(count is Number && count.toDouble().isFinite() && count.toDouble() >= 0 && count.toDouble() <= Int.MAX_VALUE) { "无效的未读基线" }
                        editor.putFloat(prefix + name.replace("directMessages", "direct_messages"), count.toFloat())
                    }
                }
                "image_save_path_type", "video_save_path_type" -> editor.putString(if (key.startsWith("image")) "imagePath" else "videoPath", listOf("review", "self", "author")[(value as Number).toInt().coerceIn(0, 2)])
                "key_current_preset_app_icon_id" -> editor.putFloat("icon", listOf("default", "alias1", "alias2").indexOf(value).coerceAtLeast(0).toFloat())
                else -> putPreference(editor, backupNames[key] ?: key, value)
            }
        }
        SessionStore.accountWrites.withLock {
            check(SessionStore.revision.get()==revision && session.snapshot()==oldCookie && secret.snapshot()==oldPassword && prefs.all==oldPrefs) { "账号或设置已改变，请重新恢复" }
            withContext(NonCancellable) { synchronized(native) {
                check(oldNative==null || native.encryptedBackupSnapshot()==oldNative){"原生会话已改变，请重新恢复"}
                var appliedCookie:Map<String,*>?=null;var appliedPassword:Map<String,*>?=null;var appliedPrefs:Map<String,*>?=null;var appliedNative=false
                try {
                    if (full) {
                        if(restoreLogin) {
                            check(native.restoreBackupSession(verifiedNative,uid));appliedNative=true
                            session.save(verifiedWeb?.cookie.orEmpty(),recoverUnreadable=true);appliedCookie=session.snapshot()
                            editor.putString("uid",uid).putBoolean("mobileOnly",verifiedWeb?.mobileOnly?:false)
                        }
                        secret.save(values.optString("webdav_password"),recoverUnreadable=true);appliedPassword=secret.snapshot()
                    }else if(listOf("webdav_url","webdav_username").any{values.has(it)&&values.opt(it)!=oldPrefs[it]}) {
                        secret.save("");appliedPassword=secret.snapshot()
                    }
                    val committed=editor.commit();appliedPrefs=prefs.all.toMap()
                    check(committed){"备份设置写入失败"}
                }catch(failure:Exception){
                    try {
                        appliedCookie?.let{session.rollback(it,oldCookie)}
                        appliedPassword?.let{secret.rollback(it,oldPassword)}
                        if(appliedNative && oldNative!=null)native.restoreEncryptedBackupSnapshot(oldNative)
                        appliedPrefs?.let { applied ->
                            val rollback=prefs.edit()
                            (applied.keys+oldPrefs.keys).filter{applied[it]!=oldPrefs[it]&&prefs.all[it]==applied[it]}.forEach{key->
                                val value=oldPrefs[key]
                                when(value){null->rollback.remove(key);is Int->rollback.putInt(key,value);is Long->rollback.putLong(key,value);else->putPreference(rollback,key,value)}
                            }
                            check(rollback.commit())
                        }
                    }catch(rollback:Exception){failure.addSuppressed(rollback)}
                    throw failure
                }
            } }
        }
        when {
            restoreLogin -> "设置和本地资料已恢复，账号登录已通过验证并恢复。"
            full && (candidate.isNotBlank() || !data.isNull("native_session")) -> "资料已恢复，但账号登录未恢复，请重试或重新登录。当前会话保持不变。"
            full -> "设置和本地资料已恢复。备份未包含有效登录凭据，当前会话保持不变。"
            else -> "设置和本地资料已恢复，当前账号登录保持不变。"
        }
    }
}

private fun putPreference(editor: SharedPreferences.Editor, key: String, value: Any) {
    when (value) {
        is Boolean -> editor.putBoolean(key, value)
        is Number -> if (key == "theme") editor.putInt(key, value.toInt()) else editor.putFloat(key, value.toFloat())
        is Set<*> -> editor.putStringSet(key, value.filterIsInstance<String>().toSet())
        else -> editor.putString(key, value.toString())
    }
}

data class DavConfig(val server: String, val username: String, val password: String, val directory: String) {
    fun base(): HttpUrl {
        val value = server.trim().let { if ("://" in it) it else "https://$it" }.toHttpUrl()
        require(value.isHttps || value.host in setOf("localhost", "127.0.0.1", "::1")) { "WebDAV 请使用加密的 https:// 协议" }
        require(value.username.isEmpty() && value.password.isEmpty() && value.query == null && value.fragment == null) { "服务器地址不能包含凭据、查询参数或片段" }
        require(username.isNotBlank() && ':' !in username && password.isNotBlank()) { "请输入账号和授权密码" }
        return value.newBuilder().apply { if (!value.encodedPath.endsWith('/')) addPathSegment("") }.build()
    }
    fun folder() = base().newBuilder().addPathSegment(directory.trim().ifBlank { "Review" }.also { require(it !in setOf(".", "..") && '/' !in it && '\\' !in it) { "请输入单个备份文件夹名称" } }).addPathSegment("").build()
}

class DavClient {
    private val transport = WebDavTransport(OkHttpClient(), 16L * 1024 * 1024)
    private suspend fun request(config: DavConfig, url: HttpUrl, method: String, body: String? = null, accepted: Set<Int>): String =
        transport.request(url, method, Credentials.basic(config.username, config.password, Charsets.UTF_8), body?.toByteArray(Charsets.UTF_8))
            .requireStatus(if (method == "GET") "下载" else method, accepted).bytes.toString(Charsets.UTF_8)
    suspend fun test(config: DavConfig) { request(config, config.base(), "PROPFIND", accepted = setOf(200, 207)) }
    suspend fun upload(config: DavConfig, data: JSONObject): Boolean {
        val folder = config.folder()
        request(config, folder, "MKCOL", accepted = setOf(200, 201, 405))
        val body = data.toString(2)
        request(config, folder.newBuilder().addPathSegment("backup_review_latest.json").build(), "PUT", body, setOf(200, 201, 204))
        return try {
            request(config, folder.newBuilder().addPathSegment("backup_review_${System.currentTimeMillis()}.json").build(), "PUT", body, setOf(200, 201, 204)); true
        } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (_: Exception) { false }
    }
    suspend fun download(config: DavConfig) = transport.request(config.folder().newBuilder().addPathSegment("backup_review_latest.json").build(), "GET",
        Credentials.basic(config.username, config.password, Charsets.UTF_8)).requireStatus("下载", setOf(200)).json().also(::validateBackup)
}
