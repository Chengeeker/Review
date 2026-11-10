package com.review.compose

import kotlinx.coroutines.CancellationException
import org.json.JSONObject
import java.io.IOException

data class Contact(val id: String, val name: String, val avatar: String, val text: String, val time: String, val group: Boolean, val unread: Int)
data class Message(val id: String, val sender: String, val name: String, val avatar: String, val text: String, val time: String, val raw: String,
    val verified: Boolean = false, val verifiedType: Int = -1, val notice: Boolean = false)

internal data class ChatGroup(val owner: String, val admins: Set<String>, val names: Map<String, String>, val fanLabel: String)

internal fun chatGroup(info: JSONObject): ChatGroup {
    val admins = info.optJSONArray("admins")
    return ChatGroup(
        info.optString("owner"),
        (0 until (admins?.length() ?: 0)).mapNotNull { admins?.optString(it)?.takeIf(String::isNotBlank) }.toSet(),
        info.optJSONArray("nick_infos").objects().mapNotNull { entry ->
            val uid = entry.optString("uid")
            entry.optString("nick").takeIf { uid.isNotBlank() && it.isNotBlank() }?.let { uid to it }
        }.toMap(),
        info.optJSONObject("verify")?.optString("vplususer_name").orEmpty().trim('“', '”').ifBlank { "真爱粉" },
    )
}

internal fun chatMessageText(text: String): String {
    val clean = text.replace("\r\n", "\n").replace('\r', '\n')
    return if (Regex("<[/!]?[A-Za-z][^<>]*>").containsMatchIn(clean)) cleanRichHtml(clean, preserveLineBreaks = true)
    else org.jsoup.parser.Parser.unescapeEntities(clean, false).trim()
}

internal fun isChatNotice(raw: JSONObject, text: String, group: Boolean): Boolean {
    val type = raw.optInt("type")
    val subtype = raw.optInt("sub_type")
    return type == 344 || subtype == 101 || raw.optInt("dm_type") == 9 && subtype == 0 ||
        group && (type != 0 && type != 321 || type == 321 && subtype > 0) ||
        text.endsWith("撤回了一条消息")
}

internal fun chatAvatar(vararg sources: JSONObject?): String = sources.firstNotNullOfOrNull { source ->
    listOf("avatar_large", "round_avatar_large", "avatar_hd", "profile_image_url", "round_avatar", "avatar")
        .firstNotNullOfOrNull { key -> secureImage(source?.optString(key).orEmpty().trim()).takeIf(String::isNotBlank) }
}.orEmpty()

internal suspend fun <T> Repository.accountRead(
    cookie: String, endpoint: String, params: Map<String, String>, unavailable: String,
    publicWeb: Boolean = false,
    web: suspend () -> JSONObject, parse: (JSONObject) -> T
): T {
    val webFailure = if (cookie.isBlank()) null else try { return parse(web()) }
    catch (cancelled: CancellationException) { throw cancelled }
    catch (failure: IOException) { failure }
    try {
        nativeGet(endpoint, params)?.let { return parse(it) }
    } catch (cancelled: CancellationException) { throw cancelled }
    catch (_: Exception) { /* Native transport errors can contain signed request details. */ }
    if (cookie.isBlank() && publicWeb) return parse(web())
    throw webFailure ?: IOException(unavailable)
}

