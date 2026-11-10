package com.review.compose

import kotlinx.coroutines.CancellationException
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException

fun responseArray(root: JSONObject, vararg keys: String): JSONArray {
    val data = root.optJSONObject("data")
    for (key in keys) (data?.optJSONArray(key) ?: root.optJSONArray(key))?.let { return it }
    root.optJSONArray("data")?.let { return it }
    throw IOException("返回结构不完整，请重试")
}

suspend fun Repository.interact(cookie: String, action: String, id: String, enabled: Boolean = true): JSONObject {
    require(id.matches(Regex("[0-9]+"))) { "内容标识无效" }
    val desktop = when (action) {
        "like" -> if (enabled) "/ajax/statuses/setLike" else "/ajax/statuses/cancelLike"
        "favorite" -> if (enabled) "/ajax/statuses/createFavorites" else "/ajax/statuses/destoryFavorites"
        "follow" -> if (enabled) "/ajax/friendships/create" else "/ajax/friendships/destory"
        "delete" -> "/ajax/statuses/destroy"
        "commentLike" -> if (enabled) "/ajax/statuses/updateLike" else "/ajax/statuses/destroyLike"
        else -> error("未知操作")
    }
    val mobile = when (action) {
        "like" -> "/api/attitudes/${if (enabled) "create" else "destroy"}"
        "favorite" -> "/api/favorites/${if (enabled) "create" else "destory"}"
        "follow" -> "/api/friendships/${if (enabled) "create" else "destory"}"
        "delete" -> "/profile/delMyblog"
        else -> null
    }
    require(!mobileOnly || mobile != null) { "此操作需要桌面会话，请在账号页补充登录" }
    val fields = buildMap {
        put(if (action == "follow") "uid" else if (action == "delete" && mobileOnly) "mid" else if (action == "commentLike") "object_id" else "id", id)
        if (action == "like" && mobileOnly) put("attitude", "heart")
        if (action == "commentLike") put("object_type", "comment")
    }
    return api.post(if (mobileOnly) ApiClient.MOBILE + mobile else ApiClient.DESKTOP + desktop, cookie, fields)
}

suspend fun Repository.writeComment(cookie: String, postId: String, text: String, reply: String? = null): JSONObject {
    require(text.isNotBlank() && text.length <= 10000) { "请输入评论内容" }
    val statusId = numericStatusId(postId)
    val commentId = reply?.let(::numericStatusId)
    require(statusId.isNotBlank() && (commentId == null || commentId.isNotBlank())) { "评论编号无效" }
    val fields = buildMap {
        put("id", statusId); put(if (mobileOnly) "content" else "comment", text)
        if (commentId != null) put("cid", commentId)
    }
    return api.post((if (mobileOnly) ApiClient.MOBILE + "/api/comments/" else ApiClient.DESKTOP + "/ajax/comments/") + if (reply == null) "create" else "reply", cookie, fields)
}
suspend fun Repository.deleteComment(cookie: String, id: String) = api.post(
    if (mobileOnly) ApiClient.MOBILE + "/api/comments/destroy" else ApiClient.DESKTOP + "/ajax/statuses/destroyComment", cookie, mapOf("cid" to numericStatusId(id).also { require(it.isNotBlank()) { "评论编号无效" } }))

suspend fun Repository.commentPage(cookie: String, post: Post, cursor: String, hot: Boolean = false, parent: Comment? = null): Page<Comment> {
    val params = mapOf("id" to numericStatusId(parent?.id ?: post.id), "uid" to post.uid,
        "is_reload" to "1", "is_show_bulletin" to "2", "is_mix" to if (parent != null && cursor != "0") "1" else "0",
        "count" to if (cursor == "0" && parent == null) "10" else "20",
        "flow" to if (hot) "0" else "1", "fetch_level" to if (parent == null) "0" else "1", "locale" to "zh-CN", "max_id" to cursor)
    val inherited = parent?.images?.map { commentImageIdentity(it.url) }?.toSet().orEmpty()
    return accountRead(cookie, "comments/build_comments", params, "暂时无法读取评论", publicWeb = true,
        web = { get("/ajax/statuses/buildComments", cookie, params) }) { root ->
        val body = root.optJSONObject("data") ?: root
        val next = body.optString("max_id").takeIf { it.matches(Regex("[1-9][0-9]*")) } ?: "0"
        Page(responseArray(root, "comments", "data").objects().map { parseComment(it, inherited) }, next)
    }
}

suspend fun Repository.profile(cookie: String, id: String): User {
    val numeric = id.matches(Regex("[1-9][0-9]*"))
    if (cookie.isBlank() && numeric) nativeProfile(id)?.let { return it }
    try {
        val root = get("/ajax/profile/info", cookie, mapOf((if (numeric) "uid" else "screen_name") to id))
        val user = root.optJSONObject("data")?.optJSONObject("user")?.let(::parseUser)
        if (user != null && user.id.isNotBlank() && (!numeric || user.id == id)) return user
    } catch (cancelled: CancellationException) { throw cancelled }
    catch (_: IOException) { }
    if (cookie.isNotBlank() && numeric) nativeProfile(id)?.let { return it }
    throw IOException("暂时无法读取用户资料，请稍后重试")
}

