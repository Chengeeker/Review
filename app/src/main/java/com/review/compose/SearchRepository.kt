package com.review.compose

import android.net.Uri
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.jsoup.Jsoup
import java.io.IOException
import java.time.LocalDate
import java.time.ZoneId

val searchTypes = linkedMapOf("hasori" to "原创", "hasret" to "转发", "hastext" to "纯文字", "haspic" to "含图片", "hasvideo" to "含视频", "hasmusic" to "含音乐", "hasv" to "V+微博")
data class FollowingFilter(val query: String, val types: Set<String>, val start: LocalDate?, val end: LocalDate) {
    fun params(page: Int, zone: ZoneId = ZoneId.systemDefault()): Map<String, String> {
        require(page > 0 && types.isNotEmpty() && types.all { it in searchTypes }) { "请选择微博类型" }
        require(start == null || !start.isAfter(end)) { "开始日期不能晚于结束日期" }
        return buildMap {
            if (query.isNotBlank()) put("q", query.trim())
            start?.let { put("starttime", it.atStartOfDay(zone).toEpochSecond().toString()) }
            put("endtime", end.plusDays(1).atStartOfDay(zone).toEpochSecond().toString())
            types.forEach { put(it, "1") }; put("atten", "1"); put("count", "10"); put("page", "$page")
        }
    }
}
suspend fun Repository.followingSearch(cookie: String, filter: FollowingFilter, page: Int): Pair<Page<Post>, Int> {
    val body = get("/ajax/statuses/search", cookie, filter.params(page))
    require(body.optInt("ok") == 1 && body.optJSONArray("statuses") != null) { "关注微博搜索失败，请检查登录状态后重试" }
    val posts = body.getJSONArray("statuses").objects().map(::parsePost)
    val total = body.optInt("total_number", -1)
    return Page(posts, if (posts.isNotEmpty() && (if (total >= 0) page * 10 < total else posts.size >= 10)) "${page + 1}" else "0") to total
}
suspend fun Repository.searchPeople(cookie: String, query: String, page: Int): Page<User> {
    val clean = query.trim().removePrefix("@").trim()
    if (clean.isBlank()) return Page(emptyList())
    try {
        val html = api.raw("https://s.weibo.com/user", cookie, mapOf("q" to clean, "page" to "$page"), html = true).text
        val doc = withContext(Dispatchers.Default) { Jsoup.parse(html) }
        doc.selectFirst("#pl_user_feedList")?.let { list ->
            val users = list.select(".card-user-b").mapNotNull { card ->
                val name = card.selectFirst("a.name") ?: return@mapNotNull null
                val id = Regex("/u/([0-9]+)").find(name.attr("href"))?.groupValues?.get(1) ?: return@mapNotNull null
                val info = card.selectFirst(".info")
                val fans = Regex("粉丝[：:]\\s*([0-9.]+)\\s*([万亿]?)").find(info?.text().orEmpty())?.groupValues
                val badge = card.selectFirst(".avator [title*=认证]")
                val description = info?.select("p")?.map { it.text() }?.filterNot { it.contains("粉丝") }?.joinToString(" ").orEmpty()
                User(id, name.text(), secureImage(card.selectFirst(".avator img")?.attr("src").orEmpty()),
                    description, followers = fans?.drop(1)?.joinToString("").orEmpty(), verified = if (badge != null) description else "",
                    isVerified = badge != null, verifiedType = if (badge == null) -1 else if (badge.attr("title").contains("个人")) 0 else 2)
            }
            return Page(users, if (doc.selectFirst("a.next[href]") != null) "${page + 1}" else "0")
        }
        if (doc.selectFirst(".card-no-result") != null) return Page(emptyList())
    } catch (e: CancellationException) { throw e } catch (_: IOException) { }
    val root = api.get(ApiClient.MOBILE + "/api/container/getIndex", cookie, mapOf("containerid" to "100103type=3&q=$clean", "page" to "$page"))
    val users = mutableListOf<User>()
    fun collect(node: JSONObject) {
        node.optJSONObject("user")?.let { users += parseUser(it) }
        node.optJSONArray("card_group").objects().forEach(::collect)
    }
    responseArray(root, "cards").objects().forEach(::collect)
    return Page(users.distinctBy(User::id), if (users.isEmpty()) "0" else "${page + 1}")
}
fun belongsToTopic(post: JSONObject, id: String): Boolean {
    fun matches(value: String): Boolean {
        val uri = runCatching { android.net.Uri.parse(value) }.getOrNull() ?: return false
        return (uri.scheme == "sinaweibo" && uri.host == "pageinfo" && uri.getQueryParameter("pageid") == id) ||
            (uri.host in setOf("weibo.com", "m.weibo.cn") && uri.path == "/p/$id")
    }
    if (matches(post.optJSONObject("title_source")?.optString("url").orEmpty())) return true
    return post.optJSONArray("url_struct").objects().any { it.optString("page_id") == id || matches(it.optString("h5_target_url")) || matches(it.optString("long_url")) }
}
suspend fun Repository.globalSearch(cookie: String, query: String, page: Int, topicId: String = "", topicTitle: String = ""): Page<Post> {
    if (topicId.isBlank() && cookie.isBlank()) nativeKeywordPosts(cookie, query, page)?.let { return it }
    try {
        val html = api.raw("https://s.weibo.com/weibo", cookie, mapOf("q" to if (topicId.isBlank()) query else "$topicTitle $query", "page" to "$page"), html = true).text
        val doc = withContext(Dispatchers.Default) { Jsoup.parse(html) }
        val cards = doc.select(".card-wrap[mid]")
        if (cards.isEmpty() && doc.selectFirst(".card-no-result, #pl_feedlist_index") == null) throw IOException("搜索服务暂不可用")
        val ids = cards.map { it.attr("mid") }.filter { it.matches(Regex("[0-9]+")) }.distinct().take(20)
        val posts = mutableListOf<Post>()
        for (batch in ids.chunked(4)) posts += coroutineScope { batch.map { id -> async {
            try {
                val root = get("/ajax/statuses/show", cookie, mapOf("id" to id))
                val card = cards.first { it.attr("mid") == id }
                val badge = card.selectFirst(".card-top")?.text().orEmpty()
                if (badge.contains("置顶") || card.selectFirst(".icon-top,.label-top") != null) root.put("isTop", true).put("title", JSONObject().put("text", "置顶"))
                else if (badge.contains("热门") || card.selectFirst(".card-top .icon-star,.card-top .icon-hot") != null) root.put("title", JSONObject().put("text", "热门"))
                if (topicId.isNotBlank() && (!belongsToTopic(root, topicId) || !plainText(root.optString("text_raw").ifBlank { root.optString("text") }).contains(query, true))) null else parsePost(root)
            } catch (e: CancellationException) { throw e } catch (_: IOException) { null }
        } }.awaitAll().filterNotNull() }
        if (ids.isNotEmpty() && posts.isEmpty() && topicId.isBlank()) throw IOException("搜索内容暂不可用")
        return Page(parsePosts(cookie, posts.map { JSONObject(it.raw) }), if (doc.selectFirst("a.next[href]") != null) "${page + 1}" else "0")
    } catch (e: CancellationException) { throw e }
    catch (e: IOException) { if (topicId.isNotBlank()) throw e }
    return try { search(cookie, query, page) }
    catch (failure: IOException) {
        if (topicId.isNotBlank() || cookie.isBlank()) throw failure
        nativeKeywordPosts(cookie, query, page) ?: throw failure
    }
}

