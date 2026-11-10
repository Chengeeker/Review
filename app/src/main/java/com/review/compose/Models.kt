package com.review.compose

import android.text.Html
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI

data class Media(val url: String = "", val artwork: Int = 0, val video: String = "", val live: Boolean = false,
    val width: Int = 0, val height: Int = 0, val title: String = "", val qualities: Map<String, String> = emptyMap(),
    val article: String = "", val background: String = "", val card: Boolean = false,
    val duration: String = "", val long: Boolean = false, val gif: Boolean = false, val preview: String = "",
    val videoId: String = "", val thumbnailAspect: Float = 0f, val cardLink: String = "")
data class Post(
    val id: String, val author: String, val uid: String = "", val avatar: String = "",
    val text: String, val time: String = "", val source: String = "",
    val images: List<Media> = emptyList(), val repost: Post? = null,
    val comments: Int = 0, val likes: Int = 0, val shares: Int = 0,
    val demo: Boolean = false, val longText: Boolean = false,
    val raw: String = "",
) {
    val data by lazy(LazyThreadSafetyMode.NONE) { runCatching { JSONObject(raw) }.getOrDefault(JSONObject()) }
    val liked get() = data.optBoolean("favorited_attitude") || data.optBoolean("liked") || data.optInt("attitudes_status") == 1
    val favorited get() = data.optBoolean("favorited")
    fun snapshot(): JSONObject = JSONObject().apply {
        put("id", id); put("author", author); put("uid", uid); put("avatar", avatar)
        put("text", text); put("time", time); put("source", source)
        put("comments", comments); put("likes", likes); put("shares", shares)
        put("demo", demo); put("longText", longText)
        put("raw", raw)
        put("images", JSONArray(images.map { JSONObject().put("url", it.url).put("artwork", it.artwork).put("video", it.video).put("live", it.live)
            .put("width", it.width).put("height", it.height).put("title", it.title).put("qualities", JSONObject(it.qualities)).put("article", it.article).put("background", it.background).put("card", it.card).put("duration", it.duration).put("long", it.long).put("gif", it.gif).put("preview", it.preview).put("videoId", it.videoId).put("thumbnailAspect", it.thumbnailAspect)
            .put("cardLink", it.cardLink) }))
        repost?.let { put("repost", it.snapshot()) }
    }
    companion object {
        fun restore(o: JSONObject): Post {
            val storedImages = o.optJSONArray("images").objects()
            val legacy = if (storedImages.any { !it.has("thumbnailAspect") } && o.optString("raw").isNotBlank())
                runCatching { parsePost(JSONObject(o.getString("raw"))).images.associateBy(Media::url) }.getOrDefault(emptyMap()) else emptyMap()
            return Post(
            id = o.getString("id"), author = o.getString("author"), uid = o.optString("uid"),
            avatar = o.optString("avatar"), text = o.getString("text"), time = o.optString("time"),
            source = o.optString("source"), images = storedImages.map {
                val qualities = it.optJSONObject("qualities") ?: JSONObject()
                Media(it.optString("url"), it.optInt("artwork"), it.optString("video"), it.optBoolean("live"), it.optInt("width"), it.optInt("height"), it.optString("title"), qualities.keys().asSequence().associateWith(qualities::getString), it.optString("article"), it.optString("background"), it.optBoolean("card"), it.optString("duration"), it.optBoolean("long"), it.optBoolean("gif"), it.optString("preview"), it.optString("videoId"), it.optDouble("thumbnailAspect", legacy[it.optString("url")]?.thumbnailAspect?.toDouble() ?: 0.0).toFloat().let { value -> if (value.isFinite() && value in .5f..2f) value else 0f }, it.optString("cardLink"))
            }, repost = o.optJSONObject("repost")?.let(::restore), comments = o.optInt("comments"),
            likes = o.optInt("likes"), shares = o.optInt("shares"), demo = o.optBoolean("demo"),
            longText = o.optBoolean("longText"),
            raw = o.optString("raw"),
        )
        }
    }
}
data class Trend(val word: String, val heat: String, val label: String = "", val pinned: Boolean = false, val rank: Int = 0, val ranked: Boolean = true, val location: String = "", val category: String = "")
fun Post.withInteraction(kind: String, enabled: Boolean): Post {
    require(kind == "like" || kind == "favorite")
    val count = if (kind == "like" && liked != enabled) (likes + if (enabled) 1 else -1).coerceAtLeast(0) else likes
    val changed = JSONObject(data.toString()).put(if (kind == "like") "liked" else "favorited", enabled)
    if (kind == "like") changed.put("attitudes_status", if (enabled) 1 else 0).put("attitudes_count", count)
    return copy(raw = changed.toString(), likes = count)
}
fun parseTrend(o: JSONObject, index: Int, pinned: Boolean = false): Trend {
    fun first(vararg keys: String) = keys.firstNotNullOfOrNull { o.optString(it).takeIf(String::isNotBlank) }.orEmpty()
    val ranked = o.optInt("realpos") > 0
    val heat = first("num", "raw_hot").ifBlank { (o.opt("description") as? Number)?.toString().orEmpty() }
    return Trend(first("word", "note"), heat, first("label_name", "icon_desc", "small_icon_desc", "flag_desc"), pinned || o.optInt("is_gov") == 1 || o.optInt("is_pinned") == 1,
        o.optInt("realpos", o.optInt("rank", index + 1)), ranked, if (ranked) "" else (o.opt("description") as? String).orEmpty(), first("m_category", "category", "channel_type"))
}
data class Comment(val id: String, val author: String, val text: String, val avatar: String = "", val likes: Int = 0,
    val uid: String = "", val replies: Int = 0, val images: List<Media> = emptyList(), val liked: Boolean = false,
    val children: List<Comment> = emptyList(), val replyCountKnown: Boolean = false, val time: String = "", val source: String = "", val raw: String = "")
