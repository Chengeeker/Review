package com.review.compose

import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.platform.ViewConfiguration
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.DpSize
import coil.compose.AsyncImage
import org.json.JSONObject
import org.jsoup.Jsoup
import java.time.*
import java.time.format.DateTimeFormatter
import java.util.Locale

private var emojiData: JSONObject? = null
private var softbankData: JSONObject? = null
private val hiddenLinkChars = Regex("[\\u200B\\u200C\\u200D\\uFEFF]")
private fun richLinkKey(url: String): String = secureImage(url.replace(hiddenLinkChars, "").replace("&amp;", "&").trim())
private val topicPagePattern = Regex("100808[0-9a-f]{32}", RegexOption.IGNORE_CASE)
private val topicWebHosts = setOf("weibo.com", "www.weibo.com", "weibo.cn", "m.weibo.cn")

internal fun topicPageId(value: String): String? = value.trim().removePrefix("1022:")
    .takeIf(topicPagePattern::matches)

internal fun topicName(value: String): String {
    val title = value.trim().trim('#').trim()
    return (if (title.endsWith("[超话]")) title.removeSuffix("[超话]") else title.removeSuffix("超话")).trim()
}

private fun topicUrlId(value: String): String? {
    val uri = Uri.parse(value.trim().replace("&amp;", "&"))
    if (!uri.isHierarchical || uri.userInfo != null) return null
    val web = uri.scheme in setOf(null, "https", "http") && uri.host in topicWebHosts
    val native = uri.scheme == "sinaweibo" && uri.host in setOf("pageinfo", "cardlist")
    if (!web && !native) return null
    return sequenceOf(uri.path.orEmpty().takeIf { it.startsWith("/p/") }?.split('/')?.getOrNull(2),
        uri.getQueryParameter("page_id"), uri.getQueryParameter("pageid"), uri.getQueryParameter("containerid"))
        .filterNotNull().firstNotNullOfOrNull { topicPageId(it.substringBefore("_-_")) }
}

private fun linkTopicId(item: JSONObject): String? = sequenceOf("page_id", "oid", "topic_id")
    .firstNotNullOfOrNull { topicPageId(item.optString(it)) }
    ?: sequenceOf("long_url", "ori_url", "h5_target_url", "scheme", "url")
        .firstNotNullOfOrNull { topicUrlId(item.optString(it)) }
fun encodedEmoji(token: String, mapping: JSONObject): String? {
    val hex = Regex("^\\[/?([a-fA-F0-9]{6,32})\\.(?:png|gif)]$", RegexOption.IGNORE_CASE).matchEntire(token)?.groupValues?.get(1) ?: return null
    if (hex.length % 2 != 0) return null
    return runCatching {
        val bytes = hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val decoder = Charsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
        val raw = decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString()
        val converted = raw.codePoints().toArray().joinToString("") { mapping.optString(it.toString()).ifBlank { String(Character.toChars(it)) } }
        converted.takeIf { it != raw || it.codePoints().anyMatch { code -> code >= 0x1f000 } }
    }.getOrNull()
}

fun articleId(url: String): String? {
    val uri = runCatching { java.net.URI(url) }.getOrNull() ?: return null
    if (uri.host !in setOf("weibo.com", "www.weibo.com", "weibo.cn", "m.weibo.cn")) return null
    if (uri.path == "/ttarticle/p/show") return Regex("(?:^|&)id=(\\d+)").find(uri.rawQuery.orEmpty())?.groupValues?.get(1)
    return Regex("/article/m/show/id/(\\d+)").find(uri.path.orEmpty())?.groupValues?.get(1)
}

fun ReviewModel.openLink(raw: String, title: String = "") {
    val url = richLinkKey(raw)
    if (url.isBlank()) { notice = "链接地址不可用"; return }
    if (isCommentPhotoPage(url)) { openCommentPhoto(url); return }
    if (runCatching { openNativeLink(url, title) }.getOrDefault(false)) return
    if (isWeiboShortLink(url)) openShortLink(url, title)
    else navigate("browser:${Uri.encode(url)}")
}

