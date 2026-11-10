@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package com.review.compose

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException

@Composable
fun EditHistorySheet(post: Post, visible: Boolean, gallery: (List<Media>, Int) -> Unit, close: () -> Unit) {
    val model = LocalReview.current
    val colors = MaterialTheme.colorScheme
    val cookie = model.sessionCookie
    val mid = post.data.optString("mid").takeIf { it.isNotEmpty() && it.all(Char::isDigit) } ?: post.id
    var rows by remember(mid, cookie) { mutableStateOf(emptyList<Post>()) }
    var total by remember(mid, cookie) { mutableIntStateOf(0) }
    var lastPage by remember(mid, cookie) { mutableStateOf(emptyList<Post>()) }
    var error by remember(mid, cookie) { mutableStateOf<String?>(null) }
    var page by remember(mid, cookie) { mutableIntStateOf(1) }
    var attempt by remember(mid, cookie) { mutableIntStateOf(0) }
    var loading by remember(mid, cookie) { mutableStateOf(true) }
    val listState = rememberLazyListState()
    LaunchedEffect(mid, cookie, page, attempt) {
        loading = true; error = null
        try {
            val result = if (model.demo) EditHistoryPage(emptyList(), null) else model.repository.editHistory(cookie, mid, page)
            if (result.revisions.isNotEmpty() && result.revisions != lastPage) {
                rows = rows + result.revisions
                lastPage = result.revisions
                total = maxOf(rows.size, result.total ?: total)
            } else {
                total = rows.size
                if (rows.isEmpty()) error = "未获取到编辑记录或该微博无需编辑历史"
            }
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) { error = e.message ?: "未获取到编辑记录或该微博无需编辑历史" }
        finally { loading = false }
    }
    if (!visible) return
    ModalBottomSheet(close, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = colors.surfaceContainerLow, shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        dragHandle = { Box(Modifier.padding(top = 12.dp, bottom = 8.dp).size(38.dp, 4.5.dp).background(colors.onSurfaceVariant.copy(alpha = .4f), RoundedCornerShape(32.dp))) }) {
        Column(Modifier.heightIn(max = (LocalConfiguration.current.screenHeightDp * .86f).dp - 24.5.dp).testTag("edit-history-content")) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.background(colors.primaryContainer.copy(alpha = .7f), RoundedCornerShape(14.dp)).padding(8.dp)) { Icon(Icons.Rounded.History, null, Modifier.size(22.dp), tint = colors.primary) }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("微博编辑记录", fontSize = 17.sp, fontWeight = reviewWeight(FontWeight.Bold))
                    Text(if (rows.isNotEmpty()) "共 $total 个修订版本" else "@${post.author} 的博文修订历史", fontSize = 12.sp, color = colors.onSurfaceVariant)
                }
                IconButton(onClick = hapticClick(close)) { Icon(Icons.Rounded.Close, "关闭编辑记录") }
            }
            Box(Modifier.height(1.dp), contentAlignment = Alignment.Center) { ReviewDivider() }
            if (rows.isEmpty()) Box(Modifier.fillMaxWidth().height(220.dp).padding(horizontal = 24.dp), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    if (error == null) {
                        CircularProgressIndicator(Modifier.size(32.dp), strokeWidth = 3.dp)
                        Spacer(Modifier.height(16.dp)); Text("正在加载编辑记录...", color = colors.onSurfaceVariant)
                    } else {
                        Icon(Icons.Rounded.Info, null, Modifier.size(40.dp), tint = colors.error)
                        Spacer(Modifier.height(12.dp)); Text(error.orEmpty(), textAlign = TextAlign.Center, color = colors.onSurfaceVariant)
                        Spacer(Modifier.height(16.dp))
                        FilledTonalButton(onClick = hapticClick { attempt++ }) { Icon(Icons.Rounded.Refresh, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("重试") }
                    }
                }
            } else LazyColumn(Modifier.weight(1f, false).testTag("edit-history-list"), state = listState, contentPadding = PaddingValues(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                itemsIndexed(rows) { index, revision ->
                    val latest = index == 0; val initial = index == total - 1
                    Surface(color = colors.surfaceContainerLowest, shape = RoundedCornerShape(20.dp), border = BorderStroke(if (latest) 1.2.dp else .8.dp, if (latest) colors.primary.copy(alpha = .35f) else colors.outlineVariant.copy(alpha = .25f))) {
                        Column(Modifier.fillMaxWidth().padding(16.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(if (latest) "🔥 最新版本 (当前)" else if (initial) "🌱 首次发布" else "第 ${total - index} 版",
                                    Modifier.background(if (latest) colors.primaryContainer else if (initial) colors.secondaryContainer else colors.surfaceContainerHighest, RoundedCornerShape(20.dp)).padding(horizontal = 10.dp, vertical = 4.dp),
                                    fontSize = 12.sp, fontWeight = reviewWeight(FontWeight.Bold), color = if (latest) colors.onPrimaryContainer else if (initial) colors.onSecondaryContainer else colors.onSurfaceVariant)
                                Spacer(Modifier.weight(1f))
                                Text(postTime(revision.time, true, false, false, false, false), fontSize = 12.sp, color = colors.onSurfaceVariant)
                            }
                            Spacer(Modifier.height(12.dp))
                            SelectionContainer { RichText(revision.availableFullText().ifBlank { revision.text }, revision, style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 22.5.sp)) }
                            if (revision.images.isNotEmpty()) {
                                Spacer(Modifier.height(12.dp))
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    revision.images.forEachIndexed { mediaIndex, media -> MediaImage(media, "编辑记录第 ${mediaIndex + 1} 张图片", Modifier.size(84.dp).clip(RoundedCornerShape(12.dp)).reviewClickable { model.mediaAuthor = revision.author; gallery(revision.images, mediaIndex) }) }
                                }
                            }
                            revision.data.optString("region_name").takeIf(String::isNotBlank)?.let { region ->
                                Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Outlined.LocationOn, null, Modifier.size(14.dp), tint = colors.onSurfaceVariant.copy(alpha = .7f)); Spacer(Modifier.width(4.dp))
                                    Text(region, fontSize = 11.5.sp, color = colors.onSurfaceVariant.copy(alpha = .7f))
                                }
                            }
                        }
                    }
                }
                if (rows.size < total) item {
                    if (error != null) ErrorNotice(error.orEmpty()) { attempt++ }
                    else {
                        Box(Modifier.fillMaxWidth().padding(8.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(Modifier.size(24.dp))
                        }
                        LaunchedEffect(rows.size, loading) { if (!loading) { loading = true; page++ } }
                    }
                }
            }
        }
    }
}