fun commentImageIdentity(url: String) = url.substringBefore('?').replace(Regex("/(thumbnail|bmiddle|orj960|large|mw2000|original)/"), "/")
fun parseComment(o: JSONObject, inherited: Set<String> = emptySet(), depth: Int = 0): Comment {
    val user = o.optJSONObject("user") ?: JSONObject()
    val pictures = mutableListOf<Media>()
    fun add(value: Any?) {
        val info = value as? JSONObject
        val url = secureImage(if (info == null) (value as? String).orEmpty() else listOf("largest", "original", "large", "bmiddle").firstNotNullOfOrNull { info.optJSONObject(it)?.optString("url")?.takeIf(String::isNotBlank) } ?: info.optString("url"))
        val identity = commentImageIdentity(url)
        if (url.isBlank() || identity in inherited || pictures.any { commentImageIdentity(it.url) == identity }) return
        val uri = runCatching { java.net.URI(url) }.getOrNull() ?: return
        if (!(uri.host.endsWith(".sinaimg.cn") || Regex("\\.(jpg|jpeg|png|gif|webp|bmp|heic)([?#]|$)", RegexOption.IGNORE_CASE).containsMatchIn(url))) return
        pictures += pictureMedia(info ?: JSONObject(), url)
    }
    add(o.opt("pic")); o.optJSONArray("pics").objects().forEach(::add)
    o.optJSONObject("pic_infos")?.let { infos -> infos.keys().forEach { add(infos.opt(it)) } }
    o.optJSONArray("url_struct").objects().forEach { link -> add(link.opt("pic_info")); link.optJSONArray("pic_infos").objects().forEach(::add) }
    val childInherited = inherited + pictures.map { commentImageIdentity(it.url) }
    val children = if (depth >= 8) emptyList() else o.optJSONArray("comments").objects().map { parseComment(it, childInherited, depth + 1) }
    val count = listOf("total_number", "comments_count", "comment_count").firstNotNullOfOrNull { if (o.has(it)) o.optInt(it) else null }
    val id = listOf("idstr", "id", "cid", "cidstr", "comment_id", "comment_idstr", "commentId", "commentIdStr", "mid")
        .firstNotNullOfOrNull { key -> o.optString(key).trim().takeIf { it.isNotBlank() && it !in setOf("null", "0", "-1") } }
        ?: throw IllegalArgumentException("评论缺少标识")
    return Comment(id, user.optString("screen_name"), cleanRichHtml(o.optString("text_raw").ifBlank { o.optString("text") }),
        secureImage(user.optString("profile_image_url")), o.optInt("like_counts", o.optInt("like_count")), user.optString("idstr").ifBlank { user.optString("id") }, count ?: children.size, pictures, o.optBoolean("liked"), children, count != null, o.optString("created_at"), plainText(o.optString("source")), o.toString())
}
data class User(val id: String, val name: String, val avatar: String, val description: String = "", val following: Boolean = false,
    val followers: String = "", val friends: String = "", val posts: String = "", val verified: String = "",
    val gender: String = "", val ip: String = "", val followMe: Boolean = false, val isVerified: Boolean = false, val verifiedType: Int = -1, val joinedAt: Long = 0)
fun parseUser(o: JSONObject) = User(o.optString("idstr").ifBlank { o.optString("id").ifBlank { o.optString("uid") } },
    o.optString("screen_name").ifBlank { o.optString("name").ifBlank { o.optString("nick") } },
    secureImage(o.optString("avatar_hd").ifBlank { o.optString("avatar_large").ifBlank { o.optString("profile_image_url") } }),
    plainText(o.optString("description")), o.optBoolean("following"), o.optString("followers_count").toIntOrNull()?.let(::compactCount) ?: o.optString("followers_count_str").ifBlank { o.optString("followers_count") },
    o.optString("friends_count"), o.optString("statuses_count"), o.optString("verified_reason"), o.optString("gender"), o.optString("ip_location").removePrefix("IP属地：").removePrefix("IP属地:"), o.optBoolean("follow_me"), o.optBoolean("verified"), o.optInt("verified_type", -1))