internal fun isCommentPhotoPage(url: String): Boolean = runCatching { java.net.URI(url) }.getOrNull()?.let {
    it.scheme == "https" && it.host == "photo.weibo.com" && it.userInfo == null && it.port in setOf(-1, 443) &&
        it.path.orEmpty().matches(Regex("/h5/comment/compic_id/1022:230597[0-9a-fA-F]{32}/?"))
} == true

internal fun commentPhotoImage(html: String): String? = Jsoup.parse(html).select(".img-box img[src]")
    .asSequence().map { secureImage(it.attr("src")) }.firstOrNull { value ->
        runCatching { java.net.URI(value) }.getOrNull()?.let { uri ->
            uri.host?.endsWith(".sinaimg.cn") == true && uri.path.orEmpty().matches(Regex("/[^?#]+\\.(jpg|jpeg|png|gif|webp)", RegexOption.IGNORE_CASE))
        } == true
    }

internal fun isWeiboShortLink(url: String): Boolean = runCatching { java.net.URI(url) }.getOrNull()?.let {
    it.scheme == "https" && it.userInfo == null && it.port in setOf(-1, 443) && it.host in setOf("t.cn", "www.t.cn") &&
        it.path.orEmpty().matches(Regex("/[A-Za-z0-9]+"))
} == true

internal suspend fun ApiClient.shortLinkTarget(url: String): String? {
    if (!isWeiboShortLink(url)) return null
    return try { raw(url, timeoutSeconds = 6, maxBytes = 64 * 1024); null }
    catch (e: ApiHttpFailure) {
        e.redirect?.let { runCatching { secureImage(java.net.URI(url).resolve(it).toString()) }.getOrNull() }
            ?.takeIf(String::isNotBlank)
    } catch (_: java.io.IOException) { null }
}

internal fun officialWebRoute(url: String): String? {
    val uri = Uri.parse(url)
    if (!uri.isHierarchical || uri.scheme !in setOf("https", "http") || uri.userInfo != null || uri.port !in setOf(-1, 443)) return null
    val path = uri.path.orEmpty().trimEnd('/')
    if (uri.host == "api.weibo.com" && path == "/chat") return "messages"
    if (uri.host in setOf("weibo.com", "www.weibo.com") && path == "/hot/search") return "trends"
    if (uri.host in setOf("weibo.com", "www.weibo.com")) {
        when (path) {
            "/fav", "/u/page/fav" -> return "favorites"
            "/super" -> return "topics"
        }
    }
    if (uri.host !in topicWebHosts && uri.host != "s.weibo.com") return null
    if (uri.host == "s.weibo.com" && path == "/weibo" || uri.host == "m.weibo.cn" && path == "/search") {
        return uri.getQueryParameter("q")?.trim()?.takeIf(String::isNotBlank)?.let { "searchResults:${Uri.encode(it)}" }
    }
    if (uri.host !in topicWebHosts) return null
    val container = path.removePrefix("/p/").substringBefore('/').takeIf { path.startsWith("/p/") && it != "index" }
        ?: uri.getQueryParameter("containerid").takeIf { path == "/p/index" }
    container?.takeIf { Regex("100101[A-Za-z0-9]{8,48}").matches(it) }?.let { return "place:${it.removePrefix("100101")}" }
    Regex("^/(?:u|profile)/([1-9][0-9]{0,19})/(follow|fans)$").matchEntire(path)?.let {
        return "relations:${it.groupValues[1]}:${it.groupValues[2] == "follow"}"
    }
    Regex("^/(?:u|profile)/([1-9][0-9]{0,19})$").matchEntire(path)?.let { return "profile:${it.groupValues[1]}" }
    Regex("^/n/([^/?#]+)$").matchEntire(path)?.let { return "profile:${it.groupValues[1]}" }
    return null
}

fun ReviewModel.openNativeLink(url: String, title: String = ""): Boolean {
    articleId(url)?.let { navigate("article:$it"); return true }
    if (videoObjectId(url) != null || liveRoomId(url) != null || (Uri.parse(url).host.orEmpty().endsWith(".weibocdn.com") && Regex("\\.(mp4|m3u8|webm|mov|flv)([?#]|$)", RegexOption.IGNORE_CASE).containsMatchIn(url))) { navigate("video:${Uri.encode(url)}"); return true }
    topicUrlId(url)?.let { navigate("topic:$it"); return true }
    officialWebRoute(url)?.let {
        navigate(if (it.startsWith("place:")) "$it:${Uri.encode(title)}" else it)
        return true
    }
    val uri = Uri.parse(url)
    val official = uri.host in setOf("weibo.com", "www.weibo.com", "m.weibo.cn", "weibo.cn")
    if (official) {
        Regex("^/(?:status/|detail/|[0-9]+/)([a-zA-Z0-9]{1,32})/?$").matchEntire(uri.path.orEmpty())?.let {
            openPost(Post(numericStatusId(it.groupValues[1]), "", text = "")); return true
        }
    }
    return false
}

