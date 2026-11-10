package com.review.compose

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Diamond
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException

data class FollowedTopic(val id: String, val title: String, val avatar: String, val description: String, val followers: String, val posts: Int)

fun followedTopicsPage(root: JSONObject, page: Int): Page<FollowedTopic> {
    ApiClient.requireSuccess(root)
    val data = root.opt("data")
    val message = listOf(root, data as? JSONObject).filterNotNull().firstNotNullOfOrNull { obj ->
        listOf("msg", "message", "error", "tip", "text").firstNotNullOfOrNull { obj.optString(it).takeIf(String::isNotBlank) }
    }.orEmpty()
    if (Regex("隐私|权限|不可见|未公开|仅自己|禁止|不存在").containsMatchIn(message)) throw IOException("该用户的关注超话可能受隐私设置影响，暂未公开")
    val list = if (data is JSONArray) data else (data as? JSONObject)?.let { obj ->
        listOf("list", "topics", "cards").firstNotNullOfOrNull { key -> when (val value = obj.opt(key)) {
            is JSONArray -> value
            is JSONObject -> JSONArray(value.keys().asSequence().map(value::opt).toList())
            else -> null
        } }
    } ?: throw IOException(message.ifBlank { "服务器未返回关注的超话列表" })
    val topics = list.objects().mapNotNull { item ->
        fun value(vararg keys: String) = keys.firstNotNullOfOrNull { item.optString(it).takeIf(String::isNotBlank) }.orEmpty()
        val title = value("topic_name", "title", "name")
        if (title.isBlank()) null else FollowedTopic(
            value("oid").removePrefix("1022:").ifBlank { Regex("100808[0-9a-zA-Z]+").find(value("link") + " " + value("scheme"))?.value.orEmpty() },
            title, secureImage(value("pic", "avatar", "avatar_large")), plainText(value("content1", "intro", "description")),
            value("content2").ifBlank { value("follow_count").takeIf(String::isNotBlank)?.let { "粉丝：$it" }.orEmpty() }, item.optInt("status_count"))
    }
    val maxPage = (data as? JSONObject)?.let { it.optInt("max_page", it.optInt("maxPage", 1)) } ?: 1
    return Page(topics, if (page < maxPage && list.length() > 0) "${page + 1}" else "0")
}

@Composable
fun FollowedTopicsScreen(uid: String, retained: PagedContentState<FollowedTopic>? = null) {
    val model = LocalReview.current
    PagedContent("followedTopics:$uid", { cursor ->
        val page = cursor.toInt().coerceAtLeast(1)
        val root = model.repository.api.raw(ApiClient.DESKTOP + "/ajax/profile/topicContent", model.sessionCookie,
            mapOf("tabid" to "231093_-_chaohua", "page" to "$page"), extraHeaders = mapOf("Referer" to "https://weibo.com/u/page/follow/$uid/231093_-_chaohua")).json()
        followedTopicsPage(root, page)
    }, { it.id.ifBlank { it.title } }, retained = retained) { item ->
        ReviewListItem(headlineContent = { Text(item.title, fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis) },
            supportingContent = { Column {
                val stats = listOf(item.followers, if (item.posts > 0) "${item.posts} 帖子" else "").filter(String::isNotBlank).joinToString(" · ")
                if (stats.isNotBlank()) Text(stats, fontSize = 12.sp, color = MaterialTheme.colorScheme.primary)
                if (item.description.isNotBlank()) Text(item.description, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            } }, leadingContent = {
                Surface(Modifier.size(48.dp), shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.primaryContainer) {
                    if (item.avatar.isNotBlank()) MediaImage(Media(item.avatar), item.title, Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)))
                    else Icon(Icons.Outlined.Diamond, null, Modifier.padding(12.dp))
                }
            }, modifier = Modifier.reviewClickable {
                model.openTopic(JSONObject().put("page_id", item.id).put("title", item.title).put("pic", item.avatar).put("description", item.description))
            }.padding(vertical = 6.dp))
        ReviewDivider(Modifier.padding(start = 68.dp), thickness = .5.dp)
    }
}
