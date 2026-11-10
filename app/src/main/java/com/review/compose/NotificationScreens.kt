@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun notificationPost(row: JSONObject): Post? {
    val status = listOf("status", "root_status", "rootStatus", "mblog", "weibo")
        .firstNotNullOfOrNull { row.optJSONObject(it) }
    if (status != null) return runCatching { parsePost(status) }.getOrNull()
    val id = listOf("status_id", "statusId", "status_mid", "mblogid", "mblog_id", "weibo_id", "weibo_mid")
        .firstNotNullOfOrNull { row.optString(it).trim().takeIf { value -> value.isNotBlank() && value !in setOf("null", "0", "-1") } } ?: return null
    return Post(id, "", text = "")
}

@Composable
fun NotificationList(kind: String, gallery: (List<Media>, Int) -> Unit) {
    val model = LocalReview.current
    val active = LocalPageActive.current
    LaunchedEffect(kind, model.uid, active) { if (active) model.markInteractionRead(kind) }
    if (model.uid.isBlank() && !model.demo && kind != "mentions") {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Rounded.MarkEmailUnread, null, Modifier.size(60.dp), tint = MaterialTheme.colorScheme.primary.copy(alpha = .6f))
                Spacer(Modifier.height(16.dp)); Text("登录后即可同步查看记录与通知", fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.SemiBold))
                Spacer(Modifier.height(16.dp)); Button(hapticClick { model.navigate("account") }) { Icon(Icons.Rounded.Login, null); Spacer(Modifier.width(8.dp)); Text("立即登录") }
            }
        }
        return
    }
    val modes = if (kind == "mentions") listOf("mentions", "mentionComments") else listOf(kind)
    val states = remember(kind, model.uid) { modes.map { PagedContentState<JSONObject>() } }
    DisposableEffect(states) { onDispose { states.forEach { it.stopObservingPosts?.invoke() } } }
    val pager = rememberPagerState { modes.size }
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize()) {
        if (modes.size > 1) PrimaryTabRow(pager.currentPage, containerColor = Color.Transparent) {
            listOf("@我的微博", "@我的评论").forEachIndexed { index, title ->
                Tab(pager.currentPage == index, hapticClick { scope.launch { pager.animateScrollToPage(index) } },
                    Modifier.height(48.dp), unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant, text = { Text(title, fontSize = 14.5.sp, fontWeight = reviewWeight(FontWeight.Bold)) })
            }
        }
        HorizontalPager(pager, Modifier.weight(1f), userScrollEnabled = modes.size > 1) { index ->
            val mode = modes[index]
            val data = states[index]
            PagedContent("notifications:$mode:${model.uid}", { model.repository.notifications(model.sessionCookie, mode, it.toInt().coerceAtLeast(1)) },
                { it.optString("idstr").ifBlank { it.optString("id").ifBlank { it.toString().hashCode().toString() } } },
                retained = data, showLoadMore = false,
                contentPadding = PaddingValues(top = if (modes.size > 1) 0.dp else LocalContentTop.current),
                loading = { Box(Modifier.fillMaxWidth().then(if (data.rows.value.isEmpty()) Modifier.fillParentMaxHeight() else Modifier.height(64.dp)), contentAlignment = Alignment.Center) { CircularProgressIndicator() } },
                empty = {
                    Box(Modifier.fillParentMaxHeight().fillMaxWidth(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(when (mode) { "likes" -> Icons.Rounded.Favorite; "mentions" -> Icons.Rounded.AlternateEmail; else -> Icons.Rounded.ChatBubbleOutline }, null,
                                Modifier.size(54.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .4f))
                            Spacer(Modifier.height(12.dp))
                            Text(when (mode) { "likes" -> "暂无收到的赞"; "sentComments" -> "暂无发出的评论"; "mentions" -> "暂无@你的微博"; "mentionComments" -> "暂无@你的评论"; else -> "暂无收到的评论" }, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }, body = { rows ->
                    itemsIndexed(rows, key = { _, row -> row.optString("idstr").ifBlank { row.optString("id").ifBlank { row.toString().hashCode().toString() } } }) { position, row ->
                        if (position > 0 && mode != "mentions") ReviewDivider(Modifier.padding(start = 64.dp), .5.dp)
                        if (mode == "mentions") PostRow(parsePost(row), gallery)
                        else NotificationRow(row, mode) { removed -> data.rows.value = data.rows.value.filterNot { it === removed } }
                    }
                }) {}
        }
    }
}

@Composable
internal fun NotificationRow(row: JSONObject, mode: String, removed: (JSONObject) -> Unit = {}) {
    val model = LocalReview.current
    val colors = MaterialTheme.colorScheme
    val user = remember(row) { parseUser(row.optJSONObject("user") ?: JSONObject()) }
    val post = remember(row) { notificationPost(row) }
    val comment = remember(row) { runCatching { parseComment(row) }.getOrNull() }
    val like = mode == "likes"
    var confirm by remember(row) { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().reviewClickable {
        if (post != null) { if (!like && mode != "mentionComments" && comment != null) model.openComment(post, comment) else model.openPost(post) }
    }.padding(horizontal = 16.dp, vertical = 11.dp), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Avatar(user.name, user.avatar, Modifier.size(40.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(user.name.ifBlank { "微博用户" }, Modifier.weight(1f, fill = false), fontSize = 14.sp, lineHeight = 18.9.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (like) {
                    Spacer(Modifier.width(6.dp)); Icon(Icons.Rounded.Favorite, null, Modifier.size(14.dp), tint = Color(0xFFEF5350)); Spacer(Modifier.width(4.dp))
                    Text(if (row.optJSONObject("comment") != null) "赞了你的评论" else "赞了你的微博", fontSize = 12.5.sp, lineHeight = 16.875.sp, fontWeight = reviewWeight(FontWeight.Medium), color = colors.onSurfaceVariant)
                } else if (mode != "mentionComments") {
                    val fans = remember(row) { secureImage(row.optJSONObject("user")?.optJSONObject("fansIcon")?.optString("icon_url").orEmpty().ifBlank { row.optJSONObject("user")?.optJSONObject("fans_icon")?.optString("icon_url").orEmpty() }) }
                    if (fans.isNotBlank()) { Spacer(Modifier.width(4.dp)); SubcomposeAsyncImage(fans, "微博铁粉等级标识", Modifier.height(14.dp), loading = {}, error = {}) }
                }
            }
            if (row.optString("created_at").isNotBlank()) {
                Spacer(Modifier.height(2.dp)); Text(postTime(row.optString("created_at"), true, false, false, false, false), fontSize = 12.sp, lineHeight = 16.8.sp, color = colors.outline)
            }
            Spacer(Modifier.height(if (like) 6.dp else 4.dp))
            if (like) {
                val quoted = row.optJSONObject("comment") ?: row.optJSONObject("status")
                if (quoted != null) Text(quoted.optString("text_raw").ifBlank { quoted.optString("text") },
                    Modifier.fillMaxWidth().background(colors.surfaceContainerHighest.copy(alpha = .45f), RoundedCornerShape(8.dp))
                        .border(.8.dp, colors.outlineVariant.copy(alpha = .2f), RoundedCornerShape(8.dp)).padding(horizontal = 10.dp, vertical = 8.dp),
                    fontSize = 13.sp, lineHeight = 16.9.sp, color = colors.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
            } else {
                RichText(cleanRichHtml(row.optString("text_raw").ifBlank { row.optString("text") }), style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp, lineHeight = 19.6.sp, color = colors.onSurface))
                if (mode != "mentionComments") {
                    val reply = row.optJSONObject("reply_comment") ?: row.optJSONObject("replyComment")
                    if (reply != null) {
                        Spacer(Modifier.height(6.dp)); Text("回复 @${reply.optJSONObject("user")?.optString("screen_name").orEmpty()}：${reply.optString("text_raw").ifBlank { reply.optString("text") }}",
                            Modifier.background(colors.surfaceContainerHighest.copy(alpha = .5f), RoundedCornerShape(6.dp)).padding(horizontal = 8.dp, vertical = 6.dp),
                            fontSize = 12.5.sp, lineHeight = 17.5.sp, color = colors.outline, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                    if (post != null) {
                        Spacer(Modifier.height(6.dp)); Text("原微博：${post.text}", Modifier.background(colors.surfaceContainerHighest.copy(alpha = .3f), RoundedCornerShape(6.dp)).padding(horizontal = 8.dp, vertical = 6.dp),
                            fontSize = 12.sp, lineHeight = 16.8.sp, color = colors.outline, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
        if (mode == "sentComments") OutlinedButton(hapticClick { confirm = true }, enabled = comment != null && !model.actionBusy,
            modifier = Modifier.heightIn(min = 48.dp), contentPadding = PaddingValues(horizontal = 10.dp),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = colors.primary), border = androidx.compose.foundation.BorderStroke(1.dp, colors.outline)) {
            Icon(Icons.Rounded.DeleteOutline, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("删除")
        }
    }
    if (confirm && comment != null) ReviewAlertDialog({ confirm = false }, title = { Text("删除评论") }, text = { Text("确定要删除这条评论吗？删除后不可恢复。") },
        confirmButton = { Button(hapticClick { confirm = false; model.mutate { model.repository.deleteComment(model.sessionCookie, comment.id); removed(row); model.notice = "评论已删除" } }) { Text("删除") } },
        dismissButton = { TextButton(hapticClick { confirm = false }) { Text("取消") } })
}