@Composable
fun RichText(value: String, post: Post? = null, modifier: Modifier = Modifier, style: TextStyle = LocalTextStyle.current, linkColor: Color = Color.Unspecified) {
    val model = LocalReview.current
    val context = LocalContext.current
    val emojis = remember { emojiData ?: context.assets.open("rich_emoji.json").bufferedReader().use { JSONObject(it.readText().removePrefix("\uFEFF")) }.also { emojiData = it } }
    val softbank = remember { softbankData ?: context.assets.open("softbank_emoji.json").bufferedReader().use { JSONObject(it.readText()) }.also { softbankData = it } }
    val color = if (linkColor != Color.Unspecified) linkColor else if (model.bool("linkTheme", true)) MaterialTheme.colorScheme.primary else Color(0xFF3366CC)
    val raw = post?.data ?: JSONObject()
    val markup = remember(post?.raw) { Jsoup.parse(raw.optString("text")) }
    val links = remember(post?.raw) { raw.optJSONArray("url_struct").objects().map { richLinkKey(it.optString("short_url")) to it } }
    val topics = remember(post?.raw) { raw.optJSONArray("topic_struct").objects() }
    val videoLinks = remember(markup) {
        buildMap {
            for (anchor in markup.select("a[href]")) {
                val target = richLinkKey(anchor.attr("href"))
                if (videoObjectId(target) == null) continue
                val title = anchor.text().takeIf { it.isNotBlank() && richLinkKey(it).isBlank() } ?: continue
                val video = title to target
                put(target, video)
                // Quoted statuses can carry the short URL only on the video icon.
                for (icon in anchor.select("img[title]")) {
                    val short = richLinkKey(icon.attr("title"))
                    if (Uri.parse(short).host == "t.cn") putIfAbsent(short, video)
                }
            }
        }
    }
    val inline = remember(value, markup, style.fontSize) {
        val result = mutableMapOf<String, InlineTextContent>()
        val urls = emojis.getJSONObject("emojiUrlMap")
        val supplied = markup.select("img[alt]").associate { it.attr("alt") to it.attr("src").ifBlank { it.attr("data-src") } }
        Regex("\\[[^\\[\\]\\r\\n]{1,80}]").findAll(value).forEach { match ->
            val url = secureImage(supplied[match.value] ?: urls.optString(match.value))
            if (url.isNotBlank()) {
                val size = (if (style.fontSize.isSp) style.fontSize.value else 16f) * 1.2f
                result[match.value] = InlineTextContent(Placeholder(size.sp, size.sp, PlaceholderVerticalAlign.Center)) { AsyncImage(url, match.value, Modifier.fillMaxSize()) }
            }
        }
        result
    }
    val linkWeight = reviewWeight(FontWeight.SemiBold)
    val pulse = reviewPulse()
    val annotated = buildAnnotatedString {
        val regex = Regex("(@[\\w\\u4e00-\\u9fa5-]+)|(#([^#]+)#)|(https?://[^\\s]+)|(\\[[^\\[\\]\\r\\n]{1,80}])")
        var position = 0
        for (match in regex.findAll(value)) {
            append(value.substring(position, match.range.first))
            val token = match.value
            if (token in inline) appendInlineContent(token, token)
            else if (token.startsWith('[')) append(emojis.getJSONObject("emojiMap").optString(token).ifBlank { encodedEmoji(token, softbank) ?: token })
            else {
                val key = if (token.startsWith("http")) richLinkKey(token) else ""
                val link = key.takeIf(String::isNotBlank)?.let { url -> links.firstOrNull { it.first == url }?.second }
                val video = videoLinks[key]
                val title = link?.optString("url_title").orEmpty()
                val display = when {
                    video != null && (title.isBlank() || richLinkKey(title).isNotBlank()) -> video.first
                    title.isNotBlank() -> title
                    else -> token
                }
                val hot = link?.optString("url_type") == "2" || (token.startsWith('#') && topics.any { it.optString("topic_title") == token.trim('#') && it.optBoolean("is_hot") })
                withLink(LinkAnnotation.Clickable(token, TextLinkStyles(SpanStyle(color = if (hot && linkColor == Color.Unspecified) Color(0xFFFF8200) else color, fontWeight = linkWeight, textDecoration = if (linkColor != Color.Unspecified) androidx.compose.ui.text.style.TextDecoration.Underline else null))) {
                    pulse()
                    when {
                        token.startsWith('@') -> model.navigate("profile:${token.drop(1)}")
                        token.startsWith('#') -> {
                            val label = token.trim('#').trim()
                            val name = topicName(label)
                            val id = topics.firstNotNullOfOrNull { if (topicName(it.optString("topic_title")) == name) linkTopicId(it) else null }
                                ?: links.firstNotNullOfOrNull { (_, item) -> if (topicName(item.optString("url_title")) == name) linkTopicId(item) else null }
                                ?: markup.select("a[href]").firstNotNullOfOrNull { if (topicName(it.text()) == name) topicUrlId(it.attr("href")) else null }
                            if (name.isNotBlank() && (id != null || name != label)) {
                                model.openTopic(JSONObject().put("page_id", id.orEmpty()).put("title", name))
                            } else model.openSearchResults(token)
                        }
                        else -> {
                            val id = link?.let(::linkTopicId)
                            if (id != null) model.openTopic(JSONObject().put("page_id", id).put("title", topicName(title)))
                            else {
                                val target = sequenceOf("long_url", "ori_url", "h5_target_url")
                                    .firstNotNullOfOrNull { field -> richLinkKey(link?.optString(field).orEmpty()).takeIf(String::isNotBlank) }
                                model.openLink(video?.second ?: target ?: token, title)
                            }
                        }
                    }
                }) { append(display) }
            }
            position = match.range.last + 1
        }
        append(value.substring(position))
    }
    InlineLinkTargets { Text(annotated, modifier, style = style, inlineContent = inline) }
}

