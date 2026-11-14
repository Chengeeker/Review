package com.review.compose

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.PeopleOutline
import androidx.compose.material.icons.rounded.Inbox
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.automirrored.rounded.Login
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeedScreen(model: ReviewModel, gallery: (List<Media>, Int) -> Unit) {
    val state = rememberLazyListState()
    var savedPosition by remember(model.uid, model.group.id) { mutableStateOf<Pair<Int, Int>?>(null) }
    var pullRefreshPending by remember(model.uid, model.group.id) { mutableStateOf(false) }
    var topRefreshPending by remember(model.uid, model.group.id) { mutableStateOf(false) }
    LaunchedEffect(pullRefreshPending, topRefreshPending, model.feedLoading, model.feedError) {
        if ((pullRefreshPending || topRefreshPending) && !model.feedLoading) {
            if (model.feedError == null) {
                withFrameNanos { }
                state.scrollToItem(0)
                savedPosition = null
            }
            pullRefreshPending = false
            topRefreshPending = false
        }
    }
    val topThreshold = with(LocalDensity.current) { 50.dp.toPx() }
    var topHandled by remember { mutableIntStateOf(model.feedTopRequest) }
    var toggleHandled by remember { mutableIntStateOf(model.feedToggleRequest) }
    var saveHandled by remember { mutableIntStateOf(model.feedSaveTopRequest) }
    var refreshHandled by remember { mutableIntStateOf(model.feedRefreshTopRequest) }
    LaunchedEffect(model.feedTopRequest, model.feedToggleRequest, model.feedSaveTopRequest, model.feedRefreshTopRequest) {
        val toggle = toggleHandled != model.feedToggleRequest
        val save = saveHandled != model.feedSaveTopRequest
        val force = topHandled != model.feedTopRequest
        val refresh = refreshHandled != model.feedRefreshTopRequest
        refreshHandled = model.feedRefreshTopRequest
        topHandled = model.feedTopRequest; toggleHandled = model.feedToggleRequest; saveHandled = model.feedSaveTopRequest
        if ((refresh || save) && model.feedRefreshing) topRefreshPending = true
        val away = state.firstVisibleItemIndex > 0 || state.firstVisibleItemScrollOffset > topThreshold
        if (toggle && away || save && away) savedPosition = state.firstVisibleItemIndex to state.firstVisibleItemScrollOffset
        if (toggle && !away && savedPosition != null) {
            val (index, offset) = savedPosition!!; savedPosition = null
            state.animateScrollToItem(index.coerceAtMost((state.layoutInfo.totalItemsCount - 1).coerceAtLeast(0)), offset)
        } else if (toggle || save || force) state.animateScrollToItem(0)
    }
    val nearEnd by remember { derivedStateOf { (state.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: -1) >= state.layoutInfo.totalItemsCount - 3 } }
    LaunchedEffect(nearEnd, model.feed.size) { if (nearEnd && model.feedMore && model.feedError == null) model.loadFeed() }
    val colors = MaterialTheme.colorScheme
    val friendsGroup = model.group.id in setOf("friends", "all_follow") || model.group.id.startsWith("11000") || model.group.id.startsWith("10001") || model.groups.any { it.section == "我的分组" && it.id == model.group.id }
    if (model.uid.isBlank() && !model.demo && friendsGroup) {
        Box(Modifier.fillMaxSize().padding(top = LocalContentTop.current).padding(24.dp), contentAlignment = Alignment.Center) {
            Surface(Modifier.padding(horizontal = 10.dp, vertical = 5.dp), color = colors.surfaceContainerLowest, shape = RoundedCornerShape(22.dp), border = BorderStroke(.8.dp, colors.outlineVariant.copy(alpha = .25f))) {
                Column(Modifier.padding(24.8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Rounded.PeopleOutline, null, Modifier.size(56.dp), tint = colors.primary)
                    Spacer(Modifier.height(16.dp)); Text("关注流需要登录", fontSize = 18.sp, fontWeight = reviewWeight(FontWeight.Bold))
                    Spacer(Modifier.height(8.dp)); Text("登录或导入微博账号凭据后，即可同步查看你关注的好友与特别关注动态", fontSize = 13.sp, color = colors.onSurfaceVariant, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(20.dp)); Button(onClick = hapticClick { model.navigate("account") }, contentPadding = PaddingValues(start = 16.dp, end = 24.dp, top = 10.dp, bottom = 10.dp)) { Icon(Icons.AutoMirrored.Rounded.Login, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("去登录 / 导入凭据") }
                }
            }
        }
        return
    }
    ReviewRefresh(pullRefreshPending && model.feedRefreshing && model.feed.isNotEmpty(), onRefresh = {
        if (!model.feedLoading) { pullRefreshPending = true; model.refreshFeed() }
    }, failed = model.feedError != null) {
        LazyColumn(Modifier.fillMaxSize().testTag("feed-list"), state, contentPadding = if (model.feed.isEmpty()) PaddingValues(top = LocalContentTop.current) else PaddingValues(top = LocalContentTop.current + 4.dp, bottom = rootScrollBottom(model))) {
            items(model.feed.filterNot { it.uid in model.blocked }, key = Post::id) { PostRow(it, gallery) }
            if (model.feed.isEmpty()) item {
                Box(Modifier.fillParentMaxHeight().fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                    if (model.feedLoading) CircularProgressIndicator()
                    else Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Rounded.Inbox, null, Modifier.size(56.dp), tint = colors.onSurfaceVariant.copy(alpha = .5f))
                        Spacer(Modifier.height(16.dp)); Text(model.feedError ?: "暂无微博内容", color = colors.onSurfaceVariant, textAlign = TextAlign.Center)
                        Spacer(Modifier.height(16.dp)); OutlinedButton(onClick = hapticClick(model::refreshFeed)) { Icon(Icons.Rounded.Refresh, null, Modifier.size(16.dp)); Spacer(Modifier.width(8.dp)); Text("重新加载") }
                    }
                }
            } else if (model.feedLoading) item { LoadingRow() }
            else model.feedError?.let { item { ErrorNotice(it, model::retryFeed) } }
        }
    }
}

@Composable
internal fun rootScrollBottom(model: ReviewModel) = if (!model.bool("floating", true)) 16.dp else if (model.bool("liquidGlass")) WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + 76.dp else 72.dp

@Composable
fun ModeNotice(model: ReviewModel) {
    if (model.demo) Text("设计预览 · 以下均为示例内容", Modifier.padding(16.dp), style = MaterialTheme.typography.labelSmall)
}