fun parseMessage(o: JSONObject, group: Boolean = false): Message {
    val user = o.optJSONObject("from_user") ?: o.optJSONObject("sender") ?: o.optJSONObject("user") ?: JSONObject()
    val id = listOf("mid", "id", "idstr", "msgid").firstNotNullOfOrNull { o.optString(it).takeIf { value -> value.isNotBlank() && value != "null" } } ?: throw IOException("消息缺少标识")
    val text = o.optString("content").ifBlank { o.optString("text") }.ifBlank { o.optJSONObject("tip")?.optString("content").orEmpty() }
    return Message(id, o.optString("from_uid").ifBlank { o.optString("sender_id").ifBlank { user.optString("idstr").ifBlank { user.optString("id").ifBlank { user.optString("uid") } } } },
        o.optString("sender_screen_name").ifBlank { user.optString("screen_name").ifBlank { user.optString("name") } },
        chatAvatar(user, o),
        chatMessageText(text), o.optString("created_at").ifBlank { o.optString("time") }, o.toString(),
        user.optString("verified") in setOf("1", "true"), user.optInt("verified_type", -1), isChatNotice(o, text, group))
}
suspend fun Repository.contacts(cookie: String): List<Contact> {
    return accountRead(cookie, "direct_messages/user_list", mapOf("count" to "50"), "暂时无法读取私信会话",
        web = { api.get(ApiClient.CHAT + "/webim/2/direct_messages/contacts.json", cookie) }) { root ->
      responseArray(root, "contacts", "user_list").objects().mapNotNull { o ->
        val group = o.optJSONObject("group") ?: o.optJSONObject("group_info")
        val user = o.optJSONObject("user") ?: group ?: o
        val id = user.optString("id").ifBlank { user.optString("idstr").ifBlank { o.optString("id").ifBlank { o.optString("user_id") } } }
        if (id.isBlank()) return@mapNotNull null
        val name = user.optString("name").ifBlank { user.optString("screen_name") }
        val message = o.optJSONObject("message") ?: o.optJSONObject("direct_message") ?: JSONObject()
        Contact(id, name, chatAvatar(user, group, o),
            plainText(message.optString("text").ifBlank { message.optString("content") }), message.optString("created_at"),
            group != null || o.optString("is_group") in setOf("true", "1") || o.optString("isGroup") in setOf("true", "1") || id.length > 12 || name.contains("群") || name.contains("交流"), o.optInt("unread_count").coerceAtLeast(0))
      }
    }
}
suspend fun Repository.conversation(cookie: String, id: String, group: Boolean, before: String = "0"): Page<Message> {
    val params = buildMap {
        put(if (group) "id" else "uid", id); put("count", "40"); put("convert_emoji", "1")
        if (group) { put("query_sender", "1"); put("max_mid", before) } else if (before != "0") put("max_id", before)
    }
    suspend fun web() = api.get(ApiClient.CHAT + if (group) "/webim/groupchat/query_messages.json" else "/webim/2/direct_messages/conversation.json",
        cookie, params + ("source" to "209678993"))
    fun parse(root: JSONObject) = responseArray(root, "messages", "direct_messages").objects().map { parseMessage(it, group) }.distinctBy { it.id }
    val messages = if (group) {
        requireWebChat(cookie)
        parse(web())
    } else accountRead(cookie, "direct_messages/conversation", params, "暂时无法读取私信记录", web = { web() }, parse = ::parse)
    val minimum = messages.mapNotNull { it.id.toBigIntegerOrNull() }.minOrNull()
    return Page(messages.sortedWith(compareByDescending { it.id.toBigIntegerOrNull() }), if (messages.size < 40 || minimum == null || minimum.signum() <= 0) "0" else (minimum - java.math.BigInteger.ONE).toString())
}
suspend fun Repository.sendMessage(cookie: String, id: String, group: Boolean, text: String): String {
    require(text.isNotBlank()) { "消息不能为空" }
    val root = api.post(ApiClient.CHAT + if (group) "/webim/groupchat/send_message.json" else "/webim/2/direct_messages/new.json", cookie, buildMap {
        put("source", "209678993"); put("is_encoded", "0")
        if (group) {
            put("id", id); put("content", text); put("media_type", "0"); put("setTimeout", "50"); put("annotations", "{\"webchat\":1,\"clientid\":\"\"}")
        } else { put("uid", id); put("text", text); put("decodetime", "1"); put("extensions", "{\"clientid\":\"\"}") }
    })
    val message = root.optJSONObject("data") ?: root.optJSONObject("message") ?: root
    return message.optString("mid").ifBlank { message.optString("id") }
}
suspend fun Repository.notifications(cookie: String, kind: String, page: Int): Page<JSONObject> {
    val path = when(kind) { "mentions" -> "/ajax/statuses/mentions"; "mentionComments" -> "/ajax/comments/mentions"; "likes" -> "/ajax/message/attitudes"; "sentComments" -> "/ajax/message/myCmt"; else -> "/ajax/message/cmt" }
    val endpoint = when (kind) {
        "mentions" -> "statuses/mentions"
        "mentionComments" -> "comments/mentions"
        "likes" -> "like/to_me"
        "sentComments" -> "comments/by_me"
        else -> "comments/to_me"
    }
    val params = mapOf("page" to "$page")
    val values = accountRead(cookie, endpoint, params + ("count" to "20"), "暂时无法读取这类消息",
        web = { get(path, cookie, params) }) { responseArray(it, "statuses", "comments", "attitudes", "data").objects() }
    return Page(values, if (values.isEmpty()) "0" else "${page + 1}")
}
suspend fun Repository.unreadMessages(cookie: String, uid: String): JSONObject =
    accountRead(cookie, "remind/unread_count", mapOf("uid" to uid), "暂时无法读取未读消息",
        web = { ApiClient.requireSuccess(api.raw("https://rm.api.weibo.com/2/remind/push_count.json", cookie,
            mapOf("trim_null" to "0", "with_dm_group" to "1", "with_reminding" to "1", "with_settings" to "1",
                "with_chat_group_notice" to "1", "source" to "339644097", "with_chat_group" to "1", "with_dm_unread" to "1"),
            extraHeaders = mapOf("Referer" to "https://weibo.com/")).json()) }) { root ->
        if (unreadCount(root, listOf("mention_status", "all_mention_cmt", "mention_cmt", "mention", "like", "cmt", "dm",
                "mentionStatus", "mentionComment", "mention_comment", "mentions", "at_me", "likes", "attitude", "attitudes",
                "comment", "comments")) == null) throw IOException("未读消息结构不完整")
        root
    }