private suspend fun Repository.nativeKeywordPosts(cookie: String, query: String, page: Int): Page<Post>? {
    return try {
        val root = nativeGet("cardlist", mapOf("containerid" to "100103type=1&q=${Uri.encode(query)}", "page" to "$page")) ?: return null
        val rows = pageCards(root).mapNotNull { it.optJSONObject("mblog") }
            .filter { it.optString("idstr").ifBlank { it.optString("id") }.isNotBlank() }.toList()
        if (rows.isEmpty()) return null
        val posts = parsePosts(cookie, rows).distinctBy(Post::id)
        Page(posts, "${page + 1}")
    } catch (cancelled: CancellationException) { throw cancelled }
    catch (_: Exception) { null }
}
suspend fun Repository.hotList(cookie: String, category: String): List<Trend> {
    val endpoints = mapOf("mine" to "mineBand", "ent" to "entertainment", "social" to "social", "tech" to "technology", "life" to "life", "sports" to "sport", "acg" to "acg")
    if (cookie.isBlank() && category == "hot") nativeHotList(category)?.let { return it }
    val paths = if (category == "hot") listOf("/ajax/side/hotSearch", "/ajax/statuses/hot_band")
        else listOf("/ajax/statuses/${endpoints.getValue(category)}")
    val webCookie = if (category == "hot") api.cookieFor(ApiClient.DESKTOP, cookie) else cookie
    for (path in paths) {
        try {
            val items = webTrends(get(path, webCookie))
            if (items.isNotEmpty()) return items
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: IOException) { }
    }
    if (cookie.isNotBlank() || category != "hot") nativeHotList(category)?.let { return it }
    if (category == "hot" && webCookie.isNotBlank()) {
        for (path in paths) {
            try {
                val items = webTrends(get(path, ""))
                if (items.isNotEmpty()) return items
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: IOException) { }
        }
    }
    throw IOException("暂时无法读取此榜单，请稍后重试")
}

