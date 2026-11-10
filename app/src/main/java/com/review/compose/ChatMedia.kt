package com.review.compose

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.PlayCircle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage
import coil.compose.SubcomposeAsyncImageContent
import coil.request.CachePolicy
import coil.request.ImageRequest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONArray
import org.json.JSONObject

fun chatAttachmentUrl(fid: String, image: Boolean = false) = Uri.Builder().scheme("https").authority("upload.api.weibo.com").path("/2/mss/msget")
    .appendQueryParameter("source", "209678993").appendQueryParameter("fid", fid).apply { if (image) appendQueryParameter("imageType", "origin") }.build().toString()

fun chatAttachmentIds(message: JSONObject): List<String> {
    val raw = message.opt("att_ids") ?: message.opt("fids") ?: message.opt("fid")
    return (if (raw is JSONArray) (0 until raw.length()).map { raw.optString(it) } else (raw as? String).orEmpty().split(','))
        .map(String::trim).filter { it.isNotBlank() && it != "null" }.distinct().take(50)
}
fun chatImages(message: JSONObject): List<Media> {
    if (message.optString("media_type") == "1") chatAttachmentIds(message).takeIf(List<String>::isNotEmpty)?.let { return it.map { id -> Media(chatAttachmentUrl(id, true)) } }
    val urls = mutableListOf<String>()
    val pictures = message.opt("pic_infos") ?: message.opt("pic_gifs")
    (if (pictures is JSONObject) listOf(pictures) else (pictures as? JSONArray).objects()).forEach { urls += it.optString("original_pic") }
    listOf("original_pic", "bmiddle_pic", "pic_url").forEach { if (message.has(it)) urls += message.optString(it) }
    return urls.map(::secureImage).filter(String::isNotBlank).distinct().map(::Media)
}

internal data class ChatSticker(val shortUrl: String, val pictureId: String, val directUrl: String)