data class Page<T>(val items: List<T>, val next: String = "0")
data class FeedGroup(val id: String, val title: String, val section: String = "")

fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList()
    else (0 until length()).mapNotNull { optJSONObject(it) }
fun plainText(value: String): String = Html.fromHtml(value, Html.FROM_HTML_MODE_LEGACY).toString().trim()
fun secureImage(value: String): String {
    val candidate = if (value.startsWith("//")) "https:$value" else value.replaceFirst(Regex("^http://"), "https://")
    return runCatching { URI(candidate) }.getOrNull()
        ?.takeIf { it.scheme == "https" && !it.host.isNullOrBlank() && it.userInfo == null }?.toString().orEmpty()
}
fun compactCount(count: Int): String = if (count >= 10000) String.format(java.util.Locale.ROOT, "%.1f万", count / 10000.0)
    else count.coerceAtLeast(0).toString()
fun compactCount(count: String): String = count.toIntOrNull()?.let(::compactCount)
    ?: count.replace(Regex("^([0-9]+)([万亿])$"), "\$1.0\$2")
fun mergePosts(old: List<Post>, fresh: List<Post>): List<Post> = (old + fresh).distinctBy { it.id }
fun canContinuePage(previous: String, next: String, addedContent: Boolean): Boolean =
    addedContent && next.isNotBlank() && next != "0" && next != "-1" && next != "null" && next != previous

fun authenticatedUid(root: JSONObject, requireLoginFlag: Boolean = false): String? {
    if (root.optInt("ok", 1) < 0 || root.optString("url").contains("login", ignoreCase = true)) return null
    val data = root.optJSONObject("data") ?: root
    val user = data.optJSONObject("user") ?: root.optJSONObject("user")
    val flags = listOf(data, root).flatMap { obj -> listOf("islogin", "login", "isNormal").filter(obj::has).map { obj.opt(it).toString() } }
    val loggedIn = if (flags.isEmpty()) !requireLoginFlag && user != null else flags.any {
        when (it.trim().lowercase()) {
            "true", "1", "yes" -> true
            else -> false
        }
    }
    if (!loggedIn) return null
    return listOf(data.optString("uid"), data.optString("id"), data.optString("idstr"),
        user?.optString("id").orEmpty(), user?.optString("idstr").orEmpty(), user?.optString("uid").orEmpty(), root.optString("uid"))
        .firstOrNull { it.matches(Regex("[1-9][0-9]*")) }
}

