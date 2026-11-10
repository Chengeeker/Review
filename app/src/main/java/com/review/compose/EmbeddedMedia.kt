package com.review.compose

import org.json.JSONObject

internal fun attachmentLinkPattern(url: String): Regex = Regex(
    "(?<![A-Za-z0-9])https?://" + Regex.escape(url.substringAfter("://").replace(Regex("[\u200B\u200C\u200D\uFEFF]"), "")) +
        "(?![A-Za-z0-9_/?#&=.%+-])")

internal fun statusReferencesLink(status: JSONObject, link: JSONObject): Boolean {
    val text = listOf("text_raw", "text", "full_text_raw", "longTextContent_raw", "longTextContent")
        .joinToString("\n") { status.optString(it) }.replace("http://", "https://")
        .replace(Regex("[\u200B\u200C\u200D\uFEFF]"), "")
    return listOf("short_url", "url_ori").any { key ->
        link.optString(key).takeIf { it.startsWith("http://") || it.startsWith("https://") }
            ?.let { attachmentLinkPattern(it).containsMatchIn(text) } == true
    }
}

internal fun linkedPictures(link: JSONObject): List<Media> {
    val infos = link.optJSONObject("pic_infos") ?: return emptyList()
    return infos.keys().asSequence().mapNotNull { key ->
        val info = infos.optJSONObject(key) ?: return@mapNotNull null
        val url = listOf("largest", "original", "large", "bmiddle", "thumbnail").firstNotNullOfOrNull { size ->
            secureImage(info.optJSONObject(size)?.optString("url").orEmpty()).takeIf(String::isNotBlank)
        } ?: secureImage(info.optString("url"))
        val host = android.net.Uri.parse(url).host.orEmpty()
        if (url.isBlank() || (!host.endsWith(".sinaimg.cn") && !Regex("\\.(jpg|jpeg|png|gif|webp|heic)([?#]|$)", RegexOption.IGNORE_CASE).containsMatchIn(url))) null
        else pictureMedia(info, url)
    }.toList()
}

fun embeddedMedia(status: JSONObject): List<Media> {
    val results = mutableListOf<Media>()
    fun parse(value: JSONObject, outer: JSONObject = value) {
        val type = value.optString("type").ifBlank { value.optString("object_type") }.lowercase()
        val cardInfo = value.optJSONObject("card_info")
        val title = outer.optString("url_title").ifBlank { outer.optString("title") }.ifBlank { value.optString("page_title") }
            .ifBlank { cardInfo?.optString("title").orEmpty() }.ifBlank { value.optString("display_name") }
        val urls = listOf("articleUrl", "article_url", "page_url", "url", "long_url", "target_url").flatMap { listOf(value.optString(it), outer.optString(it)) }
        if (type.contains("vote") || type.contains("poll") || type.contains("lottery") || value.has("vote_object") || value.optBoolean("card_is_poll") || urls.any { it.contains("lottery.sina.cn") || it.contains("vote.weibo") || liveRoomId(it) != null || videoObjectId(it) != null } || title.contains("抽奖")) return
        val article = urls.firstOrNull { articleId(it) != null }.orEmpty()
        results += linkedPictures(value)
        val automatic = outer.optInt("url_type") == 39 || outer.optJSONObject("info")?.optInt("type") == 39 ||
            value.has("media_pic_url") || type in setOf("bigpic", "big_pic", "webpage") || value.optString("card_object_type") == "webpage"
        if (article.isBlank() && !automatic) return
        val pic = value.optJSONObject("page_pic")
        val pictures = cardInfo?.optJSONObject("page_info")?.optJSONObject("pic_info") ?: cardInfo?.optJSONObject("pic_info") ?: value.optJSONObject("pic_info")
        val big = pictures?.optJSONObject("pic_big")
        val middle = pictures?.optJSONObject("pic_middle")
        fun image(vararg urls: String?) = urls.firstNotNullOfOrNull { secureImage(it.orEmpty()).takeIf(String::isNotBlank) }.orEmpty()
        // The desktop page thumbnail may already contain its own background.
        val foreground = image(cardInfo?.optString("pic_url"), value.optString("pic_url"), value.optJSONObject("image")?.optString("url"), pic?.optString("url"),
            pic?.optString("image_url"), value.opt("page_pic") as? String, value.optString("page_pic_url"),
            value.optString("card_image_url"), value.optString("media_pic_url"))
        if (foreground.isBlank()) return
        val foregroundId = commentImageIdentity(foreground)
        val background = listOf(big?.optString("url"), middle?.optString("url"), value.optString("media_pic_url"),
            value.optString("background_url"), value.optString("card_background_url")).firstNotNullOfOrNull { candidate ->
            secureImage(candidate.orEmpty()).takeIf { it.isNotBlank() && commentImageIdentity(it) != foregroundId }
        }.orEmpty()
        val dimensions = (if (background.isNotBlank()) listOf(big, middle) else listOf(pic, value.optJSONObject("image"), value, big, middle))
            .filterNotNull().firstOrNull { it.optInt("width") > 0 && it.optInt("height") > 0 }
        val width = dimensions?.optInt("width") ?: outer.optInt("card_image_width").takeIf { background.isBlank() && it > 0 } ?: 16
        val height = dimensions?.optInt("height") ?: outer.optInt("card_image_height").takeIf { background.isBlank() && it > 0 } ?: 9
        val link = image(outer.optString("short_url"), outer.optString("url_ori"), outer.optJSONObject("info")?.optString("url_short"))
        results += Media(foreground, width = width, height = height,
            article = article, background = background, card = article.isBlank(), title = title, cardLink = if (article.isBlank()) link else "")
    }
    status.optJSONArray("url_struct").objects().forEach { link ->
        if (!status.has("retweeted_status") || statusReferencesLink(status, link)) parse(link)
    }
    status.optJSONArray("url_objects").objects().forEach { entry ->
        val wrapper = entry.optJSONObject("object") ?: return@forEach
        val inner = wrapper.optJSONObject("object") ?: wrapper
        if (!status.has("retweeted_status") || statusReferencesLink(status, entry)) parse(inner, entry)
    }
    if (!status.has("retweeted_status")) status.optJSONObject("page_info")?.let { page ->
        val links = status.optJSONArray("url_struct").objects().filter { it.optInt("url_type") == 39 || articleId(it.optString("long_url")) != null }
        val pageId = page.optString("page_id")
        val link = links.firstOrNull { pageId.isNotEmpty() && it.optString("page_id") == pageId } ?: links.singleOrNull()
        parse(page, link ?: page)
    }
    return mergeStatusMedia(emptyList(), results)
}

internal fun Media.birthdayCaption(): String = title.trim().takeIf { card && it.contains("生日") }.orEmpty()

internal fun String.withoutWebCardLinks(media: List<Media>): String {
    var body = this
    for (item in media) {
        if (item.card && item.cardLink.startsWith("https://")) body = body.replace(attachmentLinkPattern(item.cardLink), "").trim()
    }
    return body
}
