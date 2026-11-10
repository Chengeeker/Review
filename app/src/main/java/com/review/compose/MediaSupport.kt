package com.review.compose

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.LruCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import kotlin.coroutines.coroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.sqrt

private suspend fun okhttp3.Call.download(file: File, limit: Long): String? = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(object : okhttp3.Callback {
        override fun onFailure(call: okhttp3.Call, failure: IOException) { if (!continuation.isCancelled) continuation.resumeWithException(failure) }
        override fun onResponse(call: okhttp3.Call, response: okhttp3.Response) {
            try {
                val redirect = response.use {
                    if (it.code in 300..399) it.header("Location")?.takeIf(String::isNotBlank) ?: throw IOException("无效的媒体跳转")
                    else {
                        if (!it.isSuccessful) throw IOException("媒体下载失败（${it.code}）")
                        val body = it.body ?: throw IOException("媒体为空")
                        require(body.contentLength() <= limit) { "媒体超过大小上限" }
                        body.byteStream().use { input -> file.outputStream().use { output ->
                            val buffer = ByteArray(65536); var count = 0L
                            while (true) { if (call.isCanceled()) throw IOException("已取消下载"); val n = input.read(buffer); if (n < 0) break; count += n; require(count <= limit) { "媒体超过大小上限" }; output.write(buffer, 0, n) }
                        } }
                        null
                    }
                }
                if (!continuation.isCancelled) continuation.resume(redirect)
            } catch (e: Exception) { if (!continuation.isCancelled) continuation.resumeWithException(e) }
            finally { if (call.isCanceled()) file.delete() }
        }
    })
}

internal fun highQualityPreviewUrl(url: String): String = runCatching {
    val uri = java.net.URI(url)
    if (uri.scheme != "https" || uri.userInfo != null || !uri.host.orEmpty().endsWith(".sinaimg.cn") || uri.path.endsWith(".gif", true)) return@runCatching url
    val parts = uri.rawPath.removePrefix("/").split('/')
    if (parts.size != 2 || !Regex("thumbnail|middle|bmiddle|small|square|(?:orj|mw|cmw)[0-9]+").matches(parts[0])) return@runCatching url
    val pixels = Regex("[0-9]+").find(parts[0])?.value?.toIntOrNull()
    if (pixels != null && pixels >= 960) return@runCatching url
    val start = uri.scheme.length + 3 + uri.rawAuthority.length + 1
    url.replaceRange(start, start + parts[0].length, "orj960")
}.getOrDefault(url)

internal fun previewDecodeSize(media: Media, width: Int, height: Int, fit: Boolean): androidx.compose.ui.unit.IntSize {
    val w = width.coerceIn(1, 2048); val h = height.coerceIn(1, 2048)
    if (media.width <= 0 || media.height <= 0) {
        val scale = minOf(1.0, sqrt(3_000_000.0 / w / h))
        return androidx.compose.ui.unit.IntSize(maxOf(1, (w * scale).toInt()), maxOf(1, (h * scale).toInt()))
    }
    val x = w.toDouble() / media.width; val y = h.toDouble() / media.height
    val scale = minOf(if (fit) minOf(x, y) else maxOf(x, y), 1.0, sqrt(3_000_000.0 / media.width / media.height))
    return androidx.compose.ui.unit.IntSize(maxOf(1, (media.width * scale).toInt()), maxOf(1, (media.height * scale).toInt()))
}