internal fun chatSticker(message: JSONObject): ChatSticker? {
    for (entry in message.optJSONArray("url_objects").objects()) {
        val outer = entry.optJSONObject("object") ?: continue
        val gif = outer.optJSONObject("object")?.takeIf { it.has("gif_name") }
            ?: outer.takeIf { it.has("gif_name") } ?: continue
        val pictureId = listOf(gif, outer).firstNotNullOfOrNull { item ->
            item.optJSONArray("pic_ids")?.optString(0)?.takeIf { it.matches(Regex("[A-Za-z0-9_-]{1,128}")) }
        }.orEmpty()
        val shortUrl = secureImage(entry.optJSONObject("info")?.optString("url_short").orEmpty())
            .ifBlank { secureImage(message.optString("url_short")) }
        val directUrl = secureImage(gif.optString("url").trim()).takeUnless { Uri.parse(it).host == "t.cn" }.orEmpty()
        return ChatSticker(shortUrl, pictureId, directUrl)
    }
    return null
}
fun chatMetadata(raw: String): JSONObject {
    val text = raw.trim()
    val json = Regex("^__review_video_meta\\s*\\(([\\s\\S]*)\\)\\s*;?$").matchEntire(text)?.groupValues?.get(1) ?: text
    return runCatching { JSONObject(json) }.getOrDefault(JSONObject())
}
fun chatVideo(message: JSONObject, fid: String, metadata: JSONObject): Media? {
    if (metadata.optString("is_delete") in setOf("true", "1")) return null
    if (message.optString("media_type") != "10" && metadata.optString("extension").lowercase() != "mp4") return null
    val poster = message.optString("ext_text_video_pic_fid")
    val size = metadata.optString("videosize").split('*')
    return Media(if (poster.isNotBlank()) chatAttachmentUrl(poster) else secureImage(metadata.optString("screenshot").ifBlank { metadata.optString("thumbnail_240").ifBlank { message.optString("screenshot") } }),
        video = chatAttachmentUrl(metadata.optString("fid").ifBlank { fid }), width = size.getOrNull(0)?.toIntOrNull() ?: 0, height = size.getOrNull(1)?.toIntOrNull() ?: 0, title = "聊天视频")
}
data class ChatLink(val url: String, val title: String, val description: String, val image: String)
fun chatLink(message: JSONObject): ChatLink? {
    message.optJSONArray("url_objects").objects().forEach { entry ->
        val info = entry.optJSONObject("info") ?: JSONObject()
        val status = entry.optJSONObject("status"); val user = entry.optJSONObject("user")
        val outer = entry.optJSONObject("object")
        val data = status ?: user ?: outer?.optJSONObject("object") ?: outer ?: return@forEach
        if (data.has("gif_name")) return@forEach
        val title = data.optJSONObject("user")?.optString("screen_name").orEmpty().ifBlank { data.optString("screen_name").ifBlank { data.optString("display_name").ifBlank { data.optString("title") } } }
        val id = data.optString("idstr").ifBlank { data.optString("id").ifBlank { data.optString("mid").ifBlank { data.optString("uid") } } }
        val url = if (id.matches(Regex("[0-9]+")) && (status != null || user != null)) "https://weibo.com/${if (status != null) "detail" else "u"}/$id"
            else listOf(info.optString("url_long"), data.optString("url"), info.optString("url_short"), message.optString("url_short")).firstOrNull { secureImage(it).isNotBlank() }.orEmpty()
        if (title.isBlank() || url.isBlank()) return@forEach
        val firstPicture = status?.optJSONArray("pics").objects().firstOrNull()
        val cover = listOf(data.optString("thumbnail_pic"), data.optString("bmiddle_pic"), data.optString("original_pic"),
            data.optString("profile_image_url"), data.optJSONObject("image")?.optString("url"),
            firstPicture?.optJSONObject("large")?.optString("url"), firstPicture?.optString("url"))
            .firstNotNullOfOrNull { secureImage(it.orEmpty()).takeIf(String::isNotBlank) }
            ?: status?.let(::linkedPictures)?.firstOrNull()?.url.orEmpty()
        return ChatLink(url, title, chatMessageText(data.optString("text").ifBlank { data.optString("summary").ifBlank { data.optString("description").ifBlank { data.optString("verified_reason") } } }), cover)
    }
    val url = listOf("linkurl", "url_long", "url_short").firstNotNullOfOrNull { secureImage(message.optString(it)).takeIf(String::isNotBlank) } ?: return null
    val title = message.optString("cardtitle").takeIf(String::isNotBlank) ?: return null
    return ChatLink(url, title, plainText(message.optString("desc")), secureImage(message.optString("thumbnail_pic")))
}
private val attachmentGate = Semaphore(2)
private val attachmentCache = android.util.LruCache<String, String>(48)
internal suspend fun Repository.chatStickerUrl(cookie: String, pictureId: String, refresh: Boolean): String = attachmentGate.withPermit {
    val account = java.security.MessageDigest.getInstance("SHA-256").digest(cookie.toByteArray()).joinToString("") { "%02x".format(it) }
    val key = "sticker:$account:$pictureId"
    if (!refresh) attachmentCache.get(key)?.let { return@withPermit it }
    val response = api.get(ApiClient.CHAT + "/webim/pic_infos.json", cookie, mapOf("pids" to pictureId))
    val address = secureImage((response.optJSONObject("data") ?: response).optString(pictureId).trim())
    check(address.isNotBlank() && Uri.parse(address).host != "t.cn") { "动图地址不可用" }
    attachmentCache.put(key, address)
    address
}