fun parsePost(o: JSONObject, depth: Int = 0): Post {
    val links = normalizedLinks(o)
    if (links.isNotEmpty()) o.put("url_struct", JSONArray(links))
    val user = o.optJSONObject("user") ?: JSONObject()
    val infos = o.optJSONObject("pic_infos")
    val ids = o.optJSONArray("pic_ids") ?: infos?.let { JSONArray(it.keys().asSequence().toList()) }
    val images = if (ids != null) (0 until ids.length()).mapNotNull { index ->
        val id = ids.optString(index)
        val info = infos?.optJSONObject(id)
        val url = info?.optJSONObject("largest")?.optString("url")
            ?: info?.optJSONObject("original")?.optString("url")
            ?: info?.optJSONObject("bmiddle")?.optString("url")
            ?: if (id.matches(Regex("[a-zA-Z0-9]+"))) "https://wx1.sinaimg.cn/large/$id.jpg" else ""
        secureImage(url).takeIf { it.isNotEmpty() }?.let { pictureMedia(info ?: JSONObject(), it) }
    } else o.optJSONArray("pics").objects().mapNotNull {
        secureImage(it.optJSONObject("large")?.optString("url") ?: it.optString("url"))
            .takeIf(String::isNotEmpty)?.let { url -> pictureMedia(it, url) }
    }
    val media = mutableListOf<Media>()
    o.optJSONObject("mix_media_info")?.optJSONArray("items").objects().forEach { item ->
        val info = item.optJSONObject("data") ?: return@forEach
        if (item.optString("type") == "video") videoMedia(info)?.let(media::mergeVideo)
        else if (item.optString("type") == "pic") {
            val pic = info.optJSONObject("pic_info") ?: info
            val url = listOf("largest", "original", "large", "pic_big", "bmiddle").firstNotNullOfOrNull { pic.optJSONObject(it)?.optString("url")?.takeIf(String::isNotBlank) }.orEmpty()
            if (secureImage(url).isNotBlank()) media += pictureMedia(pic, secureImage(url))
        }
    }
    media += images.filterNot { image -> media.any { it.url == image.url } }
    if (!o.has("retweeted_status") && media.none { it.video.isNotBlank() && !it.live }) o.optJSONObject("page_info")?.let(::videoMedia)?.let { media += it }
    links.filter { !o.has("retweeted_status") || statusReferencesLink(o, it) }
        .mapNotNull(::linkedVideo).forEach(media::mergeVideo)
    for (image in embeddedMedia(o)) {
        val existing = media.indexOfFirst { it.video.isBlank() && commentImageIdentity(it.url) == commentImageIdentity(image.url) }
        if (existing < 0) media += image else media[existing] = if (image.card) image else image.copy(url = media[existing].url)
    }
    var text = o.optString("text_raw").ifEmpty { cleanRichHtml(o.optString("text")) }
    for (link in links) {
        val pictures = linkedPictures(link)
        if (pictures.isNotEmpty() && pictures.all { image -> media.any { commentImageIdentity(it.url) == commentImageIdentity(image.url) } }) {
            val short = link.optString("short_url").ifBlank { link.optString("url_ori") }
            if (short.startsWith("http://") || short.startsWith("https://")) text = text.replace(attachmentLinkPattern(short), "").trim()
        }
    }
    return Post(
        id = numericStatusId(o.optString("mid").ifBlank { o.optString("idstr").ifBlank { o.optString("id").ifBlank { o.optString("mblogid") } } }).also { require(it.isNotEmpty()) { "内容缺少标识" } },
        author = user.optString("screen_name", "未知用户"), uid = user.optString("idstr").ifEmpty { user.optString("id") },
        avatar = secureImage(user.optString("avatar_large").ifEmpty { user.optString("profile_image_url") }),
        text = text.withoutWebCardLinks(media),
        time = o.optString("created_at"), source = plainText(o.optString("source")), images = media,
        repost = if (depth < 1) o.optJSONObject("retweeted_status")?.let { parsePost(it, depth + 1) } else null,
        comments = o.optInt("comments_count"), likes = o.optInt("attitudes_count"), shares = o.optInt("reposts_count"),
        longText = o.optBoolean("isLongText") || o.optBoolean("is_long_text"),
        raw = o.toString(),
    )
}

object PreviewContent {
    val posts = listOf(
        Post("demo-1", "山间来信", text = "把周末留给山野。\n\n走过薄雾、松林和一段没有信号的路，才发现，慢一点也能看到很多。", time = "12 分钟前", source = "生活记录", images = listOf(Media(artwork = 1), Media(artwork = 2), Media(artwork = 3)), comments = 24, likes = 128, shares = 6, demo = true),
        Post("demo-2", "小林的设计手记", text = "好的阅读体验，应该让界面安静下来。\n\n恰好的留白，清晰的层次，还有每一次恰到好处的反馈。比起堆叠装饰，我更喜欢把注意力还给内容本身。", time = "38 分钟前", source = "设计与日常", comments = 16, likes = 86, shares = 12, demo = true),
        Post("demo-3", "城市漫游者", text = "傍晚六点，整座城市变成了暖色。\n#下班后的风景#", time = "1 小时前", source = "摄影日记", images = listOf(Media(artwork = 4)), comments = 32, likes = 206, shares = 9, demo = true),
        Post("demo-4", "一页书", text = "今天读到的一句话，分享给路过的人。", time = "2 小时前", repost = Post("demo-quote", "纸上远行", text = "生活并不总需要赶路。有时停下来读一页书，就已经去过很远的地方。", demo = true), comments = 7, likes = 42, demo = true),
        Post("demo-5", "慢慢咖啡", text = "雨天、窗边和一杯刚冲好的咖啡。\n今日的小小幸福已经收集完成。", time = "3 小时前", images = listOf(Media(artwork = 5), Media(artwork = 6)), comments = 9, likes = 63, demo = true),
    )
    val trends = listOf(
        Trend("秋天适合去哪里散步", "86.2万", "热"), Trend("那些让人安静下来的瞬间", "62.8万", "新"),
        Trend("原来设计可以这么简单", "54.1万"), Trend("把日常拍成电影", "43.6万"),
        Trend("你最近读完的一本书", "38.2万"), Trend("周末的100种打开方式", "29.5万"),
        Trend("城市里的自然观察", "24.9万"), Trend("给生活留一点空白", "18.6万"),
        Trend("窗外的云又换了形状", "12.4万"), Trend("今天也有好好吃饭", "9.8万"),
    )
    val comments = listOf(
        Comment("c1", "风经过的地方", "看着这些颜色，整个人都放松下来了。", likes = 18),
        Comment("c2", "周末计划", "已经开始期待下一次出发了！", likes = 9),
        Comment("c3", "日常观察员", "慢一点，才能看见路上的风景。", likes = 6),
    )
}
