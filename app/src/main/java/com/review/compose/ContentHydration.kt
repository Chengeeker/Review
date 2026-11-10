package com.review.compose

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject

private val textGate = Semaphore(2)
private val textLocks = Array(16) { Mutex() }
private val texts = android.util.LruCache<String, String>(96)
private val cardGate = Semaphore(6)
private val cardLocks = Array(16) { Mutex() }
private val cards = android.util.LruCache<String, String>(96)

fun needsCardHydration(post: Post): Boolean {
    val data = post.data
    val vote = listOf("is_vote", "isVote", "hasActionTypeCard", "has_action_type_card").any { data.optString(it) in setOf("1", "true") } ||
        listOf("vote_info", "vote_object", "vote_dynamic").any(data::has) || data.optJSONArray("url_struct").objects().any { it.toString().contains(Regex("vote\\.weibo|投票|vote_object")) }
    val card = data.optJSONArray("url_struct").objects().any { it.optInt("url_type") == 39 || it.optString("card_object_type") == "webpage" }
    return (parsePoll(data) == null && vote) || (post.images.none { it.video.isNotBlank() && !it.live } && (card || post.source == "微博直播"))
}

fun mergeStatusMedia(old: List<Media>, fresh: List<Media>): List<Media> {
    val video = fresh.any { it.video.isNotBlank() && !it.live }
    val merged = mutableListOf<Media>()
    old.filterNot { video && it.card }.forEach { media ->
        if (media.video.isNotBlank() && !media.live) merged.mergeVideo(media) else merged += media
    }
    fresh.filterNot { video && it.card }.forEach { media ->
        if (media.video.isNotBlank() && !media.live) {
            merged.mergeVideo(media, preferCandidate = true)
            return@forEach
        }
        val index = merged.indexOfFirst {
            it.video == media.video && (commentImageIdentity(it.url) == commentImageIdentity(media.url) ||
                it.card && media.card && it.cardLink.isNotBlank() && it.cardLink == media.cardLink)
        }
        if (index < 0) merged += media else {
            val previous = merged[index]
            val preferred = if (previous.card && previous.background.isNotBlank() && media.background.isBlank()) previous else media
            val geometry = if (preferred.width <= 0 || preferred.height <= 0) previous else preferred
            merged[index] = preferred.copy(background = media.background.ifBlank { previous.background },
                width = geometry.width, height = geometry.height,
                article = media.article.ifBlank { previous.article },
                preview = media.preview.ifBlank { previous.preview },
                title = media.birthdayCaption().ifBlank { previous.birthdayCaption() }.ifBlank { preferred.title }.ifBlank { previous.title },
                card = media.card || previous.card, cardLink = media.cardLink.ifBlank { previous.cardLink })
        }
    }
    return merged
}

suspend fun Repository.hydrateCards(cookie: String, source: Post): Post {
    var post = source
    if (needsCardHydration(source)) {
        val key = java.security.MessageDigest.getInstance("SHA-256").digest(cookie.toByteArray()).joinToString("") { "%02x".format(it) } + ":${source.id}"
        try {
            val raw = cardLocks[(key.hashCode() and Int.MAX_VALUE) % cardLocks.size].withLock {
                cards.get(key) ?: cardGate.withPermit {
                    val root = api.get(ApiClient.MOBILE + "/api/statuses/show", cookie, mapOf("id" to source.id))
                    val value = root.optJSONObject("data") ?: root
                    require(value.has("id") || value.has("idstr"))
                    value.toString().also { cards.put(key, it) }
                }
            }
            val original = source.data
            val extra = JSONObject(raw)
            val merged = JSONObject(original.toString())
            extra.keys().forEach { merged.put(it, extra.opt(it)) }
            if (original.has("title")) merged.put("title", original.opt("title"))
            val hydrated = parsePost(merged)
            val images = mergeStatusMedia(source.images, hydrated.images)
            post = hydrated.copy(images = images, text = hydrated.text.ifBlank { source.text }.withoutWebCardLinks(images),
                avatar = if (source.uid == hydrated.uid) source.avatar.ifBlank { hydrated.avatar } else hydrated.avatar)
        } catch (e: CancellationException) { throw e } catch (_: Exception) { }
    }
    return post.copy(repost = source.repost?.let { hydrateCards(cookie, it) })
}
suspend fun Repository.fullText(cookie: String, id: String): String {
    val scope = java.security.MessageDigest.getInstance("SHA-256").digest(cookie.toByteArray()).joinToString("") { "%02x".format(it) }
    val key = "$scope:$id"
    return textLocks[(key.hashCode() and Int.MAX_VALUE) % textLocks.size].withLock {
        texts.get(key)?.let { return@withLock it }
        val data = textGate.withPermit { get("/ajax/statuses/longtext", cookie, mapOf("id" to id)).optJSONObject("data") }
        val raw = listOf("longTextContent_raw", "longTextContent", "text_raw").firstNotNullOfOrNull { data?.optString(it)?.takeIf(String::isNotBlank) }.orEmpty()
        val clean = cleanLongText(raw)
        check(clean.isNotBlank()) { "暂未返回完整正文，请重试" }
        texts.put(key, clean); clean
    }
}
internal fun cleanLongText(value: String): String {
    val text = value.replace("\r\n", "\n").replace('\r', '\n')
    if (!Regex("<[/!]?[A-Za-z][^<>]*>").containsMatchIn(text)) return text.trim()
    return cleanRichHtml(text, preserveLineBreaks = true)
}

internal fun Post.availableFullText(): String = listOf("full_text_raw", "longTextContent_raw", "longTextContent")
    .firstNotNullOfOrNull { data.optString(it).takeIf(String::isNotBlank) }?.let(::cleanLongText).orEmpty()

fun cleanRichHtml(html: String, preserveLineBreaks: Boolean = false): String {
    val doc = org.jsoup.Jsoup.parseBodyFragment(html)
    doc.select("img[alt]").forEach { it.replaceWith(org.jsoup.nodes.TextNode(it.attr("alt"))) }
    doc.select("a[href]").forEach { element ->
        if (element.attr("href").contains(Regex("(?:video\\.weibo\\.com|weibo\\.com/tv/show|weibo\\.cn/s/video/show)"))) element.text(element.attr("href"))
    }
    if (preserveLineBreaks) {
        doc.outputSettings().prettyPrint(false)
        doc.body().getAllElements().flatMap { it.textNodes() }.filter { '\n' in it.wholeText }.forEach { node ->
            node.wholeText.split('\n').forEachIndexed { index, line ->
                if (index > 0) node.before(org.jsoup.nodes.Element("br"))
                if (line.isNotEmpty()) node.before(org.jsoup.nodes.TextNode(line))
            }
            node.remove()
        }
    }
    return plainText(doc.body().html())
}
suspend fun Repository.hydrateText(cookie: String, post: Post): Post {
    var current = post
    if (post.longText && post.data.optString("full_text_raw").isBlank()) {
        try { current = post.copy(raw = JSONObject(post.raw).put("full_text_raw", fullText(cookie, post.id)).toString()) }
        catch (e: CancellationException) { throw e } catch (_: Exception) { }
    }
    return current.copy(repost = post.repost?.let { hydrateText(cookie, it) })
}
suspend fun Repository.parsePosts(cookie: String, items: List<JSONObject>, longText: Boolean = true): List<Post> = coroutineScope {
    items.map { json -> async(kotlinx.coroutines.Dispatchers.Default) { val post = hydrateCards(cookie, parsePost(json)); if (longText) hydrateText(cookie, post) else post } }.awaitAll()
}