private fun requireWebChat(cookie: String) {
    if (cookie.isBlank()) throw IOException("群聊需要网页会话，请导入同一账号的 Cookie")
}

internal suspend fun Repository.chatGroupMetadata(cookie: String, id: String): JSONObject {
    requireWebChat(cookie)
    val response = api.get(ApiClient.CHAT + "/webim/groupchat/query.json", cookie, mapOf("id" to id, "source" to "209678993"))
    return response.optJSONObject("data") ?: response
}

suspend fun Repository.groupInfo(cookie: String, id: String): JSONObject {
    val info = chatGroupMetadata(cookie, id)
    try {
        val bulletin = api.get(ApiClient.CHAT + "/webim/groupchat/query_user_bulletin.json", cookie, mapOf("id" to id, "source" to "209678993"))
        if (bulletin.optString("content").isNotBlank()) info.put("bulletin", bulletin)
    } catch (e: CancellationException) { throw e } catch (_: IOException) { }
    return info
}
suspend fun Repository.groupMembers(cookie: String, id: String, cursor: String, count: Int = 500): Page<User> {
    requireWebChat(cookie)
    val root = api.get(ApiClient.CHAT + "/webim/groupchat/query_members.json", cookie, mapOf("id" to id, "source" to "209678993", "count" to "$count", "cursor" to cursor))
    val users = responseArray(root, "members", "users").objects().map(::parseGroupMember).filter { it.id.isNotBlank() }.distinctBy(User::id)
    return Page(users, root.optString("next_cursor", "0"))
}
fun parseGroupMember(item: JSONObject): User {
    val source = item.optJSONObject("user") ?: item
    val normalized = JSONObject(source.toString())
    if (normalized.optString("id").isBlank() && normalized.optString("idstr").isBlank()) normalized.put("id", source.optString("uid"))
    if (normalized.optString("screen_name").isBlank()) normalized.put("screen_name", source.optString("nick").ifBlank { source.optString("name") })
    return parseUser(normalized).copy(avatar = chatAvatar(source, item), joinedAt = item.optLong("time"))
}
suspend fun Repository.chatUser(cookie: String, id: String): User {
    if (cookie.isBlank()) return profile(cookie, id)
    val root = api.get(ApiClient.CHAT + "/webim/2/users/show.json", cookie, mapOf("uid" to id, "source" to "209678993"))
    val data = root.optJSONObject("data") ?: root
    return parseGroupMember(data)
}

suspend fun Repository.exitGroup(cookie: String, id: String) {
    require(id.matches(Regex("[0-9]+"))) { "群号无效" }
    // The official chat endpoint exits membership; deleting chat history is a separate operation.
    api.post(ApiClient.CHAT + "/webim/groupchat/exit.json", cookie, mapOf("id" to id, "keep_entrance" to "0"))
}