fun pictureMedia(info: JSONObject, url: String): Media {
    val gif = url.substringBefore('?').endsWith(".gif", true) || info.optString("type") == "gif"
    val explicit = info.optString("livephoto_video").ifBlank { info.optString("livePhotoVideoUrl") }
    val video = secureImage(explicit.ifBlank { info.optJSONObject("video")?.optString("url") ?: (info.opt("video") as? String).orEmpty() })
    val live = !gif && (info.optString("type") == "livephoto" || info.optBoolean("is_livephoto") || info.has("live_photo") || explicit.isNotBlank() || video.contains("/livephoto/"))
    val fallback = if (live && video.isBlank() && info.optString("fid").matches(Regex("[a-zA-Z0-9:_-]+"))) "https://video.weibo.com/media/livephoto/${info.optString("fid")}.mp4" else video
    val size = info.optJSONObject("largest") ?: info.optJSONObject("original") ?: info.optJSONObject("large")?.optJSONObject("geo") ?: info.optJSONObject("large") ?: info.optJSONObject("geo") ?: info.optJSONObject("pic_big") ?: info
    val thumbnailSize = info.optJSONObject("large")?.optJSONObject("geo") ?: info.optJSONObject("geo") ?: info
    val thumbnailAspect = if (thumbnailSize.optInt("width") > 0 && thumbnailSize.optInt("height") > 0)
        (thumbnailSize.optInt("width").toFloat() / thumbnailSize.optInt("height")).coerceIn(.5f, 2f) else 1f
    val preview = listOf("large", "orj960", "mw2000", "bmiddle", "thumbnail").firstNotNullOfOrNull { key ->
        secureImage(info.optJSONObject(key)?.optString("url") ?: (info.opt(key) as? String).orEmpty()).takeIf(String::isNotBlank)
    }.orEmpty().let { if (gif) it else highQualityPreviewUrl(it) }
    return Media(url, video = if (gif) "" else fallback, live = live, width = size.optInt("width"), height = size.optInt("height"),
        long = info.optBoolean("is_long") || info.optInt("cut_type") == 1 || (size.optInt("width") > 0 && size.optInt("height").toFloat() / size.optInt("width") > 2f), gif = gif, preview = preview, thumbnailAspect = thumbnailAspect)
}
fun mediaDuration(value: Any?): String = when (value) {
    is Number -> value.toLong().takeIf { it > 0 }?.let { "${(it / 60).toString().padStart(2, '0')}:${(it % 60).toString().padStart(2, '0')}" }.orEmpty()
    is String -> value
    else -> ""
}
fun videoMedia(page: JSONObject): Media? {
    val info = page.optJSONObject("media_info") ?: JSONObject()
    val qualities = linkedMapOf<String, String>()
    info.optJSONArray("playback_list").objects().forEach { entry ->
        entry.optJSONObject("play_info")?.let { play -> secureImage(play.optString("url")).takeIf(String::isNotBlank)?.let { qualities[play.optString("quality_desc").ifBlank { play.optString("label").ifBlank { "原画 ${qualities.size + 1}" } }] = it } }
    }
    listOf("mp4_720p_mp4" to "720P", "stream_url_hd" to "高清", "stream_url" to "默认画质").forEach { (key, name) -> secureImage(info.optString(key)).takeIf(String::isNotBlank)?.let { qualities.putIfAbsent(name, it) } }
    val link = listOf(page.optString("page_url"), page.optString("url"), info.optString("stream_url")).firstOrNull { liveRoomId(it) != null || videoObjectId(it) != null }
    val url = qualities.values.firstOrNull() ?: link ?: return null
    val cover = secureImage(page.optJSONObject("page_pic")?.optString("url") ?: (page.opt("page_pic") as? String) ?: page.optJSONObject("pic_info")?.optJSONObject("pic_big")?.optString("url") ?: info.optString("cover_image"))
    val id = link?.let(::videoObjectId) ?: listOf(info, page).firstNotNullOfOrNull { source ->
        listOf("object_id", "video_id", "fid", "page_id").firstNotNullOfOrNull { normalizeVideoId(source.optString(it)) }
    }
    return Media(cover, video = url, width = info.optInt("width"), height = info.optInt("height"), title = page.optString("page_title"), qualities = qualities, duration = mediaDuration(info.opt("duration")), videoId = id.orEmpty())
}

internal fun Media.sameVideo(other: Media): Boolean {
    if (live || other.live || video.isBlank() || other.video.isBlank()) return false
    val id = videoId.ifBlank { videoObjectId(video).orEmpty() }
    val otherId = other.videoId.ifBlank { videoObjectId(other.video).orEmpty() }
    if (id.isNotBlank() && otherId.isNotBlank()) return id == otherId
    if (video == other.video) return true
    // CDN signatures and edge hosts can vary for the same stream path.
    fun streamPath(url: String): String? = Uri.parse(url).let { uri ->
        uri.encodedPath?.takeIf { it.length > 1 && uri.host.orEmpty().endsWith(".weibocdn.com") }
    }
    val paths = (qualities.values + video).mapNotNull(::streamPath).toSet()
    return paths.isNotEmpty() && (other.qualities.values + other.video).any { streamPath(it) in paths }
}