private fun webTrends(root: JSONObject): List<Trend> {
    val data = root.optJSONObject("data") ?: throw IOException("榜单结构不完整")
    val pinned = data.optJSONArray("hotgovs").objects().toMutableList().apply { data.optJSONObject("hotgov")?.let(::add) }
    val ranked = data.optJSONArray("realtime") ?: data.optJSONArray("band_list") ?: throw IOException("未返回榜单")
    return (pinned.mapIndexed { i, item -> parseTrend(item, i, true) } + ranked.objects().mapIndexed { i, item -> parseTrend(item, i) }).filter { it.word.isNotBlank() }.distinctBy(Trend::word)
}

private suspend fun Repository.nativeHotList(category: String): List<Trend>? {
    return try {
        val root = nativeGet("cardlist", mapOf(
            "containerid" to "106003type=25&t=3&disable_hot=1&filter_type=realtimehot",
            "extparam" to "mi_cid=100103",
            "hot_search_page" to "1"
        )) ?: return null
        if (category == "hot") return nativeTrends(root).takeIf { it.isNotEmpty() }

        val titles = mapOf("mine" to setOf("我的", "我的热搜"), "ent" to setOf("文娱", "娱乐", "文娱榜"),
            "social" to setOf("社会", "社会榜"), "tech" to setOf("科技", "科技榜"), "life" to setOf("生活", "生活榜"),
            "sports" to setOf("体育", "体育榜"), "acg" to setOf("ACG", "ACG榜"))
        val container = pageCards(root).mapNotNull { card ->
            val title = card.optString("title").ifBlank { card.optString("name").ifBlank { card.optString("desc") } }
            if (title !in titles.getValue(category)) return@mapNotNull null
            trendScheme(card)?.takeIf { it.host == "pageinfo" && it.getQueryParameter("q").isNullOrBlank() }
                ?.getQueryParameter("containerid")?.takeIf { !it.contains("&q=") }
        }.firstOrNull { it.isNotBlank() } ?: return null
        val board = nativeGet("cardlist", mapOf("containerid" to container, "hot_search_page" to "1")) ?: return null
        nativeTrends(board).takeIf { it.isNotEmpty() }
    } catch (cancelled: CancellationException) { throw cancelled }
    catch (_: Exception) { null }
}

private fun pageCards(root: JSONObject, depth: Int = 0): Sequence<JSONObject> = sequence {
    if (depth >= 7) return@sequence
    yield(root)
    for (name in listOf("data", "cardlistInfo", "pageInfo")) {
        root.optJSONObject(name)?.let { yieldAll(pageCards(it, depth + 1)) }
    }
    for (name in listOf("cards", "card_group", "tabs")) {
        root.optJSONArray(name).objects().forEach { yieldAll(pageCards(it, depth + 1)) }
    }
}

private fun trendScheme(card: JSONObject): Uri? = Uri.parse(card.optString("scheme"))
    .takeIf { it.scheme == "sinaweibo" && it.isHierarchical }

private fun nativeTrends(root: JSONObject): List<Trend> {
    val items = mutableListOf<Trend>()
    val words = mutableSetOf<String>()
    var rank = 1
    for (card in pageCards(root)) {
        val uri = trendScheme(card) ?: continue
        val container = uri.getQueryParameter("containerid").orEmpty()
        val query = uri.getQueryParameter("q") ?: Uri.parse("https://m.weibo.cn/?$container").getQueryParameter("q")
        val word = plainText(card.optString("word").ifBlank {
            card.optString("desc").ifBlank { card.optString("title_sub").ifBlank { query.orEmpty() } }
        })
        if (query.isNullOrBlank() || word.isBlank() || !words.add(word)) continue
        val parsed = parseTrend(card, rank - 1)
        val heat = parsed.heat.ifBlank { plainText(card.optString("desc_extr")) }
        items += parsed.copy(word = word, heat = heat, rank = if (parsed.pinned) 0 else rank++, ranked = !parsed.pinned)
    }
    return items
}
