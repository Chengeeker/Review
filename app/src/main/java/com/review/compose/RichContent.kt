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
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
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

fun ReviewModel.openLink(raw: String) {
    val url = richLinkKey(raw)
    if (url.isBlank()) { notice = "链接地址不可用"; return }
    if (!openNativeLink(url)) navigate("browser:${Uri.encode(url)}")
}

fun ReviewModel.openNativeLink(url: String): Boolean {
    articleId(url)?.let { navigate("article:$it"); return true }
    if (videoObjectId(url) != null || liveRoomId(url) != null || (Uri.parse(url).host.orEmpty().endsWith(".weibocdn.com") && Regex("\\.(mp4|m3u8|webm|mov|flv)([?#]|$)", RegexOption.IGNORE_CASE).containsMatchIn(url))) { navigate("video:${Uri.encode(url)}"); return true }
    val uri = Uri.parse(url)
    val official = uri.host in setOf("weibo.com", "www.weibo.com", "m.weibo.cn", "weibo.cn")
    if (official) {
        Regex("^/(?:status/|detail/|[0-9]+/)([a-zA-Z0-9]+)$").find(uri.path.orEmpty())?.let { openPost(Post(it.groupValues[1], "", text = "")); return true }
        Regex("^/(?:u|profile)/(\\d+)").find(uri.path.orEmpty())?.let { navigate("profile:${it.groupValues[1]}"); return true }
        Regex("^/p/(100808[a-zA-Z0-9]+)").find(uri.path.orEmpty())?.let { navigate("topic:${it.groupValues[1]}"); return true }
        if (uri.path.orEmpty().startsWith("/n/")) { navigate("profile:${Uri.decode(uri.lastPathSegment.orEmpty())}"); return true }
    }
    if (uri.host == "s.weibo.com" && uri.path.orEmpty().startsWith("/weibo")) { openSearchResults(uri.getQueryParameter("q").orEmpty()); return true }
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
                val hot = link?.optString("url_type") == "2" || (token.startsWith('#') && raw.optJSONArray("topic_struct").objects().any { it.optString("topic_title") == token.trim('#') && it.optBoolean("is_hot") })
                withLink(LinkAnnotation.Clickable(token, TextLinkStyles(SpanStyle(color = if (hot && linkColor == Color.Unspecified) Color(0xFFFF8200) else color, fontWeight = linkWeight, textDecoration = if (linkColor != Color.Unspecified) androidx.compose.ui.text.style.TextDecoration.Underline else null))) {
                    pulse()
                    when {
                        token.startsWith('@') -> model.navigate("profile:${token.drop(1)}")
                        token.startsWith('#') -> {
                            val topic = raw.optJSONArray("topic_struct").objects().firstOrNull { it.optString("topic_title") == token.trim('#') }
                            val id = topic?.optString("topic_id").orEmpty()
                            if (id.startsWith("100808")) model.navigate("topic:$id") else { model.openSearchResults(token) }
                        }
                        else -> model.openLink(video?.second ?: link?.optString("long_url").orEmpty().ifBlank { token })
                    }
                }) { append(display) }
            }
            position = match.range.last + 1
        }
        append(value.substring(position))
    }
    Text(annotated, modifier, style = style, inlineContent = inline)
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
