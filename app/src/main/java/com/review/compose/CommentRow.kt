@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package com.review.compose

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Reply
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage
import org.json.JSONObject

@Composable
fun CommentRow(post: Post, comment: Comment, gallery: (List<Media>, Int) -> Unit, reply: (Comment) -> Unit, thread: () -> Unit, refresh: () -> Unit, inThread: Boolean = false) {
    val model = LocalReview.current
    val colors = MaterialTheme.colorScheme
    val context = LocalContext.current
    var menu by remember(comment.id) { mutableStateOf<Comment?>(null) }
    var deletion by remember(comment.id) { mutableStateOf<Comment?>(null) }
    val user = remember(comment.raw) { runCatching { parseUser(JSONObject(comment.raw).optJSONObject("user") ?: JSONObject()) }.getOrNull() }
    Row(Modifier.fillMaxWidth().combinedClickable(hapticFeedbackEnabled = false, onClick = hapticClick { menu = comment }, onLongClick = hapticClick { menu = comment }).padding(horizontal = 16.dp, vertical = if (inThread) 12.dp else 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(48.dp).reviewClickable(onClickLabel = "${comment.author}的头像") { model.openProfile(comment) }, contentAlignment = Alignment.Center) {
            Avatar(comment.author, comment.avatar, Modifier.size(if (inThread) 40.dp else 36.dp), verified = user?.isVerified == true, verifiedType = user?.verifiedType ?: -1, shareWithProfile = true, crossfade = false)
        }
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CommentName(post, comment, Modifier.weight(1f), inThread = inThread)
                if (inThread) Spacer(Modifier.width(8.dp))
                Box(Modifier.width(66.dp), contentAlignment = Alignment.TopEnd) {
                    Row(Modifier.clip(RoundedCornerShape(12.dp)).reviewClickable(enabled = !model.actionBusy, onClickLabel = "赞评论") {
                        model.mutate { model.repository.interact(model.sessionCookie, "commentLike", comment.id, !comment.liked); refresh() }
                    }.padding(horizontal = 4.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                        val tint = if (comment.liked) Color(0xFFEC407A) else colors.onSurfaceVariant
                        if (comment.likes > 0) { Text("${comment.likes}", fontSize = 12.sp, color = tint); Spacer(Modifier.width(4.dp)) }
                        Icon(if (comment.liked) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder, "赞评论", Modifier.size(16.dp), tint = tint)
                    }
                }
            }
            Spacer(Modifier.height(2.dp))
            val time = postTime(comment.time, model.option("timeMode", "relative") == "relative", model.bool("weekday"), model.bool("year"), model.bool("timezone"), model.bool("seconds"))
            Text(listOf(time, comment.source.trim().let { if (it.isBlank() || it.startsWith("来自")) it else "来自 $it" }).filter(String::isNotBlank).joinToString("  "), fontSize = if (inThread) 12.sp else 11.5.sp, color = colors.onSurfaceVariant)
            Spacer(Modifier.height(if (inThread) 7.dp else 6.dp))
            if (comment.text.isNotBlank()) { RichText(comment.text, Post(comment.id, comment.author, text = comment.text, raw = comment.raw), style = MaterialTheme.typography.bodyMedium.copy(fontSize = if (inThread) 15.sp else 14.sp, lineHeight = if (inThread) 21.sp else 19.6.sp), modifier = Modifier.combinedClickable(hapticFeedbackEnabled = false, onClick = hapticClick { menu = comment }, onLongClick = hapticClick { menu = comment })); if (!inThread || comment.images.isNotEmpty()) Spacer(Modifier.height(6.dp)) }
            if (comment.images.isNotEmpty()) { CommentPictures(comment, gallery, inThread); if (!inThread) Spacer(Modifier.height(6.dp)) }
            if (!inThread && (comment.children.isNotEmpty() || comment.replies > 0)) {
                Spacer(Modifier.height(8.dp))
                if (comment.children.isNotEmpty()) Column(Modifier.fillMaxWidth().background(colors.surfaceContainerHighest.copy(alpha = .4f), RoundedCornerShape(8.dp)).padding(8.dp)) {
                    comment.children.forEach { child ->
                        val childUser = remember(child.raw) { runCatching { parseUser(JSONObject(child.raw).optJSONObject("user") ?: JSONObject()) }.getOrNull() }
                        Row(Modifier.fillMaxWidth().combinedClickable(hapticFeedbackEnabled = false, onClick = hapticClick { menu = child }, onLongClick = hapticClick { menu = child }).padding(vertical = 3.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Box(Modifier.size(48.dp).reviewClickable(onClickLabel = "${child.author}的头像") { model.openProfile(child) }, contentAlignment = Alignment.Center) {
                                Avatar(child.author, child.avatar, Modifier.size(28.dp), verified = childUser?.isVerified == true, verifiedType = childUser?.verifiedType ?: -1, shareWithProfile = true, crossfade = false)
                            }
                            Column(Modifier.weight(1f)) {
                                CommentName(post, child, compact = true)
                                if (child.text.isNotBlank()) { Spacer(Modifier.height(2.dp)); RichText(child.text, Post(child.id, child.author, text = child.text, raw = child.raw), style = MaterialTheme.typography.bodyMedium.copy(fontSize = 12.5.sp), modifier = Modifier.combinedClickable(hapticFeedbackEnabled = false, onClick = hapticClick { menu = child }, onLongClick = hapticClick { menu = child })) }
                                if (child.images.isNotEmpty()) { Spacer(Modifier.height(4.dp)); CommentPictures(child, gallery) }
                            }
                        }
                    }
                }
                Spacer(Modifier.height(4.dp))
                Row(Modifier.clip(RoundedCornerShape(8.dp)).reviewClickable(onClick = thread).padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("共${comment.replies.takeIf { it > 0 } ?: comment.children.size}条回复", color = colors.primary, fontSize = 12.5.sp, fontWeight = reviewWeight(FontWeight.SemiBold)); Spacer(Modifier.width(2.dp)); Icon(Icons.Rounded.ChevronRight, null, Modifier.size(16.dp), tint = colors.primary)
                }
            }
        }
    }
    menu?.let { selected ->
        ModalBottomSheet({ menu = null }, dragHandle = null, containerColor = colors.surface, shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)) {
            Spacer(Modifier.height(8.dp)); Box(Modifier.align(Alignment.CenterHorizontally).size(38.dp, 4.5.dp).background(colors.onSurfaceVariant.copy(alpha = .4f), RoundedCornerShape(2.25.dp))); Spacer(Modifier.height(4.dp))
            ReviewListItem(headlineContent = { Text("回复 @${selected.author}") }, leadingContent = { Icon(Icons.AutoMirrored.Rounded.Reply, null) }, modifier = Modifier.reviewClickable { menu = null; reply(selected) })
            ReviewListItem(headlineContent = { Text("复制评论内容") }, leadingContent = { Icon(Icons.Rounded.ContentCopy, null) }, modifier = Modifier.reviewClickable { menu = null; (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("评论", selected.text)); model.notice = "评论已复制到剪贴板" })
            if (model.uid.isNotBlank() && (selected.uid == model.uid || post.uid == model.uid)) ReviewListItem(headlineContent = { Text("删除评论", color = colors.error) }, supportingContent = if (post.uid == model.uid && selected.uid != model.uid) { { Text("博主可删除他人评论", fontSize = 12.sp, color = colors.error.copy(alpha = .8f)) } } else null, leadingContent = { Icon(Icons.Rounded.DeleteOutline, null, tint = colors.error) }, modifier = Modifier.reviewClickable { menu = null; deletion = selected })
        }
    }
    deletion?.let { selected ->
        val others = post.uid == model.uid && selected.uid != model.uid
        ReviewAlertDialog({ deletion = null }, title = { Text(if (others) "删除他人评论" else "删除评论") }, text = { Text(if (others) "确定要删除 @${selected.author} 的这条评论吗？删除后不可恢复。" else "确定要删除这条评论吗？删除后不可恢复。") }, confirmButton = { Button(onClick = hapticClick { deletion = null; model.mutate { model.repository.deleteComment(model.sessionCookie, selected.id); refresh() } }, colors = ButtonDefaults.buttonColors(containerColor = colors.error, contentColor = colors.onError)) { Text("删除") } }, dismissButton = { TextButton(hapticClick { deletion = null }) { Text("取消") } })
    }
}