@Composable
internal fun InlineLinkTargets(content: @Composable () -> Unit) {
    val configuration = LocalViewConfiguration.current
    val exactTargets = remember(configuration) {
        object : ViewConfiguration by configuration {
            // Expanded touch targets can hit the empty rectangle between wrapped link fragments.
            override val minimumTouchTargetSize = DpSize.Zero
        }
    }
    CompositionLocalProvider(LocalViewConfiguration provides exactTargets, content = content)
}

fun postTime(raw: String, relative: Boolean, weekday: Boolean, year: Boolean, timezone: Boolean, seconds: Boolean,
    now: LocalDateTime = LocalDateTime.now()): String {
    val date = runCatching { LocalDateTime.parse(raw, DateTimeFormatter.ofPattern("EEE MMM dd HH:mm:ss Z yyyy", Locale.ENGLISH)) }.getOrNull()
        ?: runCatching { OffsetDateTime.parse(raw).toLocalDateTime() }.getOrNull()
        ?: runCatching { LocalDateTime.parse(raw) }.getOrNull() ?: return raw
    val diff = Duration.between(date, now)
    val zone = if (timezone) " +0800" else ""
    val time = date.format(DateTimeFormatter.ofPattern(if (seconds) "HH:mm:ss" else "HH:mm"))
    val day = if (weekday) "${listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")[date.dayOfWeek.value - 1]} " else ""
    if (relative) {
        if (diff.seconds < 60) return "刚刚$zone"
        if (diff.toMinutes() < 60) return "${diff.toMinutes()}分钟前$zone"
        if (diff.toHours() < 24 && date.toLocalDate() == now.toLocalDate()) return "${diff.toHours()}小时前$zone"
        if (date.toLocalDate() == now.toLocalDate().minusDays(1)) return "${day}昨天 $time$zone"
    }
    return "$day${if (year || date.year != now.year) "${date.year}年" else ""}${date.monthValue}月${date.dayOfMonth}日 $time$zone"
}
