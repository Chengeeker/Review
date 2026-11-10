package com.review.compose

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Forum
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun MessagesScreen() {
    val model = LocalReview.current; val colors = MaterialTheme.colorScheme
    if (model.uid.isBlank() && !model.demo) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Outlined.MailOutline, null, Modifier.size(60.dp), tint = colors.primary.copy(alpha = .6f))
            Spacer(Modifier.height(16.dp)); Text("登录后即可同步查看您的消息与私信会话", fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.SemiBold))
            Spacer(Modifier.height(16.dp)); Button(onClick = hapticClick { model.navigate("account") }) { Icon(Icons.Outlined.Login, null); Spacer(Modifier.width(8.dp)); Text("立即登录") }
        }
        return
    }
    PagedContent("contacts:${model.uid}:${model.messagesRevision}", { Page(if (model.demo) emptyList() else model.repository.contacts(model.sessionCookie).sortedByDescending { model.bool("pin:${model.uid}:${it.id}") }) }, Contact::id, header = {
        item {
            Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp)) {
                Text("消息通知", Modifier.padding(start = 14.8.dp), style = MaterialTheme.typography.titleMedium, fontWeight = reviewWeight(FontWeight.Bold))
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    MessageShortcut("@我的", "提及我的微博与评论", Icons.Outlined.AlternateEmail, Color(0xFF1E88E5), "mentions", Modifier.weight(1f))
                    MessageShortcut("收到的赞", "收到的点赞记录", Icons.Rounded.Favorite, Color(0xFFE91E63), "likes", Modifier.weight(1f))
                }
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    MessageShortcut("发出的评论", "我发表的评论记录", Icons.Outlined.ChatBubbleOutline, Color(0xFFFFA000), "sentComments", Modifier.weight(1f))
                    MessageShortcut("收到的评论", "与我互动的评论回复", Icons.Rounded.Forum, Color(0xFF10B981), "comments", Modifier.weight(1f))
                }
            }
            Spacer(Modifier.height(20.dp)); ReviewDivider(thickness = .5.dp); Spacer(Modifier.height(12.dp))
            Text("私信与群聊", Modifier.padding(horizontal = 16.dp), style = MaterialTheme.typography.titleMedium, fontWeight = reviewWeight(FontWeight.Bold)); Spacer(Modifier.height(6.dp))
        }
    }, empty = {
        Column(Modifier.fillMaxWidth().padding(vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Outlined.ChatBubbleOutline, null, Modifier.size(48.dp), tint = colors.onSurfaceVariant.copy(alpha = .35f))
            Spacer(Modifier.height(12.dp)); Text("暂无私信会话", fontSize = 14.sp, color = colors.onSurfaceVariant)
        }
    }) { contact ->
        val key = "read:${model.uid}:${contact.id}"; val baseline = model.number(key, 0f).toInt()
        val unread = if (contact.unread < baseline) contact.unread else contact.unread - baseline
        val muted = model.bool("mute:${model.uid}:${contact.id}")
        LaunchedEffect(contact.unread) { if (contact.unread < baseline) model.setOption(key, 0f) }
        Row(Modifier.fillMaxWidth().reviewClickable { model.setOption(key, contact.unread.toFloat()); model.openConversation(contact) }.padding(horizontal = 16.dp, vertical = 4.dp).heightIn(min = 72.dp), verticalAlignment = Alignment.CenterVertically) {
            Box {
                Avatar(contact.name, contact.avatar, Modifier.size(48.dp))
                if (unread > 0) Text(if (unread > 99) "99+" else "$unread", Modifier.align(Alignment.TopEnd).offset(2.dp, (-2).dp).background(if (muted) colors.surfaceContainerHighest else Color(0xFFE53935), RoundedCornerShape(10.dp)).padding(horizontal = 5.dp, vertical = 1.5.dp), fontSize = 10.sp, fontWeight = reviewWeight(FontWeight.Bold), color = if (muted) colors.onSurfaceVariant else Color.White)
            }
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(contact.name, Modifier.weight(1f), fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (contact.time.isNotBlank()) Text(postTime(contact.time, true, false, false, false, false), fontSize = 12.sp, color = colors.outline)
                }
                Text(contact.text, Modifier.padding(top = 4.dp), fontSize = 13.5.sp, lineHeight = 18.9.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, color = colors.onSurfaceVariant)
            }
        }
        ReviewDivider(Modifier.padding(start = 72.dp), thickness = .5.dp)
    }
}

@Composable
private fun MessageShortcut(title: String, subtitle: String, icon: ImageVector, color: Color, kind: String, modifier: Modifier) {
    val model = LocalReview.current; val colors = MaterialTheme.colorScheme
    Surface(modifier.reviewClickable { model.navigate("notificationsList:$kind") }, shape = RoundedCornerShape(14.dp), color = colors.surfaceContainerHighest.copy(alpha = .35f), border = BorderStroke(.8.dp, colors.outlineVariant.copy(alpha = .25f))) {
        Row(Modifier.padding(horizontal = 14.8.dp, vertical = 12.8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(38.dp).background(color.copy(alpha = .12f), RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) { Icon(icon, null, Modifier.size(20.dp), tint = color) }
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(title, fontSize = 14.sp, fontWeight = reviewWeight(FontWeight.Bold))
                Spacer(Modifier.height(2.dp)); Text(subtitle, fontSize = 11.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, color = colors.onSurfaceVariant)
            }
        }
    }
}

@Composable
fun ConversationTitle(route: ReviewRoute) {
    val contact = route.contact
    Row(verticalAlignment = Alignment.CenterVertically) {
        Avatar(contact?.name.orEmpty(), contact?.avatar.orEmpty(), Modifier.size(36.dp), shareWithProfile = contact?.group != true); Spacer(Modifier.width(10.dp))
        Column {
            Text(contact?.name.orEmpty().ifBlank { "聊天" }, fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (contact?.group == true) Text("群聊会话", fontSize = 11.sp, color = MaterialTheme.colorScheme.outline)
        }
    }
}
