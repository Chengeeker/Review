package com.review.compose

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import okhttp3.FormBody
import org.json.JSONArray
import org.json.JSONObject

private val videoIdPattern = Regex("[0-9]+:[a-zA-Z0-9_-]+")
internal fun normalizeVideoId(id: String): String? =
    id.takeIf(videoIdPattern::matches) ?: id.removePrefix("1022:").takeIf(videoIdPattern::matches)

fun videoObjectId(url: String): String? {
    val uri = Uri.parse(url)
    if (uri.host !in setOf("h5.video.weibo.com", "video.weibo.com", "h5.video.weibo.cn", "video.weibo.cn", "weibo.com", "www.weibo.com", "m.weibo.cn")) return null
    val query = listOf("fid", "object_id", "objectId", "oid").firstNotNullOfOrNull { uri.getQueryParameter(it)?.takeIf(String::isNotBlank) }
    val id = query ?: Regex("/(?:show|tv/show|s/video/show)/([^/?#]+)", RegexOption.IGNORE_CASE).find(uri.path.orEmpty())?.groupValues?.get(1) ?: return null
    return normalizeVideoId(id)
}
fun liveRoomId(url: String): String? {
    val uri = Uri.parse(url)
    if (uri.host !in setOf("weibo.com", "www.weibo.com", "weibo.cn", "www.weibo.cn", "m.weibo.cn")) return null
    return Regex("/l/(?:wblive/)?p/show/([a-zA-Z0-9:_-]+)").find(uri.path.orEmpty())?.groupValues?.get(1)
        ?: uri.getQueryParameter("live_id")?.takeIf { it.matches(Regex("[a-zA-Z0-9:_-]+")) }
}
fun playableVideo(url: String): String = secureImage(url).takeIf { videoObjectId(it) == null && liveRoomId(it) == null }.orEmpty()