@Composable
private fun CommentName(post: Post, comment: Comment, modifier: Modifier = Modifier, compact: Boolean = false, inThread: Boolean = false) {
    val colors = MaterialTheme.colorScheme
    val model = LocalReview.current
    val user = remember(comment.raw) { runCatching { JSONObject(comment.raw).optJSONObject("user") }.getOrNull() }
    val fans = secureImage(user?.optJSONObject("fansIcon")?.optString("icon_url").orEmpty().ifBlank { user?.optJSONObject("fans_icon")?.optString("icon_url").orEmpty() })
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(comment.author, Modifier.weight(1f, fill = false).reviewClickable { model.openProfile(comment) }, fontSize = if (compact) 12.5.sp else if (inThread) 14.sp else 13.5.sp, fontWeight = reviewWeight(if (inThread) FontWeight.SemiBold else FontWeight.Bold), color = if (compact) colors.primary else colors.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (fans.isNotBlank()) SubcomposeAsyncImage(fans, "微博铁粉等级标识", Modifier.height(if (compact) 13.dp else 14.dp), contentScale = ContentScale.Fit, loading = {}, error = {})
        if (user?.optBoolean("verified") == true) Icon(Icons.Rounded.Verified, null, Modifier.size(if (compact) 12.dp else 14.dp), tint = if (user.optInt("verified_type", -1) == 0) Color(0xFFFFC107) else Color(0xFF2196F3))
        if (post.uid.isNotBlank() && post.uid == comment.uid) Text("博主", Modifier.background(Color(0xFFF57C00), RoundedCornerShape(4.dp)).padding(horizontal = 4.dp, vertical = 1.dp), color = Color.White, fontSize = 10.sp, lineHeight = 11.sp, fontWeight = reviewWeight(FontWeight.SemiBold))
    }
}