private suspend fun Repository.nativeProfile(id: String): User? {
    for (path in listOf("profile", "users/show")) {
        val root = try { nativeGet(path, mapOf("uid" to id)) ?: return null }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { continue }
        val data = root.optJSONObject("data") ?: root
        val users = listOfNotNull(data.optJSONObject("userInfo"), data.optJSONObject("user"),
            root.optJSONObject("userInfo"), root.optJSONObject("user"), data) +
            data.optJSONArray("users").objects() + root.optJSONArray("users").objects()
        users.map(::parseUser).firstOrNull { it.id == id && it.name.isNotBlank() }?.let { return it }
    }
    return null
}
suspend fun Repository.userPosts(cookie: String, id: String, page: Int, query: String = "", feature: Int = 0, longText: Boolean = true): Page<Post> {
    if (query.isBlank()) try {
        val native = nativeGet("statuses/user_timeline", mapOf("uid" to id, "page" to "$page", "feature" to "$feature", "count" to "20", "trim_user" to "0", "base_app" to "0"))
        val source = native?.optJSONArray("statuses") ?: native?.optJSONObject("data")?.optJSONArray("list")
        if (source != null && (source.length() > 0 || cookie.isBlank())) {
            return Page(parsePosts(cookie, source.objects(), longText), if (source.length() == 0) "0" else "${page + 1}")
        }
    } catch (e: CancellationException) { throw e } catch (_: Exception) { }
    val root = if (query.isBlank()) get("/ajax/statuses/mymblog", cookie, mapOf("uid" to id, "page" to "$page", "feature" to "$feature"))
        else get("/ajax/statuses/search", cookie, mapOf("uid" to id, "q" to query, "page" to "$page"))
    val posts = parsePosts(cookie, responseArray(root, "list", "statuses").objects(), longText)
    return Page(posts, if (posts.isEmpty()) "0" else "${page + 1}")
}
suspend fun Repository.relations(cookie: String, id: String, page: Int, fans: Boolean): Page<User> {
    val root = get("/ajax/friendships/friends", cookie, buildMap { put("uid", id); put("page", "$page"); if (fans) { put("relate", "fans"); put("type", "fans") } })
    val body = root.optJSONObject("data") ?: root
    val source = body.optJSONArray("users") ?: body.optJSONObject("follows")?.optJSONArray("users")
        ?: body.optJSONObject("fans")?.optJSONArray("users") ?: root.optJSONArray("users") ?: throw IOException("关注列表结构不完整")
    val users = source.objects().map(::parseUser).filter { it.id.isNotBlank() }
    return Page(users, if (users.isEmpty()) "0" else "${page + 1}")
}
suspend fun Repository.savedPosts(cookie: String, uid: String, page: Int, likes: Boolean): Page<Post> {
    suspend fun fetch(path: String) = get(path, cookie, mapOf("uid" to uid, "page" to "$page"))
    suspend fun web() = try { fetch(if (likes) "/ajax/statuses/likelist" else "/ajax/favorites/all_fav") }
        catch (e: CancellationException) { throw e }
        catch (e: IOException) {
            if (likes) fetch("/ajax/profile/likelist") else api.get(ApiClient.MOBILE + "/api/favorites/all_fav", cookie, mapOf("page" to "$page"))
        }
    fun parse(root: JSONObject) = responseArray(root, "list", "statuses", "favorites").objects().map {
        val status = it.optJSONObject("status") ?: it
        parsePost(if (likes) status.put("attitudes_status", 1) else status.put("favorited", true))
    }
    val posts = if (likes) {
        if (cookie.isBlank()) throw IOException("读取已赞列表需要网页会话，请导入同一账号的 Cookie")
        parse(web())
    } else accountRead(cookie, "favorites", mapOf("page" to "$page", "count" to "20"), "暂时无法读取收藏",
        web = { web() }, parse = ::parse)
    return Page(posts, if (posts.isEmpty()) "0" else "${page + 1}")
}
suspend fun Repository.reposts(cookie: String, id: String, page: Int): Page<Post> {
    val params = mapOf("id" to numericStatusId(id), "page" to "$page", "count" to "20")
    return accountRead(cookie, "statuses/repost_timeline", params, "暂时无法读取转发记录", publicWeb = true,
        web = { get("/ajax/statuses/repostTimeline", cookie, params + ("id" to id)) }) { root ->
        val posts = responseArray(root, "reposts", "statuses", "data").objects().map(::parsePost)
        val more = if (root.has("max_page")) page < root.optInt("max_page") else posts.size >= 20
        Page(posts, if (posts.isNotEmpty() && more) "${page + 1}" else "0")
    }
}
suspend fun Repository.likers(cookie: String, id: String, page: Int): Page<User> {
    val root = api.get(ApiClient.MOBILE + "/api/attitudes/show", cookie, mapOf("id" to id, "page" to "$page", "count" to "20"))
    val body = root.optJSONObject("data") ?: root
    return Page(responseArray(root, "data").objects().map { parseUser(it.optJSONObject("user") ?: it) }, if (page < body.optInt("max", 1)) "${page + 1}" else "0")
}
data class EditHistoryPage(val revisions: List<Post>, val total: Int?)

suspend fun Repository.editHistory(cookie: String, mid: String, page: Int): EditHistoryPage {
    require(mid.isNotEmpty() && mid.all(Char::isDigit) && page > 0) { "内容标识无效" }
    val root = get("/ajax/statuses/editHistory", cookie, mapOf("mid" to mid, "page" to "$page"))
    val revisions = responseArray(root, "statuses", "list").objects().map { revision ->
        // Revisions belong to the queried post and can carry their own non-status identifiers.
        parsePost(revision.put("mid", mid), depth = 1)
    }
    val total = root.optJSONObject("data")?.optInt("total", -1)?.takeIf { it >= 0 } ?: root.optInt("total", -1)
    return EditHistoryPage(revisions, total.takeIf { it >= 0 })
}
