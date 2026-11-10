package com.review.compose

import org.json.JSONArray
import org.json.JSONObject

fun normalizedLinks(status: JSONObject): List<JSONObject> {
    val links = status.optJSONArray("url_struct").objects().map { JSONObject(it.toString()) }.toMutableList()
    status.optJSONArray("url_objects").objects().forEach { entry ->
        val info = entry.optJSONObject("info") ?: JSONObject()
        val wrapper = entry.optJSONObject("object") ?: JSONObject()
        val media = wrapper.optJSONObject("object") ?: wrapper
        val image = media.optJSONObject("image")
        fun first(vararg values: String?) = values.firstOrNull { !it.isNullOrBlank() && it != "null" }.orEmpty()
        val short = first(entry.optString("url_ori"), info.optString("url_short"))
        val target = first(wrapper.optString("target_url"), media.optString("target_url"), media.optString("url"), info.optString("url_long"))
        val objectId = first(entry.optString("object_id"), entry.optString("returned_object_id"), wrapper.optString("object_id"), media.optString("object_id"))
        val type = first(media.optString("object_type"), wrapper.optString("object_type"))
        val qualities = linkedMapOf<String, String>()
        fun quality(label: String, value: String?) { val url = playableVideo(value.orEmpty()); if (url.isNotBlank() && url !in qualities.values) qualities[label] = url }
        media.optJSONObject("urls")?.let { urls -> urls.keys().forEach { quality(it, urls.optString(it)) } }
        quality("高清", media.optJSONObject("stream")?.optString("hd_url")); quality("默认画质", media.optJSONObject("stream")?.optString("url")); quality("原画", media.optString("original_url"))
        val normalized = JSONObject().put("short_url", short).put("long_url", target).put("h5_target_url", target).put("object_id", objectId)
            .put("url_title", first(info.optString("title"), media.optString("display_name"), media.optString("title"), wrapper.optString("display_name")))
            .put("url_type", info.opt("type")).put("card_object_type", type)
            .put("video_cover_url", first(media.optJSONObject("screenshots")?.optString("1"), image?.optString("url"), media.optString("cover_image")))
        if (type.lowercase() in setOf("webpage", "article") || articleId(target) != null || info.optString("type") == "39") {
            normalized.put("card_image_url", first(media.optString("pic_url"), image?.optString("url"), media.optString("cover_image")))
                .put("card_image_width", image?.optInt("width") ?: media.optInt("width"))
                .put("card_image_height", image?.optInt("height") ?: media.optInt("height"))
        }
        if (qualities.isNotEmpty()) normalized.put("video_quality_urls", JSONObject(qualities)).put("video_url", qualities.values.first())
        if (media.has("vote_object") || media.has("vote_info") || media.has("poll_info")) normalized.put("card_is_poll", true)
        val existing = links.firstOrNull { short.isNotBlank() && it.optString("short_url") == short }
        if (existing == null) links += normalized else normalized.keys().forEach { key -> if (!existing.has(key) || existing.optString(key).isBlank()) existing.put(key, normalized.opt(key)) }
    }
    return links
}

fun linkedVideo(link: JSONObject): Media? {
    val target = listOf("long_url", "h5_target_url").map(link::optString)
        .firstOrNull { videoObjectId(it) != null || liveRoomId(it) != null }.orEmpty()
    val stream = playableVideo(link.optString("video_url"))
    val video = stream.ifBlank { target }
    if (video.isBlank()) return null
    val qualities = link.optJSONObject("video_quality_urls") ?: JSONObject()
    return Media(secureImage(link.optString("video_cover_url").ifBlank { link.optString("card_image_url") }), video = video, title = link.optString("url_title"),
        qualities = qualities.keys().asSequence().associateWith { qualities.optString(it) },
        videoId = (videoObjectId(target) ?: normalizeVideoId(link.optString("object_id"))).orEmpty())
}