internal fun normalizeVideoQualities(qualities: Map<String, String>, preferredUrl: String): Map<String, String> {
    val tiers = sortedMapOf<Int, String>(reverseOrder())
    val entries = qualities.mapNotNull { (label, value) -> playableVideo(value.trim()).takeIf(String::isNotBlank)?.let { label to it } }
    for ((label, url) in entries) {
        val height = Regex("(?:^|[^0-9])(2160|1440|1080|720|480|360)(?:p|[^0-9]|$)", RegexOption.IGNORE_CASE)
            .find(label)?.groupValues?.get(1)?.toInt() ?: continue
        if (height !in tiers || url == preferredUrl) tiers[height] = url
    }
    val seen = mutableSetOf<String>()
    val result = tiers.entries.filter { seen.add(it.value) }.associate { "${it.key}P" to it.value }
    if (result.isNotEmpty()) return result
    val fallback = entries.firstOrNull { it.second == preferredUrl } ?: entries.firstOrNull() ?: return emptyMap()
    return mapOf((if (fallback.first == "直播") "直播" else "分辨率未知") to fallback.second)
}
fun parseVideoComponent(root: JSONObject): Media? {
    val info = (root.optJSONObject("data") ?: root).optJSONObject("Component_Play_Playinfo") ?: return null
    val qualities = linkedMapOf<String, String>()
    fun add(label: String, value: Any?) {
        val candidate = if (value is JSONObject) value.optString("url").ifBlank { value.optString("play_url") }.ifBlank { value.optString("src") } else (value as? String).orEmpty()
        val url = playableVideo(candidate)
        if (url.isNotBlank() && url !in qualities.values) qualities[if (label in qualities) "$label ${qualities.size + 1}" else label] = url
    }
    when (val urls = info.opt("urls")) {
        is JSONObject -> urls.keys().forEach { add(it, urls.opt(it)) }
        is JSONArray -> urls.objects().forEach { add(it.optString("label", "默认画质"), it.opt("url") ?: it.opt("play_url") ?: it.opt("play_info")) }
    }
    listOf("stream_url", "stream_url_hd", "mp4_hd_url", "mp4_sd_url", "h265_mp4_hd", "h265_mp4_ld", "play_url", "media_url", "url").forEach { add(if (it.contains("hd")) "高清" else if (it.contains("sd") || it.contains("ld")) "标清" else "默认画质", info.opt(it)) }
    if (qualities.isEmpty()) return null
    return Media(secureImage(info.optString("cover_image").ifBlank { info.optString("cover_url") }.ifBlank { info.optString("cover") }), video = qualities.values.first(), title = info.optString("title"), qualities = qualities)
}
suspend fun Repository.resolveVideo(cookie: String, target: String): Media {
    liveRoomId(target)?.let { id ->
        val data = api.get(ApiClient.DESKTOP + "/l/!/2/wblive/room/show_pc_live.json", cookie, mapOf("live_id" to id)).optJSONObject("data") ?: error("直播资料暂不可用")
        check(data.optInt("status") == 1) { if (data.optInt("status") == 3) "该直播已转为回放，当前没有直播流" else "直播已结束或尚未开始" }
        val stream = listOf("live_origin_hls_url", "live_origin_flv_url", "hls_url", "m3u8_url", "stream_url", "play_url").firstNotNullOfOrNull { playableVideo(data.optString(it)).takeIf(String::isNotBlank) } ?: error("直播流暂不可用")
        return Media(secureImage(data.optString("cover").ifBlank { data.optString("cover_url") }), video = stream, title = data.optString("title"), qualities = mapOf("直播" to stream))
    }
    val id = videoObjectId(target)
    if (id == null) return Media(video = playableVideo(target).also { require(it.isNotBlank()) { "视频地址无效" } })
    val payload = JSONObject().put("Component_Play_Playinfo", JSONObject().put("oid", id)).toString()
    for (session in listOf("", cookie).distinct()) {
        try {
            val body = api.raw("https://h5.video.weibo.com/api/component", session, mapOf("page" to "/show/$id"), FormBody.Builder().add("data", payload).build(), extraHeaders = mapOf("Referer" to "https://h5.video.weibo.com/show/$id", "Origin" to "https://h5.video.weibo.com", "PAGE-REFERER" to "/show/$id")).json()
            parseVideoComponent(ApiClient.requireSuccess(body))?.let { return it }
        } catch (e: CancellationException) { throw e } catch (_: Exception) { }
    }
    error("视频地址暂不可用，请检查登录状态后重试")
}

internal suspend fun Repository.refreshVideo(cookie: String, media: Media, post: Post?): Media {
    normalizeVideoId(media.videoId)?.let { return resolveVideo(cookie, "https://weibo.com/tv/show/$it") }
    require(post != null && post.id.isNotBlank() && post.id.all(Char::isDigit)) { "视频缺少来源标识" }
    val root = get("/ajax/statuses/show", cookie, mapOf("id" to post.id))
    return parsePost(root.optJSONObject("data") ?: root).images.singleOrNull { it.video.isNotBlank() && !it.live }
        ?: error("原内容暂未返回可播放视频")
}

@Composable
fun VideoLinkScreen(target: String) {
    val model = LocalReview.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val supplied = LocalReviewRoute.current?.media
    var media by remember(target) { mutableStateOf(supplied) }
    var error by remember(target) { mutableStateOf<String?>(null) }
    var attempt by remember(target) { mutableIntStateOf(0) }
    val (saving, saveMedia) = rememberMediaSaver { model.notice = it }
    LaunchedEffect(target, attempt) { try { if (supplied == null || playableVideo(supplied.video).isBlank() || attempt > 0) media = model.repository.resolveVideo(model.sessionCookie, target); error = null } catch (e: CancellationException) { throw e } catch (e: Exception) { error = e.message } }
    Box(Modifier.fillMaxSize().background(Color.Black).testTag("standalone-video"), contentAlignment = Alignment.Center) {
        media?.let { item -> VideoSurface(item, LocalPageActive.current, model::back, { saveMedia(listOf(it)) }, saving = saving, post = LocalReviewRoute.current?.post) }
            ?: if (error == null) CircularProgressIndicator() else ErrorNotice(error.orEmpty()) { error = null; attempt++ }
    }
}
