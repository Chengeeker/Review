package com.review.compose

import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONObject
import java.io.IOException
import java.net.URLDecoder
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

data class ApiResponse(val text: String, val headers: Headers) {
    fun json(): JSONObject = runCatching { JSONObject(text) }.getOrElse { throw IOException("服务返回了非数据页面，请检查登录状态") }
}

internal class ApiHttpFailure(val status: Int, message: String) : IOException(message)

class ApiClient {
    companion object {
        const val DESKTOP = "https://weibo.com"
        const val MOBILE = "https://m.weibo.cn"
        const val CHAT = "https://api.weibo.com"
        const val USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        const val MOBILE_USER_AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
        val sessionHosts = setOf("weibo.com", "s.weibo.com", "m.weibo.cn", "api.weibo.com", "rm.api.weibo.com", "upload.api.weibo.com", "picupload.weibo.com", "h5.video.weibo.com")
        internal fun videoUploadSessionAllowed(url: HttpUrl): Boolean = url.isHttps && url.port == 443 &&
            url.username.isEmpty() && url.password.isEmpty() && Regex("(?:[a-z]{2})?fileplatform\\.api\\.weibo\\.com").matches(url.host) &&
            url.encodedPath in setOf("/2/fileplatform/init.json", "/2/fileplatform/check.json")
        fun token(cookie: String) = Regex("(?:^|;\\s*)XSRF-TOKEN=([^;]+)", RegexOption.IGNORE_CASE).find(cookie)?.groupValues?.get(1)
            ?.takeIf { it.isNotBlank() && it != "deleted" }?.let { URLDecoder.decode(it, "UTF-8") }
        fun requireSuccess(body: JSONObject): JSONObject {
            val ok = body.opt("ok")
            if (ok == false || (ok != null && ok.toString().toDoubleOrNull()?.let { it <= 0 } == true) ||
                body.opt("result") == false || body.optString("error_code").let { it.isNotEmpty() && it != "0" } || body.optString("error").isNotEmpty()) {
                throw IOException(body.optString("msg").ifBlank { body.optString("message") }.ifBlank { body.optString("error") }.ifBlank { "服务器拒绝了请求，请重试或重新登录" }.take(240))
            }
            return body
        }
        fun acceptedMutation(body: JSONObject): Boolean {
            fun hasId(value: JSONObject) = listOf("id", "mid").any { value.optString(it).trim() !in setOf("", "0", "null") }
            return body.opt("ok")?.toString() in setOf("1", "true") ||
                body.opt("result")?.toString() in setOf("1", "true") || hasId(body) ||
                body.optJSONObject("data")?.let(::hasId) == true
        }
    }
    private val client = OkHttpClient.Builder().connectTimeout(12, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS)
        .callTimeout(40, TimeUnit.SECONDS).followRedirects(false).followSslRedirects(false).build()
    private val tokens = java.util.concurrent.ConcurrentHashMap<String, String>()
    @Volatile private var mobileSessionCookie = ""

    fun configureSession(cookie: String, mobileOnly: Boolean) {
        mobileSessionCookie = if (mobileOnly) cookie else ""
        clearSessionCache()
    }

    fun cookieFor(address: String, cookie: String): String {
        if (cookie.isEmpty() || cookie != mobileSessionCookie) return cookie
        val host = address.toHttpUrl().host
        return if (host == "weibo.cn" || host.endsWith(".weibo.cn")) cookie else ""
    }