suspend fun Repository.chatVideoMetadata(cookie: String, fid: String): JSONObject = attachmentGate.withPermit {
    val account = java.security.MessageDigest.getInstance("SHA-256").digest(cookie.toByteArray()).joinToString("") { "%02x".format(it) }
    val key = "$account:$fid"
    attachmentCache.get(key)?.let { return@withPermit JSONObject(it) }
    suspend fun query(replace: Boolean) = chatMetadata(api.raw("https://upload.api.weibo.com/2/mss/meta_query.json", cookie,
        mapOf("source" to "209678993", "fid" to fid, "replace" to "$replace", "callback" to "__review_video_meta"), extraHeaders = mapOf("Referer" to "https://api.weibo.com/chat/")).text)
    val metadata = query(false)
    if (metadata.optString("extension").lowercase() == "mp4") try { val playable = query(true); playable.keys().forEach { metadata.put(it, playable.opt(it)) } } catch (e: CancellationException) { throw e } catch (_: Exception) { }
    if (metadata.length() > 0) attachmentCache.put(key, metadata.toString())
    metadata
}

@Composable
internal fun ChatMessageBody(message: Message, pictures: List<Media>, sticker: ChatSticker?, caption: String,
    gallery: (List<Media>, Int) -> Unit, primaryBubble: Boolean = false) {
    val model = LocalReview.current
    val raw = remember(message.raw) { JSONObject(message.raw) }
    val ids = remember(message.raw) { if (raw.optString("media_type") in setOf("10", "5")) chatAttachmentIds(raw) else emptyList() }
    val link = remember(message.raw) { chatLink(raw) }
    val width = (LocalConfiguration.current.screenWidthDp * .6f).coerceIn(1f, 240f).dp
    val lookup = sticker?.takeIf { pictures.isEmpty() && it.pictureId.isNotBlank() }
    val cookie = model.sessionCookie
    var lookupAttempt by remember(lookup, cookie) { mutableIntStateOf(0) }
    var stickerUrl by remember(lookup, cookie, lookupAttempt) { mutableStateOf<String?>(null) }
    LaunchedEffect(lookup, cookie, lookupAttempt) {
        if (lookup != null) stickerUrl = try { model.repository.chatStickerUrl(cookie, lookup.pictureId, lookupAttempt > 0) }
        catch (e: CancellationException) { throw e }
        catch (_: Exception) { lookup.directUrl }
    }
    val resolved = if (lookup != null) stickerUrl else sticker?.directUrl
    val images = pictures.ifEmpty { resolved?.takeIf(String::isNotBlank)?.let { listOf(Media(it, gif = true)) }.orEmpty() }
    Column {
        if (images.isEmpty() && lookup != null) ChatImageStatus(loading = resolved == null) { lookupAttempt++ }
        else if (images.isEmpty() && sticker != null) Text("动图暂不可用")
        images.forEachIndexed { index, media ->
            key(media.url, lookupAttempt) {
                ChatPicture(media, cookie, width, caption.isNotBlank(), lookupAttempt > 0,
                    refreshSource = lookup?.let { { lookupAttempt++ } }) {
                    model.mediaAuthor = message.name
                    gallery(images, index)
                }
            }
        }
        link?.let { card -> Row(Modifier.width(260.dp).reviewClickable { model.openLink(card.url) }, verticalAlignment = Alignment.CenterVertically) {
            if (card.image.isNotBlank()) {
                MediaImage(Media(card.image), "链接封面", Modifier.size(52.dp).clip(RoundedCornerShape(5.dp)))
                Spacer(Modifier.width(10.dp))
            }
            Column(Modifier.weight(1f)) {
                Text(card.title, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = reviewWeight(FontWeight.SemiBold), color = MaterialTheme.colorScheme.onSurface)
                if (card.description.isNotBlank()) Text(card.description, maxLines = 2, overflow = TextOverflow.Ellipsis, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } }
        ids.forEach { fid ->
            var metadata by remember(fid, model.uid) { mutableStateOf<JSONObject?>(null) }
            var retry by remember { mutableIntStateOf(0) }
            var failed by remember { mutableStateOf(false) }
            LaunchedEffect(fid, model.uid, retry) { try { failed = false; metadata = model.repository.chatVideoMetadata(model.sessionCookie, fid) } catch (e: CancellationException) { throw e } catch (_: Exception) { failed = true } }
            val media = metadata?.let { chatVideo(raw, fid, it) }
            if (media != null) Box(Modifier.width(width).height(if (media.width > 0 && media.height > 0) (width.value * media.height / media.width).coerceIn(100f, 300f).dp else 160.dp).clip(RoundedCornerShape(8.dp)).background(Color.Black.copy(alpha = .87f)).reviewClickable { model.mediaAuthor = message.name; gallery(listOf(media), 0) }) {
                if (media.url.isNotBlank()) MediaImage(media, "播放聊天视频", Modifier.fillMaxSize(), fit = true)
                Icon(Icons.Rounded.PlayCircle, "播放聊天视频", Modifier.align(Alignment.Center).size(48.dp), tint = Color.White)
            } else if (failed || metadata == null || raw.optString("media_type") == "10") Text(if (failed) "附件加载失败，点击重试" else if (metadata == null) "正在加载附件…" else "视频已失效或未通过审核", Modifier.reviewClickable(enabled = failed) { retry++ })
        }
        if (caption.isNotBlank() && !(link != null && Regex("^https?://\\S+$").matches(caption))) RichText(caption, style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.5.sp, lineHeight = 19.575.sp, color = LocalContentColor.current), linkColor = if (primaryBubble) MaterialTheme.colorScheme.onPrimary else Color.Unspecified)
    }
}

@Composable
private fun ChatPicture(media: Media, cookie: String, width: Dp, hasCaption: Boolean, refresh: Boolean,
    refreshSource: (() -> Unit)?, open: () -> Unit) {
    val context = LocalContext.current
    var retry by remember(media.url, cookie) { mutableIntStateOf(0) }
    val request = remember(media.url, cookie, retry, refresh) {
        val cache = MediaFiles.cacheKey(media.url, cookie)
        ImageRequest.Builder(context).data(media.url).size(1024).diskCacheKey(cache).memoryCacheKey(cache).apply {
            MediaFiles.privateMediaCookie(media.url, cookie).takeIf(String::isNotBlank)?.let { addHeader("Cookie", it) }
            if (retry > 0 || refresh) { diskCachePolicy(CachePolicy.WRITE_ONLY); memoryCachePolicy(CachePolicy.WRITE_ONLY) }
        }.build()
    }
    key(retry) {
        SubcomposeAsyncImage(request, contentDescription = "查看聊天图片", contentScale = ContentScale.Fit,
            modifier = Modifier.padding(bottom = if (hasCaption) 8.dp else 0.dp).widthIn(max = width).heightIn(max = 300.dp).clip(RoundedCornerShape(8.dp)),
            loading = { ChatImageStatus(loading = true) {} },
            error = { ChatImageStatus(loading = false) { if (refreshSource != null) refreshSource() else retry++ } },
            success = { SubcomposeAsyncImageContent(Modifier.reviewClickable(onClick = open)) })
    }
}

@Composable
private fun ChatImageStatus(loading: Boolean, retry: () -> Unit) {
    Box(Modifier.size(180.dp, 100.dp).then(if (loading) Modifier else Modifier.reviewClickable(onClick = retry)), contentAlignment = Alignment.Center) {
        if (loading) CircularProgressIndicator(Modifier.size(20.dp)) else Text("图片加载失败，点击重试")
    }
}

fun chatCaption(text: String, hasImages: Boolean, hasVideo: Boolean, stickerUrl: String = ""): String {
    val caption = if (stickerUrl.isNotBlank()) attachmentLinkPattern(stickerUrl).replace(text, "").trim() else text
    val placeholders = if (hasVideo) setOf("分享视频", "发送视频", "[视频]", "[视频消息]") else if (hasImages) setOf("[图片]", "[图片消息]", "发送图片", "分享图片", "[动画表情]", "分享动画", "分享动画表情", "发送表情", "[表情]") else emptySet()
    return if (caption.trim() in placeholders || stickerUrl.isNotBlank() && caption == "[链接]查看动图") "" else caption
}
