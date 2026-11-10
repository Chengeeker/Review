package com.review.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import org.json.JSONObject

internal fun drawerUnreadTotal(reminder: JSONObject, directMessages: Int): Int {
    return (interactionCounts(reminder).values.sumOf { it.toLong() } + directMessages.coerceAtLeast(0))
        .coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
}

@Composable
fun ReviewDrawerContent(open: Boolean, navigate: (String) -> Unit) {
    val model = LocalReview.current
    val colors = MaterialTheme.colorScheme
    val nickname = model.me?.name?.takeIf(String::isNotBlank) ?: if (model.uid.isBlank()) "未登录 / 访客" else "已登录用户"
    var interactionRaw by remember(model.uid) { mutableStateOf(emptyMap<String, Int>()) }
    var directUnread by remember(model.uid) { mutableIntStateOf(0) }
    val interactionUnread = interactionRaw.entries.sumOf { (kind, raw) ->
        unreadAfterRead(raw, model.number("read-interaction:${model.uid}:$kind", 0f).toInt()).toLong()
    }
    val unread = (interactionUnread + directUnread).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    LaunchedEffect(open, model.uid, model.messagesRevision, lifecycle) {
        if (!open || model.uid.isBlank() || model.demo || !lifecycle.isAtLeast(Lifecycle.State.STARTED)) return@LaunchedEffect
        while (true) {
            try {
                coroutineScope {
                    val uid = model.uid
                    val cookie = model.sessionCookie
                    val reminder = async { messagePoll { model.repository.unreadMessages(cookie, uid) } }
                    val contacts = async { messagePoll { model.repository.contacts(cookie) } }
                    if (model.uid != uid) return@coroutineScope
                    contacts.await()?.takeIf { model.uid == uid }?.let { rows ->
                      directUnread = rows.filterNot { model.bool("mute:$uid:${it.id}") }.sumOf {
                        val baseline = model.number("read:$uid:${it.id}", 0f).toInt()
                        if (it.unread < baseline) { model.setOption("read:$uid:${it.id}", 0f); it.unread.coerceAtLeast(0).toLong() }
                        else (it.unread - baseline).coerceAtLeast(0).toLong()
                      }.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
                    }
                    reminder.await()?.takeIf { model.uid == uid }?.let { response ->
                        val counts = interactionCounts(response)
                        for ((kind, raw) in counts) {
                            val key = "read-interaction:$uid:$kind"
                            if (raw < model.number(key, 0f)) model.setOption(key, 0f)
                        }
                        interactionRaw = interactionRaw + counts
                    }
                }
            } catch (e: CancellationException) { throw e } catch (_: Exception) { }
            delay(60000)
        }
    }
    Column(Modifier.fillMaxHeight()) {
        Column(Modifier.padding(start = 20.dp, top = 20.dp, end = 16.dp, bottom = 12.dp)) {
            val profile = { navigate(if (model.uid.isBlank()) "account" else "profile:${model.uid}"); if (model.uid.isNotBlank()) model.routeStack.last().profilePreview = model.me }
            Avatar(nickname, model.me?.avatar.orEmpty(), Modifier.size(64.dp).reviewClickable(onClick = profile), shareWithProfile = true)
            Spacer(Modifier.height(14.dp))
            Text(nickname, Modifier.reviewClickable(onClick = profile).padding(horizontal = 2.dp, vertical = 4.dp), fontSize = 16.5.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Box(Modifier.height(1.dp), contentAlignment = Alignment.Center) { ReviewDivider(thickness = .5.dp) }
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(vertical = 6.dp)) {
            listOf(Triple("赞和收藏", "favorites", Icons.Rounded.Favorite), Triple("我的分组", "groups", Icons.Rounded.Group),
                Triple("关注列表", "relations:${model.uid}:false", Icons.Rounded.PeopleAlt), Triple("我的消息", "messages", Icons.Rounded.MailOutline),
                Triple("超话中心", "topics", Icons.Rounded.Diamond), Triple("浏览记录", "history", Icons.Rounded.History)).forEach { (title, route, icon) ->
                item(route) {
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).reviewClickable { navigate(route) }.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(icon, null, Modifier.size(22.dp), tint = colors.onSurfaceVariant)
                        Spacer(Modifier.width(14.dp))
                        Text(title, Modifier.weight(1f), fontSize = 15.sp, fontWeight = FontWeight.Medium)
                        if (route == "messages" && unread > 0) Box(Modifier.defaultMinSize(minWidth = 22.dp, minHeight = 22.dp).background(Color(0xFFE53935), RoundedCornerShape(12.dp)).padding(horizontal = 6.dp, vertical = 2.dp), contentAlignment = Alignment.Center) { Text(if (unread > 99) "99+" else "$unread", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold) }
                    }
                }
            }
        }
    }
}