    suspend fun raw(address: String, cookie: String = "", parameters: Map<String, String> = emptyMap(),
                    body: RequestBody? = null, method: String = if (body == null) "GET" else "POST",
                    extraHeaders: Map<String, String> = emptyMap(), maxBytes: Long = 8L * 1024 * 1024, timeoutSeconds: Long = 40,
                    html: Boolean = false): ApiResponse {
        val url = address.toHttpUrl().newBuilder().apply { parameters.forEach { (k, v) -> addQueryParameter(k, v) } }.build()
        require(url.isHttps && url.username.isEmpty() && url.password.isEmpty()) { "只允许安全连接" }
        require(cookie.isEmpty() || url.host in sessionHosts || videoUploadSessionAllowed(url)) { "此地址不能使用账号会话" }
        require(cookie.length <= 32768 && cookie.all { it in ' '..'~' }) { "会话包含无效字符" }
        if (cookieFor(url.toString(), cookie) != cookie) throw IOException("此操作需要桌面网页会话")
        val referer = if (url.host == "api.weibo.com") "$CHAT/chat/" else "${url.scheme}://${url.host}/"
        val mobile = url.host == "m.weibo.cn"
        val builder = Request.Builder().url(url).method(method, body)
            .header("User-Agent", if (mobile) MOBILE_USER_AGENT else USER_AGENT)
            .header("Accept", if (html) "text/html,application/xhtml+xml" else "application/json, text/plain, */*")
            .header("Referer", referer)
        if (!html) builder.header("X-Requested-With", "XMLHttpRequest")
        if (cookie.isNotEmpty()) {
            val appendMobileLogin = mobile && (method != "GET" || cookie == mobileSessionCookie) &&
                !Regex("(?:^|;\\s*)MLOGIN=", RegexOption.IGNORE_CASE).containsMatchIn(cookie)
            builder.header("Cookie", if (appendMobileLogin) "$cookie; MLOGIN=1" else cookie)
        }
        extraHeaders.forEach { (k, v) -> builder.header(k, v) }
        return suspendCancellableCoroutine { continuation ->
            val requestClient = if (timeoutSeconds > 40) client.newBuilder().readTimeout(timeoutSeconds, TimeUnit.SECONDS).writeTimeout(timeoutSeconds, TimeUnit.SECONDS).build() else client
            val call = requestClient.newCall(builder.build())
            call.timeout().timeout(timeoutSeconds, TimeUnit.SECONDS)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (!continuation.isCancelled) continuation.resumeWithException(IOException(if (body == null) "连接失败，请检查网络" else "请求结果未确认，请先刷新核实，避免重复提交"))
                }
                override fun onResponse(call: Call, response: Response) {
                    try {
                        val result = response.use {
                            if (it.code in 300..399 || it.code == 401 || it.code == 403) throw ApiHttpFailure(it.code, "会话失效或访问受限，请重新登录")
                            if (!it.isSuccessful) throw IOException("请求失败（HTTP ${it.code}）")
                            val source = it.body?.source() ?: throw IOException("服务器没有返回内容")
                            source.request(maxBytes + 1)
                            if (source.buffer.size > maxBytes) throw IOException("返回内容超过处理上限")
                            ApiResponse(source.readUtf8(), it.headers)
                        }
                        if (!continuation.isCancelled) continuation.resume(result)
                    } catch (e: Exception) { if (!continuation.isCancelled) continuation.resumeWithException(e) }
                }
            })
        }
    }
    suspend fun get(address: String, cookie: String, params: Map<String, String> = emptyMap()) = requireSuccess(raw(address, cookie, params).json())
    suspend fun xsrf(address: String, cookie: String, force: Boolean = false): String {
        if (cookieFor(address, cookie) != cookie) throw IOException("此操作需要桌面网页会话")
        val host = address.toHttpUrl().host
        val key = "$host:$cookie"
        if (!force) {
            tokens[key]?.let { return it }
            token(cookie)?.let { return it }
        }
        val origin = if (host == "m.weibo.cn") MOBILE else DESKTOP
        val paths = if (origin == MOBILE) listOf("/api/config") else listOf("/ajax/getSpaConfig", "/ajax/statuses/config", "/ajax/config/getconfig")
        for (path in paths) {
            val response = try { raw(origin + path, cookie) }
                catch (e: kotlinx.coroutines.CancellationException) { throw e }
                catch (_: IOException) { continue }
            val value = response.headers.values("Set-Cookie").firstNotNullOfOrNull(::token)
                ?: runCatching { response.json().optJSONObject("data")?.optString("st") }.getOrNull()?.takeIf { it.isNotBlank() }
            if (value != null) { tokens.clear(); tokens[key] = value; return value }
        }
        throw IOException("未获得操作校验信息，请重新登录")
    }
    suspend fun post(address: String, cookie: String, fields: Map<String, String>, verify: Boolean = true): JSONObject {
        require(cookie.isNotEmpty()) { "此操作需要网页会话，请导入同一账号的 Cookie" }
        val url = address.toHttpUrl()
        suspend fun send(token: String): JSONObject {
            val form = FormBody.Builder().apply { fields.forEach { (k, v) -> add(k, v) }; if (url.host == "m.weibo.cn" && "st" !in fields) add("st", token) }.build()
            val requestCookie = if (ApiClient.token(cookie) == token) cookie else cookie.split(';')
                .filterNot { it.substringBefore('=').trim().equals("XSRF-TOKEN", true) }
                .joinToString("; ") + "; XSRF-TOKEN=" + java.net.URLEncoder.encode(token, "UTF-8")
            return requireSuccess(raw(address, requestCookie, body = form,
                extraHeaders = mapOf("X-XSRF-TOKEN" to token, "Origin" to "${url.scheme}://${url.host}")).json())
        }
        val result = try { send(xsrf(address, cookie)) }
        catch (failure: ApiHttpFailure) {
            if (failure.status != 403) throw failure
            send(xsrf(address, cookie, force = true))
        }
        if (verify && !acceptedMutation(result)) throw IOException("服务器未确认操作成功，请刷新核实")
        return result
    }
    fun clearSessionCache() { tokens.clear() }
}
