package com.review.compose

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.coroutineContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONException
import org.json.JSONObject

internal data class WebDavResponse(val code: Int, val bytes: ByteArray, val location: String?) {
    fun requireStatus(stage: String, accepted: Set<Int>): WebDavResponse {
        check(code in accepted) {
            val reason = when (code) {
                401 -> "身份验证失败，请检查账号和授权密码"
                403 -> "权限不足，请检查该操作的权限"
                404 -> "该路径没有备份文件"
                429 -> "请求过于频繁，请稍后重试"
                in 300..399 -> "服务器要求跳转，当前操作不能自动跳转"
                in 500..599 -> "服务器暂时出错，请稍后重试"
                else -> "服务器未确认操作成功"
            }
            "WebDAV $stage 失败（HTTP $code）：$reason"
        }
        return this
    }

    fun json(): JSONObject {
        check(bytes.isNotEmpty()) { "WebDAV 下载内容为空，未恢复任何资料" }
        return try { JSONObject(bytes.toString(Charsets.UTF_8)) }
        catch (_: JSONException) { error("WebDAV 下载内容不是有效的 JSON 备份，未恢复任何资料") }
    }
}

internal fun webDavError(error: Exception): String = when {
    error.suppressed.isNotEmpty() -> "操作失败，部分回退未完成，请检查当前资料和存储空间后重试"
    error.javaClass.simpleName=="SecretReadFailure" -> error.message?:"加密资料无法读取，原资料已保留"
    error.message?.startsWith("WebDAV ") == true -> error.message!!
    error is IllegalArgumentException -> "输入或备份格式不兼容，未完成操作，请检查设置和备份文件"
    error is IOException -> "网络请求失败或超时，请检查网络后重试"
    else -> "操作未完成，请检查存储空间、备份文件和当前账号状态后重试"
}

internal class WebDavTransport(client: OkHttpClient, private val maxBytes: Long) {
    // Preserve proxy/TLS settings, but a download CDN must never receive application credentials.
    private val http = client.newBuilder().apply {
        interceptors().clear()
        networkInterceptors().clear()
    }.authenticator(Authenticator.NONE).proxyAuthenticator(Authenticator.NONE)
        .cookieJar(CookieJar.NO_COOKIES).cache(null)
        .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).callTimeout(60, TimeUnit.SECONDS).build()

    suspend fun request(url: HttpUrl, method: String, authorization: String, bytes: ByteArray? = null): WebDavResponse {
        require(url.username.isEmpty() && url.password.isEmpty()) { "WebDAV 地址不能包含账号信息" }
        require(url.isHttps || url.host in setOf("localhost", "127.0.0.1", "::1")) { "WebDAV 地址必须使用 HTTPS" }
        require(bytes == null || bytes.size <= maxBytes) { "备份超过大小上限" }
        var current = url.newBuilder().fragment(null).build()
        var auth: String? = authorization
        val visited = mutableSetOf<HttpUrl>()
        for (hop in 0..5) {
            coroutineContext.ensureActive()
            check(visited.add(current)) { "WebDAV 下载地址循环跳转，未恢复任何资料" }
            val body = if (method in setOf("GET", "HEAD")) null else (bytes ?: ByteArray(0)).toRequestBody("application/json; charset=utf-8".toMediaType())
            val request = Request.Builder().url(current).method(method, body).apply {
                auth?.let { header("Authorization", it) }
                if (method == "PROPFIND") header("Depth", "0")
            }.build()
            val response = execute(request)
            if (method != "GET" || response.code !in setOf(301, 302, 303, 307, 308)) return response
            check(hop < 5) { "WebDAV 下载跳转超过五次，未恢复任何资料" }
            val location = response.location
            check(!location.isNullOrBlank() && location.none { it.code < 32 || it.code == 127 }) { "WebDAV 下载跳转缺少有效地址（HTTP ${response.code}），未恢复任何资料" }
            val next = current.resolve(location)?.newBuilder()?.fragment(null)?.build()
                ?: error("WebDAV 下载跳转地址无效，未恢复任何资料")
            check(next.username.isEmpty() && next.password.isEmpty()) { "WebDAV 下载跳转地址包含账号信息，已停止恢复" }
            val sameOrigin = next.scheme == current.scheme && next.host == current.host && next.port == current.port
            check(next.isHttps || sameOrigin) { "WebDAV 下载跳转未使用 HTTPS，已停止恢复" }
            if (!sameOrigin) auth = null
            current = next
        }
        error("WebDAV 下载跳转超过五次，未恢复任何资料")
    }

    private suspend fun execute(request: Request): WebDavResponse = suspendCancellableCoroutine { continuation ->
        val call = http.newCall(request)
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (continuation.isActive) continuation.resumeWithException(IOException("WebDAV ${request.method} 网络请求失败或超时，请检查网络后重试"))
            }
            override fun onResponse(call: Call, response: Response) {
                try {
                    val result = response.use {
                        val output = ByteArrayOutputStream()
                        if (request.method == "GET" && it.code == 200) {
                            val body = it.body ?: error("WebDAV 下载内容为空，未恢复任何资料")
                            check(body.contentLength() <= maxBytes) { "备份超过大小上限" }
                            body.byteStream().use { input ->
                                val buffer = ByteArray(8192)
                                while (true) {
                                    continuation.context.ensureActive()
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    check(output.size().toLong() + count <= maxBytes) { "备份超过大小上限" }
                                    output.write(buffer, 0, count)
                                }
                            }
                        }
                        WebDavResponse(it.code, output.toByteArray(), it.header("Location"))
                    }
                    if (continuation.isActive) continuation.resume(result)
                } catch (e: Exception) {
                    if (continuation.isActive) continuation.resumeWithException(
                        if (e is IOException) IOException("WebDAV 下载中断或超时，未恢复任何资料") else e
                    )
                }
            }
        })
    }
}