@Composable
private fun CommentPictures(comment: Comment, gallery: (List<Media>, Int) -> Unit, inThread: Boolean = false) {
    val model = LocalReview.current
    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        comment.images.forEachIndexed { index, media ->
            val single = comment.images.size == 1 && !inThread
            val aspect = if (media.width > 0 && media.height > 0) (media.width.toFloat() / media.height).coerceIn(.5f, 2.2f) else 1f
            val width = if (single) minOf(160f, 180f * aspect) else if (inThread) 92f else 80f
            Box(Modifier.size(width.dp, if (single) (width / aspect).dp else width.dp).clip(RoundedCornerShape(if (single || inThread) 8.dp else 6.dp)).reviewClickable { model.mediaAuthor = comment.author; gallery(comment.images, index) }) {
                MediaImage(media, "评论图片", Modifier.fillMaxSize())
                if (single && (media.live || media.gif || media.long)) Row(Modifier.align(Alignment.BottomEnd).padding(4.dp).background(Color.Black.copy(alpha = if (media.live) .72f else .7f), RoundedCornerShape(if (media.live) 6.dp else 4.dp)).padding(horizontal = 4.dp, vertical = 1.5.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (media.live) { Icon(Icons.Rounded.MotionPhotosOn, null, Modifier.size(10.dp), tint = Color.White); Spacer(Modifier.width(2.dp)) }
                    Text(if (media.live) "LIVE" else if (media.gif) "GIF" else "长图", color = Color.White, fontSize = if (media.live) 8.5.sp else 9.sp, fontWeight = reviewWeight(FontWeight.Bold))
                }
            }
        }
    }
}