internal fun MutableList<Media>.mergeVideo(candidate: Media, preferCandidate: Boolean = false) {
    val index = indexOfFirst { it.sameVideo(candidate) }
    if (index < 0) {
        add(candidate)
        return
    }
    val previous = this[index]
    val primary = if (playableVideo(candidate.video).isNotBlank() &&
        (preferCandidate || playableVideo(previous.video).isBlank())) candidate else previous
    val secondary = if (primary === previous) candidate else previous
    val geometry = if (primary.width > 0 && primary.height > 0) primary else secondary
    this[index] = primary.copy(url = primary.url.ifBlank { secondary.url }, width = geometry.width, height = geometry.height,
        title = primary.title.ifBlank { secondary.title }, duration = primary.duration.ifBlank { secondary.duration },
        qualities = secondary.qualities + primary.qualities, videoId = primary.videoId.ifBlank { secondary.videoId })
}

internal fun isHdrProbeUrl(url: String): Boolean = runCatching {
    val uri = java.net.URI(url)
    uri.scheme == "https" && uri.userInfo == null && uri.host?.endsWith(".sinaimg.cn") == true && Regex("^/large/[^/]+$").matches(uri.path.orEmpty())
}.getOrDefault(false)

internal fun mayContainHdrGainMap(bytes: ByteArray): Boolean {
    if (bytes.size < 4 || bytes[0] != 0xff.toByte() || bytes[1] != 0xd8.toByte()) return false
    val header = String(bytes, 0, minOf(bytes.size, 262144), Charsets.ISO_8859_1)
    return "http://ns.adobe.com/hdr-gain-map/1.0/" in header || "urn:iso:std:iso:ts:21496:-1" in header
}

internal val Media.canHaveHdrBadge: Boolean
    get() = video.isBlank() && !live && !gif && !card && !url.substringBefore('?').endsWith(".gif", true)

