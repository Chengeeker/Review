package com.review.compose

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Base64
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okio.BufferedSink
import okio.source
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.security.MessageDigest

data class Upload(val id: String, val type: String, val group: String = "", val pid: String = id)
fun findJson(value: Any?, key: String, depth: Int = 0): Any? {
    if (depth > 12) return null
    if (value is JSONObject) {
        if (value.has(key) && !value.isNull(key)) return value.opt(key)
        value.keys().forEach { findJson(value.opt(it), key, depth + 1)?.let { found -> return found } }
    } else if (value is JSONArray) for (i in 0 until value.length()) findJson(value.opt(i), key, depth + 1)?.let { return it }
    return null
}
fun publishFields(text: String, visibility: Int, media: List<Upload>, statement: Int = 0, extras: Map<String, String> = emptyMap()): Map<String, String> {
    require(text.isNotBlank() || media.isNotEmpty()) { "请输入内容或添加媒体" }
    require(visibility in setOf(0, 1, 5, 6, 10)) { "尚未选择可用的可见范围" }
    require(media.size <= 9 && (media.none { it.type == "video" } || media.size == 1)) { "图片与视频不能混合发布" }
    return buildMap {
        put("content", text); put("visible", "$visibility"); put("share_id", ""); put("vote", "")
        if (statement != 0) put("mblog_statement", "$statement")
        putAll(extras)
        if (media.isNotEmpty()) {
            put("need_transcode", "1")
            put("pic_id", JSONArray(media.map { JSONObject().put("type", it.type).put("media_id", it.id).put("pid", it.pid)
                .put("short_url", "").put("media_group_id", it.group).put("tags", JSONArray()) }).toString())
        }
    }
}
private fun uploadPid(text: String): String? {
    val root = runCatching { JSONObject(text) }.getOrNull()
    for (key in listOf("pid", "pic_id", "picId", "image_id", "imageId", "media_id", "mediaId")) {
        findJson(root, key)?.toString()?.takeIf { it.matches(Regex("[a-zA-Z0-9_-]+")) }?.let { return it }
    }
    Regex("\"pid\"\\s*:\\s*\"([a-zA-Z0-9_-]+)\"").find(text)?.groupValues?.get(1)?.let { return it }
    val encoded = root?.opt("data") as? String ?: return null
    return runCatching { String(Base64.decode(encoded, Base64.DEFAULT)) }.getOrNull()?.let { Regex("\"pid\"\\s*:\\s*\"([a-zA-Z0-9_-]+)\"").find(it)?.groupValues?.get(1) }
}
suspend fun Repository.uploadImage(context: Context, uri: Uri, cookie: String): Upload {
    val mime = context.contentResolver.getType(uri)?.takeIf { it.startsWith("image/") } ?: "image/jpeg"
    val body = object : RequestBody() {
        override fun contentType() = "application/octet-stream".toMediaType()
        override fun writeTo(sink: BufferedSink) { context.contentResolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(65536); var total = 0L
            while (true) { val n = input.read(buffer); if (n < 0) break; total += n; require(total <= 32L * 1024 * 1024) { "图片超过大小上限" }; sink.write(buffer, 0, n) }
        } ?: throw IOException("无法读取所选图片") }
    }
    try {
        val response = api.raw("https://picupload.weibo.com/interface/pic_upload.php", cookie, mapOf("app" to "miniblog", "s" to "json", "p" to "1", "data" to "1"), body,
            extraHeaders = mapOf("Referer" to "https://weibo.com/"))
        uploadPid(response.text)?.let { return Upload(it, mime) }
    } catch (e: CancellationException) { throw e }
    catch (_: IOException) { }
    val bytes = withContext(Dispatchers.IO) { context.contentResolver.openInputStream(uri)?.use {
        val bytes = it.readBytesBounded(32 * 1024 * 1024); bytes
    } ?: throw IOException("无法读取图片") }
    val fallback = FormBody.Builder().add("b64_data", Base64.encodeToString(bytes, Base64.NO_WRAP)).build()
    val response = api.raw("https://picupload.weibo.com/interface/pic_upload.php", cookie, mapOf("mime" to mime, "data" to "base64", "url" to "0", "markpos" to "1", "logo" to "", "nick" to "0", "marks" to "0", "app" to "miniblog"), fallback,
        extraHeaders = mapOf("Referer" to "https://weibo.com/", "Origin" to "https://weibo.com"))
    return Upload(uploadPid(response.text) ?: throw IOException("图片上传未返回标识"), mime)
}
fun java.io.InputStream.readBytesBounded(maximum: Int): ByteArray {
    val output = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(16384)
    while (true) { val n = read(buffer); if (n < 0) break; if (output.size() + n > maximum) throw IOException("文件超过此操作可处理的大小"); output.write(buffer, 0, n) }
    return output.toByteArray()
}
suspend fun Repository.uploadVideo(context: Context, uri: Uri, cookie: String, progress: (Float) -> Unit): Upload {
    var name = "video.mp4"
    var size = -1L
    withContext(Dispatchers.IO) {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { if (it.moveToFirst()) { name = it.getString(0); size = it.getLong(1) } }
    }
    require(size in 1..(15L * 1024 * 1024 * 1024)) { "视频大小无法读取或超过 15GB" }
    val group = findJson(get("/ajax/multimedia/mediaGroupInit", cookie), "media_group_id")?.toString().orEmpty()
    require(group.isNotBlank()) { "未取得视频上传组" }
    val dispatch = api.post(ApiClient.DESKTOP + "/ajax/multimedia/dispatch", cookie,
        mapOf("source" to "339644097", "types" to "video", "version" to "4", "auth_accept" to "video", "size" to "$size", "timeout" to "180000"), verify = false)
    val video = findJson(dispatch, "video") as? JSONObject ?: throw IOException("未取得视频上传地址")
    fun address(key: String): String {
        val url = video.getString(key).toHttpUrl()
        require(url.isHttps && url.username.isEmpty() && url.password.isEmpty() &&
            (url.host.endsWith(".weibo.com") || url.host.endsWith(".weibocdn.com") || url.host.endsWith(".sina.com.cn") || url.host.endsWith(".sinavideo.cn"))) { "视频上传地址未通过校验" }
        return url.toString()
    }
    val initUrl = address("init_url"); val uploadUrl = address("upload_url"); val checkUrl = address("check_url")
    val boundary = "2067456weiboPro${System.currentTimeMillis()}"
    val init = JSONObject().put("mediaprops", JSONObject().put("screenshot", 1).put("media_group_id", group).toString()).toString()
    val initBody = "--$boundary\r\nContent-Disposition: form-data; name=\"biz_file\"\r\n\r\n$init\r\n--$boundary--\r\n".toRequestBody("multipart/mixed; boundary=$boundary".toMediaType())
    val root = ApiClient.requireSuccess(api.raw(initUrl, cookie, parameters = mapOf("source" to "339644097", "size" to "$size", "name" to name, "type" to "video", "client" to "web", "session_id" to "${System.currentTimeMillis()}-$size"), body = initBody,
        extraHeaders = mapOf("Referer" to "https://weibo.com/")).json())
    val data = root.optJSONObject("data") ?: root
    val uploadId = data.getString("upload_id"); val mediaId = data.getString("media_id"); val auth = data.getString("auth")
    val chunkSize = (data.optJSONObject("strategy")?.optLong("chunk_size", 8192) ?: 8192) * 1024
    require(chunkSize in 1024..(64L * 1024 * 1024)) { "上传分片大小不受支持" }
    val count = (size + chunkSize - 1) / chunkSize
    withContext(Dispatchers.IO) {
        context.contentResolver.openInputStream(uri)?.use { input ->
            for (index in 0 until count) {
                val start = index * chunkSize
                val length = minOf(chunkSize, size - start).toInt()
                val bytes = ByteArray(length)
                var offset = 0
                while (offset < length) { val n = input.read(bytes, offset, length - offset); if (n < 0) throw IOException("视频文件长度发生变化"); offset += n }
                val hash = MessageDigest.getInstance("MD5").digest(bytes).joinToString("") { "%02x".format(it) }
                val result = api.raw(uploadUrl, parameters = mapOf("source" to "339644097", "upload_id" to uploadId, "media_id" to mediaId, "upload_protocol" to "binary", "type" to "video", "client" to "web", "check" to hash, "index" to "$index", "size" to "$length", "start_loc" to "$start", "count" to "$count"),
                    body = bytes.toRequestBody("application/octet-stream".toMediaType()), extraHeaders = mapOf("Referer" to "https://weibo.com/", "X-Up-Auth" to auth), timeoutSeconds = 180)
                ApiClient.requireSuccess(result.json())
                withContext(Dispatchers.Main) { progress((start + length).toFloat() / size) }
            }
        } ?: throw IOException("无法读取视频")
    }
    val finish = FormBody.Builder().apply {
        mapOf("source" to "339644097", "upload_id" to uploadId, "media_id" to mediaId, "upload_protocol" to "binary", "count" to "$count", "action" to "finish", "size" to "$size", "client" to "web", "status" to "").forEach { (k, v) -> add(k, v) }
    }.build()
    val checked = ApiClient.requireSuccess(api.raw(checkUrl, cookie, body = finish, extraHeaders = mapOf("Referer" to "https://weibo.com/", "X-Up-Auth" to auth)).json())
    require(checked.optString("result") in setOf("true", "1")) { "视频上传尚未完成" }
    return Upload(mediaId, "video", group, "")
}
