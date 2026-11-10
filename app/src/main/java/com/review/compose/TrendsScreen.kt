@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable
fun TrendsScreen(model: ReviewModel) {
    val standalone = LocalReviewRoute.current?.name == "trends"
    val active = LocalPageActive.current
    var ownTop by remember { mutableIntStateOf(0) }
    val topRequest = if (standalone) ownTop else model.trendsTopRequest
    val refreshRequest = if (standalone) 0 else model.trendsRefreshRequest
    val categories = remember { listOf("mine" to "我的", "hot" to "热搜", "ent" to "文娱", "social" to "社会", "tech" to "科技", "life" to "生活", "sports" to "体育", "acg" to "ACG") }
    val pager = rememberPagerState(initialPage = 1) { categories.size }
    val cache = remember(model.uid) { mutableStateMapOf<Int, List<Trend>>() }
    val scope = rememberCoroutineScope()
    val layer = rememberGraphicsLayer()
    val backdrop = remember(layer) { ReviewBackdrop(layer) }
    val top = TopAppBarDefaults.windowInsets.asPaddingValues().calculateTopPadding() + 104.dp
    CompositionLocalProvider(LocalBackdrop provides backdrop) {
        Box(Modifier.fillMaxSize()) {
            HorizontalPager(pager, Modifier.fillMaxSize().recordBackdrop(backdrop)) { page ->
                var error by remember { mutableStateOf<String?>(null) }
                var loading by remember { mutableStateOf(false) }
                var pulling by remember { mutableStateOf(false) }
                var retryFromPull by remember { mutableStateOf(false) }
                var seenTopRequest by remember { mutableIntStateOf(topRequest) }
                var seenRefreshRequest by remember { mutableIntStateOf(refreshRequest) }
                val state = rememberLazyListState()
                suspend fun fetch(fromPull: Boolean = false) {
                    if (loading) return
                    loading = true
                    pulling = fromPull
                    retryFromPull = fromPull
                    error = null
                    try {
                        val updated = if (model.demo) PreviewContent.trends.mapIndexed { index, trend -> trend.copy(rank = index + 1) } else model.repository.hotList(model.sessionCookie, categories[page].first)
                        if (fromPull) state.requestScrollToItem(0)
                        cache[page] = updated
                    }
                    catch (e: CancellationException) { throw e }
                    catch (e: Exception) { if (fromPull || cache[page].isNullOrEmpty()) error = e.message ?: "热搜加载失败" }
                    finally { loading = false; pulling = false }
                }
                LaunchedEffect(model.uid) { if (cache[page] == null) fetch() }
                LaunchedEffect(topRequest) {
                    if (seenTopRequest != topRequest) {
                        seenTopRequest = topRequest
                        if (active && pager.currentPage == page) state.animateScrollToItem(0)
                    }
                }
                LaunchedEffect(refreshRequest) {
                    if (seenRefreshRequest != refreshRequest) {
                        seenRefreshRequest = refreshRequest
                        if (active && pager.currentPage == page) fetch()
                    }
                }
                val rows = cache[page].orEmpty()
                val bottom = if (!standalone) rootScrollBottom(model) else 16.dp
                ReviewRefresh(pulling, onRefresh = { scope.launch { fetch(fromPull = true) } }, failed = error != null, topInset = top,
                    enabled = !loading || pulling) {
                    LazyColumn(Modifier.fillMaxSize(), state, contentPadding = PaddingValues(start = 16.dp, top = top + 8.dp, end = 16.dp, bottom = bottom)) {
                        error?.let { item { ErrorNotice(it) { scope.launch { fetch(retryFromPull) } } } }
                        itemsIndexed(rows, key = { _, item -> item.word }) { index, trend ->
                            TrendRow(trend, categories[page].first == "hot") {
                                model.openSearchResults(trend.word)
                            }
                            if (index < rows.lastIndex) ReviewDivider(Modifier.padding(start = 52.dp), thickness = .5.dp)
                        }
                        if (rows.isEmpty() && !loading && error == null) item { EmptyNotice("暂无热搜内容", "下拉刷新") }
                    }
                    if (rows.isEmpty() && loading && !pulling) {
                        Box(Modifier.fillMaxSize().padding(top = top, bottom = bottom), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator()
                        }
                    }
                }
            }
            Column(Modifier.frostedBackdrop(MaterialTheme.colorScheme.background)) {
                TopAppBar(title = { Text("微博热搜", fontWeight = reviewWeight(FontWeight.Bold), fontSize = 18.sp) }, navigationIcon = { if (standalone) IconButton(onClick = hapticClick(model::back)) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回") } }, actions = {
                    IconButton(onClick = hapticClick { model.query = ""; model.navigate("search") }) { Icon(Icons.Outlined.Search, "搜索") }; Spacer(Modifier.width(4.dp))
                }, modifier = Modifier.reviewClickable { if (standalone) ownTop++ else model.tapTab(1) }, expandedHeight = 56.dp, colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent))
                PrimaryScrollableTabRow(pager.currentPage, minTabWidth = 0.dp, edgePadding = 0.dp, containerColor = Color.Transparent) {
                    categories.forEachIndexed { index, item ->
                        val selected = pager.currentPage == index
                        Tab(selected, hapticClick { scope.launch { pager.animateScrollToPage(index) } }, Modifier.height(48.dp), unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant) {
                            Text(item.second, Modifier.padding(horizontal = 14.dp), fontSize = 15.sp,
                                fontWeight = reviewWeight(if (selected) FontWeight.SemiBold else FontWeight.Normal))
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun TrendBadge(label: String) {
    val background = when (label) { "热", "爆" -> Color(0xFFFF2442); "新" -> Color(0xFF00B0FF); "沸" -> Color(0xFFFF6D00); else -> MaterialTheme.colorScheme.primaryContainer }
    Text(label, Modifier.background(background, RoundedCornerShape(4.dp)).padding(horizontal = 5.dp, vertical = 1.5.dp), color = if (label in setOf("热", "爆", "新", "沸")) Color.White else MaterialTheme.colorScheme.onPrimaryContainer, fontSize = 10.sp, lineHeight = 11.sp, fontWeight = reviewWeight(FontWeight.Bold))
}

@Composable
private fun TrendRow(trend: Trend, category: Boolean, click: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    Row(Modifier.fillMaxWidth().reviewClickable(onClick = click).padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(40.dp), contentAlignment = Alignment.Center) {
            when {
                trend.pinned -> Icon(Icons.Outlined.PushPin, null, Modifier.align(Alignment.CenterStart).size(22.dp), tint = Color(0xFFFF6D00))
                !trend.ranked -> Box(Modifier.size(9.dp).background(Color(0xFFFF7A45), CircleShape))
                else -> Row(Modifier.fillMaxWidth().height(24.dp).background(when (trend.rank) { 1 -> Color(0xFFFF3852); 2 -> Color(0xFFFF9406); 3 -> Color(0xFFFFC229); else -> colors.onSurfaceVariant.copy(alpha = .35f) }, RoundedCornerShape(6.dp)), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    if (trend.rank in 1..3) Icon(Icons.Outlined.LocalFireDepartment, null, Modifier.size(15.dp), tint = Color.White)
                    Text("${trend.rank}", color = if (trend.rank in 1..3) Color.White else colors.surface, fontSize = 14.sp)
                }
            }
        }
        Spacer(Modifier.width(12.dp))
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
            Text(trend.word, Modifier.weight(1f, false), fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (trend.label.isNotBlank()) { Spacer(Modifier.width(6.dp)); TrendBadge(trend.label) }
            if (trend.location.isNotBlank()) Icon(Icons.Outlined.LocationOn, trend.location, Modifier.padding(start = 6.dp).size(13.dp), tint = Color(0xFFFF7A45))
            if (category && trend.category.isNotBlank()) Text(trend.category, Modifier.padding(start = 4.dp).background(colors.surfaceContainerHighest, RoundedCornerShape(3.dp)).padding(horizontal = 4.dp, vertical = 2.dp), fontSize = 9.5.sp, color = colors.onSurfaceVariant)
        }
        if ((trend.heat.toLongOrNull() ?: 0) > 0) Text("${trend.heat} 讨论", Modifier.padding(start = 10.dp), fontSize = 11.5.sp, color = colors.onSurfaceVariant)
    }
}