object MediaFiles {
    private val client = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(45, TimeUnit.SECONDS).followRedirects(false).followSslRedirects(false).build()
    private val probeClient = client.newBuilder().callTimeout(4, TimeUnit.SECONDS).connectTimeout(4, TimeUnit.SECONDS).readTimeout(4, TimeUnit.SECONDS).build()
    private val probes = LruCache<String, Boolean>(256)
    private val hdrHints = androidx.compose.runtime.mutableStateOf<Map<String, Boolean>>(emptyMap())
    private val probeGates = Array(4) { Mutex() }
    private val gates = Array(8) { Mutex() }
    private val budget = minOf(64L * 1024 * 1024, Runtime.getRuntime().maxMemory() / 8).toInt()
    val bitmaps = object : LruCache<String, Bitmap>(budget) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.allocationByteCount + if (Build.VERSION.SDK_INT >= 34 && value.hasGainmap()) value.gainmap?.gainmapContents?.allocationByteCount ?: 0 else 0
    }
    val hdr = androidx.compose.runtime.mutableStateMapOf<String, Boolean>()

    internal fun hasHdrBadge(media: Media): Boolean =
        media.canHaveHdrBadge && (hdr[media.url] == true || hdrHints.value[media.url] == true)

    internal fun recordHdrProbe(url: String, found: Boolean) {
        synchronized(probes) {
            probes.put(url, found)
            hdrHints.value = probes.snapshot()
        }
    }

    suspend fun probeHdr(url: String): Boolean = withContext(Dispatchers.IO) {
        if (!isHdrProbeUrl(url)) return@withContext false
        probeGates[(url.hashCode() and Int.MAX_VALUE) % probeGates.size].withLock {
            probes.get(url)?.let { return@withLock it }
            try {
                val request = Request.Builder().url(url).header("Referer", "https://weibo.com/").header("User-Agent", ApiClient.USER_AGENT).header("Range", "bytes=0-262143").header("Accept-Encoding", "identity").build()
                val found = probeClient.newCall(request).execute().use { response ->
                    if (response.code != 200 && response.code != 206) return@withLock false
                    val source = response.body?.source() ?: return@withLock false
                    source.request(262144)
                    mayContainHdrGainMap(source.readByteArray(minOf(source.buffer.size, 262144)))
                }
                recordHdrProbe(url, found)
                found
            } catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (_: IOException) { false }
        }
    }
    fun privateMediaCookie(url: String, cookie: String): String {
        val uri = runCatching { url.toHttpUrl() }.getOrNull() ?: return ""
        return if (uri.isHttps && uri.host == "upload.api.weibo.com" && uri.encodedPath.startsWith("/2/mss/msget")) cookie else ""
    }
    fun cacheKey(url: String, cookie: String): String = if (privateMediaCookie(url, cookie).isBlank()) url
        else MessageDigest.getInstance("SHA-256").digest(cookie.toByteArray()).joinToString("") { "%02x".format(it) } + ":$url"
    suspend fun fetch(context: Context, url: String, cookie: String = "", video: Boolean = false): File = withContext(Dispatchers.IO) {
        require(secureImage(url).isNotBlank()) { "媒体地址无效" }
        val hash = MessageDigest.getInstance("SHA-256").digest(cacheKey(url, cookie).toByteArray()).joinToString("") { "%02x".format(it) }
        gates[(hash.hashCode() and Int.MAX_VALUE) % gates.size].withLock {
            val directory = File(context.cacheDir, if (video) "video" else "originals").apply { mkdirs() }
            val output = File(directory, hash)
            if (output.isFile && output.length() > 0) return@withLock output
            val temporary = File(directory, "$hash-${java.util.UUID.randomUUID()}.part")
            try {
                var address = url
                repeat(6) {
                    coroutineContext.ensureActive()
                    val builder = Request.Builder().url(address).header("Referer", "https://weibo.com/").header("User-Agent", ApiClient.USER_AGENT)
                    privateMediaCookie(address, cookie).takeIf(String::isNotBlank)?.let { builder.header("Cookie", it) }
                    val redirect = client.newCall(builder.build()).download(temporary, if (video) 15L * 1024 * 1024 * 1024 else 64L * 1024 * 1024)
                    if (redirect != null) {
                        val next = address.toHttpUrl().resolve(redirect) ?: throw IOException("无效的媒体跳转")
                        require(next.isHttps && next.username.isEmpty() && next.password.isEmpty()) { "媒体跳转不安全" }
                        address = next.toString(); return@repeat
                    }
                    check(temporary.length() > 0 && temporary.renameTo(output)) { "媒体缓存保存失败" }
                    return@withLock output
                }
                throw IOException("媒体重定向次数过多")
            } finally { temporary.delete() }
        }
    }
    suspend fun decode(context: Context, media: Media, cookie: String): Bitmap = withContext(Dispatchers.IO) {
        val key = cacheKey(media.url, cookie)
        bitmaps.get(key)?.let { return@withContext it }
        val file = fetch(context, media.url, cookie)
        val bitmap = if (Build.VERSION.SDK_INT >= 28) ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_HARDWARE
            val pixels = info.size.width.toDouble() * info.size.height
            val maxPixels = budget / 16.0
            if (pixels > maxPixels) { val scale = sqrt(maxPixels / pixels); decoder.setTargetSize(maxOf(1, (info.size.width * scale).toInt()), maxOf(1, (info.size.height * scale).toInt())) }
        } else {
            val options = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
            android.graphics.BitmapFactory.decodeFile(file.absolutePath, options)
            require(options.outWidth > 0 && options.outHeight > 0) { "图片无法解码" }
            options.inJustDecodeBounds = false; options.inSampleSize = 1
            while (options.outWidth.toLong() * options.outHeight / options.inSampleSize / options.inSampleSize > budget / 16) options.inSampleSize *= 2
            android.graphics.BitmapFactory.decodeFile(file.absolutePath, options) ?: throw IOException("图片无法解码")
        }
        bitmaps.put(key, bitmap)
        withContext(Dispatchers.Main) { hdr[media.url] = Build.VERSION.SDK_INT >= 34 && bitmap.hasGainmap() }
        bitmap
    }
    suspend fun save(context: Context, media: Media, model: ReviewModel): Uri = withContext(Dispatchers.IO) {
        val isVideo = media.video.isNotBlank() && !media.live
        val resolved = if (isVideo && (videoObjectId(media.video) != null || liveRoomId(media.video) != null)) model.repository.resolveVideo(model.sessionCookie, media.video) else media
        val url = if (isVideo) resolved.video else resolved.url
        val file = fetch(context, url, model.sessionCookie, isVideo)
        val header = ByteArray(16).also { file.inputStream().use { input -> input.read(it) } }
        val signature = String(header, Charsets.US_ASCII).trimStart()
        require(!signature.startsWith("#EXTM3U") && !signature.startsWith("<")) { "服务返回了播放列表或网页，未取得可保存的媒体文件" }
        val extension = if (isVideo) "mp4" else when {
            header.take(3) == listOf(0x47.toByte(), 0x49.toByte(), 0x46.toByte()) -> "gif"
            header[0] == 0x89.toByte() && header[1] == 0x50.toByte() -> "png"
            String(header, 8, 4, Charsets.US_ASCII) == "WEBP" -> "webp"
            String(header, 4, 4, Charsets.US_ASCII) == "ftyp" -> "heic"
            else -> "jpg"
        }
        val mime = if (isVideo) "video/mp4" else if (extension == "jpg") "image/jpeg" else "image/$extension"
        val name = "Review_${System.currentTimeMillis()}.$extension"
        val tree = model.option(if (isVideo) "videoTree" else "imageTree")
        val resolver = context.contentResolver
        if (tree.isNotBlank()) {
            val uri = Uri.parse(tree)
            val parent = DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
            val target = DocumentsContract.createDocument(resolver, parent, mime, name) ?: throw IOException("无法创建目标文件")
            try { resolver.openOutputStream(target)?.use { out -> file.inputStream().use { it.copyTo(out) } } ?: throw IOException("无法写入目录") }
            catch (e: Exception) { runCatching { DocumentsContract.deleteDocument(resolver, target) }; throw e }
            return@withContext target
        }
        val pathType = model.option(if (isVideo) "videoPath" else "imagePath", "review")
        val nickname = when (pathType) { "self" -> model.me?.name.orEmpty(); "author" -> model.mediaAuthor.ifBlank { model.selected?.author.orEmpty() }; else -> "" }
        val folder = nickname.replace(Regex("[^\\p{L}\\p{N}_-]"), "_").take(60)
        val base = if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
        val relative = "$base/Review/" + if (folder.isBlank()) "" else "$folder/"
        if (Build.VERSION.SDK_INT < 29) {
            require(context.checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == android.content.pm.PackageManager.PERMISSION_GRANTED) { "请授予存储权限后重试" }
            val root = Environment.getExternalStoragePublicDirectory(base).canonicalFile
            val directory = File(root, "Review/" + folder).canonicalFile
            require(directory.toPath().startsWith(root.toPath()))
            check(directory.isDirectory || directory.mkdirs()) { "无法创建保存目录" }
            val output = File(directory, name)
            try { file.inputStream().use { input -> output.outputStream().use(input::copyTo) } }
            catch (e: Exception) { output.delete(); throw e }
            android.media.MediaScannerConnection.scanFile(context, arrayOf(output.absolutePath), arrayOf(mime), null)
            return@withContext Uri.fromFile(output)
        }
        val collection = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val target = resolver.insert(collection, ContentValues().apply { put(MediaStore.MediaColumns.DISPLAY_NAME, name); put(MediaStore.MediaColumns.MIME_TYPE, mime); put(MediaStore.MediaColumns.RELATIVE_PATH, relative); put(MediaStore.MediaColumns.IS_PENDING, 1) }) ?: throw IOException("无法创建媒体文件")
        try {
            resolver.openOutputStream(target)?.use { out -> file.inputStream().use { it.copyTo(out) } } ?: throw IOException("无法写入媒体")
            resolver.update(target, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) { resolver.delete(target, null, null); throw e }
        target
    }
}
