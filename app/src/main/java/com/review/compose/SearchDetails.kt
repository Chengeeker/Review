package com.review.compose

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import org.json.JSONObject
import java.time.Instant
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

data class TopicHeader(val title: String, val summary: String, val image: String, val reads: Long, val mentions: Long,
    val host: User?, val topId: String, val url: String)
fun parseTopicHeader(root: JSONObject): TopicHeader {
    val obj = root.optJSONObject("object") ?: JSONObject()
    val attr = root.optJSONObject("object_attr") ?: JSONObject()
    val image = when (val value = obj.opt("image")) {
        is String -> value
        is JSONObject -> listOf("url", "pic_big", "pic_middle", "pic_small").firstNotNullOfOrNull { value.optString(it).takeIf(String::isNotBlank) }.orEmpty()
        else -> ""
    }.ifBlank { attr.optString("image") }
    val count = root.optJSONObject("count") ?: JSONObject()
    val topId = attr.optJSONObject("intention")?.optString("topping_docs_topic").orEmpty().substringBefore('_').takeIf { it.matches(Regex("[0-9]+")) }.orEmpty()
    return TopicHeader(root.optString("topic_ori").ifBlank { obj.optString("display_name") }, plainText(obj.optString("summary")), secureImage(image), count.optLong("read"), count.optLong("mention"),
        root.optJSONObject("claim_info")?.let(::parseUser), topId, secureImage(obj.optString("url").ifBlank { obj.optString("target_url") }))
}
data class SearchDetails(val page: Page<Post>, val header: TopicHeader?, val topping: Post?)
fun searchKeyword(query: String): String {
    val clean = query.replace("#", "").trim()
    return if (query.startsWith('#') || query.endsWith('#') || Regex("vs|VS|对战|PK|pk|与|和|战胜|击败").containsMatchIn(clean)) "#$clean#" else query
}
suspend fun Repository.searchDetails(cookie: String, query: String, page: Int): SearchDetails = coroutineScope {
    val keyword = searchKeyword(query)
    val metadata = async {
        if (page != 1) null else try { get("/ajax/statuses/search", cookie, mapOf("q" to keyword, "page" to "1")).optJSONObject("topicHeads")?.let(::parseTopicHeader) }
        catch (e: CancellationException) { throw e } catch (_: Exception) { null }
    }
    val results = globalSearch(cookie, keyword, page)
    val header = metadata.await()
    var top = results.items.firstOrNull()?.takeIf { it.data.optBoolean("isTop") }
    if (top == null && !header?.topId.isNullOrBlank()) {
        top = results.items.firstOrNull { it.id == header!!.topId }
        if (top == null) try { top = parsePost(get("/ajax/statuses/show", cookie, mapOf("id" to header!!.topId)).put("isTop", true).put("title", JSONObject().put("text", "置顶"))) }
        catch (e: CancellationException) { throw e } catch (_: Exception) { }
    }
    SearchDetails(results, header, top)
}
fun searchDisplayPosts(posts: List<Post>, tab: String): List<Post> = when (tab) {
    "实时" -> posts.sortedByDescending { post ->
        runCatching { Instant.parse(post.time).toEpochMilli() }.getOrElse {
            runCatching { ZonedDateTime.parse(post.time, DateTimeFormatter.ofPattern("EEE MMM dd HH:mm:ss Z yyyy", Locale.ENGLISH)).toInstant().toEpochMilli() }.getOrDefault(0L)
        }
    }
    "热门" -> posts.sortedByDescending { it.likes.toLong() + it.shares }
    "视频" -> posts.filter { it.text.contains("视频") || it.text.contains("http") }.ifEmpty { posts }
    "话题" -> posts.filter { it.text.contains('#') }.ifEmpty { posts }
    else -> posts
}
fun topicCount(value: Long): String {
    val divisor = if (value >= 100000000) 100000000 else if (value >= 10000) 10000 else return "$value"
    return String.format(Locale.ROOT, "%.1f", value.toDouble() / divisor).removeSuffix(".0") + if (divisor == 10000) "万" else "亿"
}
