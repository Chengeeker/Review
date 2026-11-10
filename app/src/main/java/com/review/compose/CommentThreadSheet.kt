@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

internal fun mergeThreadPreview(page: Page<Comment>, preview: List<Comment>): Page<Comment> = page.copy(items = (page.items + preview).distinctBy(Comment::id))

private val replyListNestedScroll = object : NestedScrollConnection {
    // Leftover upward velocity at the list end must not restart the sheet's expand spring.
    override suspend fun onPostFling(consumed: Velocity, available: Velocity): Velocity =
        Velocity(0f, available.y.coerceAtMost(0f))
}

@Composable
fun CommentThreadSheet(post: Post, parent: Comment, gallery: (List<Media>, Int) -> Unit, dismiss: () -> Unit, reply: (Comment) -> Unit, revision: Int) {
    val model = LocalReview.current
    val colors = MaterialTheme.colorScheme
    var reload by remember(parent.id) { mutableIntStateOf(0) }
    val initialRevision = remember(parent.id) { revision }
    val data = remember(parent.id, model.uid) { PagedContentState<Comment>().apply { rows.value = parent.children } }
    DisposableEffect(data) { onDispose { data.stopObservingPosts?.invoke() } }
    ModalBottomSheet(dismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), dragHandle = null, containerColor = colors.surface, shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)) {
        Column(Modifier.fillMaxWidth().height((LocalConfiguration.current.screenHeightDp * .9f).dp)) {
            Row(Modifier.padding(start = 8.dp, top = 8.dp, end = 8.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(hapticClick(dismiss)) { Icon(Icons.Rounded.Close, "关闭") }
                Text("共${maxOf(parent.replies, data.rows.value.size)}条回复", Modifier.weight(1f), fontSize = 20.sp, fontWeight = reviewWeight(FontWeight.SemiBold))
                IconButton(hapticClick { reload++ }, enabled = !data.busy.value) { if (data.busy.value) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Icon(Icons.Rounded.Refresh, "刷新回复") }
            }
            ReviewDivider(thickness = 1.dp, color = colors.outlineVariant.copy(alpha = .45f))
            Box(Modifier.weight(1f).nestedScroll(replyListNestedScroll)) {
                CompositionLocalProvider(LocalContentTop provides 0.dp) {
                    PagedContent("thread:${parent.id}:${model.uid}", { cursor ->
                        val page = if (post.demo) Page(parent.children) else model.repository.commentPage(model.sessionCookie, post, cursor, false, parent)
                        if (cursor == "0" && reload == 0 && revision == initialRevision) mergeThreadPreview(page, parent.children) else page
                    }, Comment::id, empty = { Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { Text("暂无回复", color = colors.onSurfaceVariant) } },
                        retained = data, reloadKey = revision to reload,
                        loading = {
                            Box(Modifier.fillMaxWidth().height(48.dp), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                            }
                        },
                        endOfList = {
                            Box(Modifier.fillMaxWidth().height(48.dp), contentAlignment = Alignment.Center) {
                                Text("没有更多回复", fontSize = 12.sp, color = colors.onSurfaceVariant)
                            }
                        }) {
                        CommentRow(post, it, gallery, reply, {}, { reload++ }, inThread = true)
                    }
                }
            }
        }
    }
}
