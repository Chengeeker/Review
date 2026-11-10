@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch

val LocalReview = staticCompositionLocalOf<ReviewModel> { error("Missing app model") }

class PagedContentState<T> {
    val rows = mutableStateOf<List<T>>(emptyList())
    val cursor = mutableStateOf("0")
    val more = mutableStateOf(true)
    val busy = mutableStateOf(false)
    val refreshing = mutableStateOf(false)
    val error = mutableStateOf<String?>(null)
    var loaded = false
    internal var loadedReloadKey: Any? = null
    internal var retryRefresh = true
    internal var retryFromPull = false
    internal var stopObservingPosts: (() -> Unit)? = null
    val scroll = androidx.compose.foundation.lazy.LazyListState()
}

@Composable
fun <T> PagedContent(identity: String, load: suspend (String) -> Page<T>, itemKey: (T) -> String,
    header: LazyListScope.() -> Unit = {}, body: (LazyListScope.(List<T>) -> Unit)? = null,
    empty: (@Composable androidx.compose.foundation.lazy.LazyItemScope.() -> Unit)? = null, retained: PagedContentState<T>? = null,
    loading: (@Composable androidx.compose.foundation.lazy.LazyItemScope.() -> Unit)? = null, showLoadMore: Boolean = true, loadOnScrollOnly: Boolean = false,
    contentPadding: PaddingValues? = null, allowEmptyContinuation: Boolean = false,
    reloadKey: Any? = null, endOfList: (@Composable androidx.compose.foundation.lazy.LazyItemScope.() -> Unit)? = null,
    row: @Composable (T) -> Unit) {
    val scope = rememberCoroutineScope()
    val data = retained ?: remember(identity) { PagedContentState<T>() }
    val model = LocalReview.current
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    DisposableEffect(model, data, lifecycle) {
        if (data.stopObservingPosts == null) {
            val update: (String, Post?) -> Unit = { id, changed ->
                @Suppress("UNCHECKED_CAST")
                data.rows.value = data.rows.value.mapNotNull { item -> if (item is Post && item.id == id) changed as T? else item }
            }
            val observer = androidx.lifecycle.LifecycleEventObserver { _, event -> if (event == androidx.lifecycle.Lifecycle.Event.ON_DESTROY) data.stopObservingPosts?.invoke() }
            data.stopObservingPosts = { model.postObservers.remove(update); lifecycle.removeObserver(observer); data.stopObservingPosts = null }
            model.postObservers.add(update)
            lifecycle.addObserver(observer)
        }
        // Retained channels must receive changes while another channel is visible.
        onDispose { if (retained == null) data.stopObservingPosts?.invoke() }
    }
    var rows by data.rows
    var cursor by data.cursor
    var more by data.more
    var busy by data.busy
    var error by data.error
    val state = data.scroll
    val currentIdentity by rememberUpdatedState(identity to reloadKey)
    var requestGeneration by remember(data) { mutableIntStateOf(0) }
    suspend fun fetch(refresh: Boolean, replaceRequest: Boolean = false, fromPull: Boolean = false) {
        if ((!replaceRequest && busy) || (!refresh && !more)) return
        val generation = ++requestGeneration
        val requestedIdentity = identity to reloadKey
        data.retryRefresh = refresh; data.retryFromPull = fromPull
        busy = true; data.refreshing.value = refresh && !replaceRequest; error = null
        try {
            val previous = if (refresh) "0" else cursor
            val page = load(previous)
            if (currentIdentity != requestedIdentity || requestGeneration != generation) return
            val merged = ((if (refresh) emptyList() else rows) + page.items).distinctBy(itemKey)
            val advanced = if (page.items.isEmpty()) allowEmptyContinuation else refresh || merged.size > rows.size
            more = canContinuePage(previous, page.next, advanced)
            if (fromPull) state.requestScrollToItem(0)
            else if (refresh && reloadKey != null) state.requestScrollToItem(state.firstVisibleItemIndex, state.firstVisibleItemScrollOffset)
            rows = merged; cursor = page.next; data.loaded = true; data.loadedReloadKey = reloadKey
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) { if (currentIdentity == requestedIdentity && requestGeneration == generation) {
            error = e.message ?: "加载失败"
            if (reloadKey != null) model.notice = error
        } }
        finally { if (requestGeneration == generation) { data.busy.value = false; data.refreshing.value = false } }
    }
    LaunchedEffect(identity, reloadKey) {
        if (!data.loaded || data.loadedReloadKey != reloadKey) fetch(true, replaceRequest = true)
    }
    val loadNext by rememberUpdatedState<suspend () -> Unit>({ fetch(false) })
    LaunchedEffect(data, identity, reloadKey, loadOnScrollOnly) {
        snapshotFlow {
            val layout = state.layoutInfo
            val last = layout.visibleItemsInfo.lastOrNull()
            // Appending replies changes the rows before the list measures the new tail.
            val atEnd = last != null && last.index >= layout.totalItemsCount - 4 &&
                (body != null || layout.totalItemsCount >= rows.size)
            cursor.takeIf { it != "0" && atEnd && (!loadOnScrollOnly || state.isScrollInProgress) &&
                rows.isNotEmpty() && !busy && more && error == null }
        }.filterNotNull().collect { loadNext() }
    }
    ReviewRefresh(data.refreshing.value && rows.isNotEmpty(), onRefresh = { scope.launch { fetch(true, fromPull = true) } }, failed = error != null) {
        LazyColumn(Modifier.fillMaxSize(), state, contentPadding = contentPadding ?: PaddingValues(top = LocalContentTop.current, bottom = 24.dp)) {
            header()
            if (body == null) items(rows, key = itemKey) { row(it) } else body(rows)
            if (busy) item { if (loading != null) loading() else Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp)) } }
            error?.let { message -> item { ErrorNotice(message) { scope.launch { fetch(data.retryRefresh, fromPull = data.retryFromPull) } } } }
            if (rows.isEmpty() && !busy && error == null) item { if (empty == null) EmptyNotice("暂无内容", "下拉刷新") else empty() }
            if (showLoadMore && more && !busy && error == null) item { TextButton(onClick = hapticClick { scope.launch { fetch(false) } }, Modifier.fillMaxWidth()) { Text(if (rows.isEmpty()) "继续筛选" else "加载更多") } }
            if (endOfList != null && !more && !busy && error == null && rows.isNotEmpty()) item(content = endOfList)
        }
    }
}

@Composable
fun PostRow(post: Post, gallery: (List<Media>, Int) -> Unit) {
    val model = LocalReview.current
    if (post.uid !in model.blocked) PostCard(post, post.favorited, { model.openPost(post) }, { model.postAction(post, "favorite") }, gallery, model::openPost)
}
@Composable
fun UserRow(user: User) {
    val model = LocalReview.current
    ReviewListItem(headlineContent = { Text(user.name) }, supportingContent = { Text(user.description.ifBlank { "${user.followers} 粉丝" }, maxLines = 2) },
        leadingContent = { Avatar(user.name, user.avatar, verified = user.isVerified, verifiedType = user.verifiedType, shareWithProfile = true) }, modifier = Modifier.reviewClickable { model.openProfile(user) })
}

@Composable
fun RelationsScreen(id: String, initiallyFans: Boolean) {
    val model = LocalReview.current
    val self = id.isBlank() || id == model.uid
    val labels = listOf("关注列表", if (self) "我的粉丝" else "粉丝列表") + if (self) listOf("我的超话") else emptyList()
    val pager = rememberPagerState(initialPage = if (initiallyFans) 1 else 0) { labels.size }
    val scope = rememberCoroutineScope()
    val states = remember(id, model.uid) { List(2) { PagedContentState<User>() } }
    val topics = remember(id, model.uid) { PagedContentState<FollowedTopic>() }
    DisposableEffect(states, topics) { onDispose { (states + listOf(topics)).forEach { it.stopObservingPosts?.invoke() } } }
    Column(Modifier.fillMaxSize()) {
        PrimaryTabRow(pager.currentPage, containerColor = Color.Transparent) {
            labels.forEachIndexed { i, title -> Tab(pager.currentPage == i, hapticClick { scope.launch { pager.animateScrollToPage(i) } }, Modifier.height(48.dp), unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant, text = { Text(title,
                fontSize = if (pager.currentPage == i) 15.sp else 14.5.sp, fontWeight = reviewWeight(if (pager.currentPage == i) FontWeight.Bold else FontWeight.Normal)) }) }
        }
        HorizontalPager(pager, Modifier.weight(1f)) { tab ->
            if (tab == 2) FollowedTopicsScreen(id, topics)
            else if (model.uid.isBlank() && !model.demo) {
                Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Outlined.PeopleOutline, null, Modifier.size(60.dp), tint = MaterialTheme.colorScheme.primary.copy(alpha = .6f))
                    Spacer(Modifier.height(16.dp)); Text("登录后即可同步关注列表和粉丝列表", fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.SemiBold))
                    Spacer(Modifier.height(16.dp)); Button(hapticClick { model.navigate("account") }) { Icon(Icons.Outlined.Login, null); Spacer(Modifier.width(8.dp)); Text("立即登录") }
                }
            } else PagedContent("relations:$id:$tab:${model.uid}", { model.repository.relations(model.sessionCookie, id, it.toInt().coerceAtLeast(1), tab == 1) }, User::id,
                retained = states[tab], contentPadding = PaddingValues(12.dp), showLoadMore = false,
                loading = { Box(Modifier.fillMaxWidth().then(if (states[tab].rows.value.isEmpty()) Modifier.fillParentMaxHeight() else Modifier.height(64.dp)), contentAlignment = Alignment.Center) { CircularProgressIndicator() } },
                empty = { Column(Modifier.fillParentMaxHeight().fillMaxWidth().padding(horizontal = 28.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Outlined.PeopleOutline, null, Modifier.size(54.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .4f))
                    Spacer(Modifier.height(12.dp)); Text(if (tab == 1) "暂无粉丝" else "暂无关注的人", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                } }, body = { users -> itemsIndexed(users, key = { _, user -> user.id }) { index, user ->
                    if (index > 0) ReviewDivider(Modifier.padding(start = 64.dp), .5.dp)
                    SettingsTile(headlineContent = { Text(user.name, fontSize = 15.sp, lineHeight = 20.25.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        supportingContent = { Text(user.verified.ifBlank { user.description.ifBlank { "粉丝 ${user.followers}" } }, fontSize = 12.5.sp, lineHeight = 17.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        leadingContent = { Avatar(user.name, user.avatar, Modifier.size(46.dp), user.isVerified, user.verifiedType, shareWithProfile = true) },
                        trailingContent = { Icon(Icons.Rounded.ArrowForwardIos, null, Modifier.size(14.dp)) },
                        modifier = Modifier.reviewClickable { model.openProfile(user) }.padding(vertical = 3.dp))
                } }) {}
        }
    }
}
@Composable
fun FavoritesScreen(gallery: (List<Media>, Int) -> Unit) {
    val model = LocalReview.current
    val pager = rememberPagerState { 2 }
    val scope = rememberCoroutineScope()
    val states = remember(model.uid) { List(2) { PagedContentState<Post>() } }
    DisposableEffect(states) { onDispose { states.forEach { it.stopObservingPosts?.invoke() } } }
    Column(Modifier.fillMaxSize()) {
        PrimaryTabRow(pager.currentPage, containerColor = Color.Transparent) { listOf("我的赞", "我的收藏").forEachIndexed { i, title -> Tab(pager.currentPage == i, hapticClick { scope.launch { pager.animateScrollToPage(i) } }, Modifier.height(48.dp), unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
            text = { Text(title, fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.Bold)) }) } }
        if (model.uid.isBlank() && !model.demo) {
            Column(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Rounded.Favorite, null, Modifier.size(60.dp), tint = MaterialTheme.colorScheme.primary.copy(alpha = .6f))
                Spacer(Modifier.height(16.dp)); Text("登录后即可同步查看您点赞与收藏的微博", fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.SemiBold))
                Spacer(Modifier.height(16.dp)); Button(hapticClick { model.navigate("account") }) { Icon(Icons.Outlined.Login, null); Spacer(Modifier.width(8.dp)); Text("立即登录") }
            }
        } else HorizontalPager(pager, Modifier.weight(1f)) { index ->
            val likes = index == 0
            PagedContent("saved:$likes:${model.uid}", { model.repository.savedPosts(model.sessionCookie, model.uid, it.toInt().coerceAtLeast(1), likes) }, Post::id, retained = states[index], showLoadMore = false,
                loading = { Box(Modifier.fillMaxWidth().then(if (states[index].rows.value.isEmpty()) Modifier.fillParentMaxHeight() else Modifier.height(64.dp)), contentAlignment = Alignment.Center) { CircularProgressIndicator() } },
                empty = { Column(Modifier.fillParentMaxHeight().fillMaxWidth(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(if (likes) Icons.Rounded.FavoriteBorder else Icons.Rounded.StarBorder, null, Modifier.size(54.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .4f))
                    Spacer(Modifier.height(12.dp)); Text(if (likes) "暂无点赞内容" else "暂无收藏内容", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                } }) { PostRow(it, gallery) }
        }
    }
}
@Composable
fun HistoryScreen(gallery: (List<Media>, Int) -> Unit) {
    val model = LocalReview.current
    var clear by remember { mutableStateOf(false) }
    LazyColumn(contentPadding = PaddingValues(top = LocalContentTop.current)) {
        item { TextButton(onClick = hapticClick { clear = true }) { Text("清空浏览记录") } }
        items(model.history, key = Post::id) { PostRow(it, gallery) }
    }
    if (clear) ReviewAlertDialog(onDismissRequest = { clear = false }, title = { Text("清空浏览记录？") }, confirmButton = { TextButton(onClick = hapticClick { model.clearHistory(); clear = false }) { Text("清空") } }, dismissButton = { TextButton(onClick = hapticClick { clear = false }) { Text("取消") } })
}

@Composable
fun PostActions() {
    val model = LocalReview.current
    val context = LocalContext.current
    val colors = MaterialTheme.colorScheme
    var delete by remember(model.uid) { mutableStateOf<Post?>(null) }
    var copyPost by remember(model.uid) { mutableStateOf<Post?>(null) }
    fun copy(label: String, value: String, notice: String) {
        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText(label, value))
        model.actionPost = null
        model.notice = notice
    }
    model.actionPost?.let { post ->
        val owned = model.uid.isNotBlank() && post.uid == model.uid
        val fullText = remember(post.raw, post.text) { post.availableFullText().ifBlank { post.text } }
        val editCount = post.data.optInt("edit_count")
        ModalBottomSheet(onDismissRequest = { model.actionPost = null }, containerColor = colors.surfaceContainerLow,
            shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)) {
            Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 8.dp)) {
                if (owned) {
                    PostActionTile(Icons.Outlined.Edit, "编辑微博") {
                        model.saveDraft(fullText); model.actionPost = null; model.navigate("edit:${post.id}", post)
                    }
                    PostActionTile(Icons.Rounded.DeleteOutline, "删除微博", danger = true) {
                        delete = post; model.actionPost = null
                    }
                    Box(Modifier.height(16.dp), contentAlignment = Alignment.Center) { ReviewDivider(thickness = 1.dp) }
                }
                PostActionTile(Icons.Rounded.History, "查看编辑记录", if (editCount > 0) "已编辑 $editCount 次" else null) {
                    model.actionPost = null; model.revisionPost = post
                }
                PostActionTile(Icons.Rounded.ContentCopy, "复制微博正文") { copyPost = post; model.actionPost = null }
                PostActionTile(if (post.favorited) Icons.Rounded.Star else Icons.Rounded.StarOutline,
                    if (post.favorited) "取消收藏" else "收藏微博", iconColor = if (post.favorited) Color(0xFFFF8200) else colors.onSurfaceVariant,
                    enabled = !model.actionBusy) {
                    model.actionPost = null; model.postAction(post, "favorite")
                }
                PostActionTile(Icons.Rounded.Link, "复制微博链接") {
                    copy("链接", "https://weibo.com/${post.uid}/${post.id}", "已复制微博网页链接")
                }
                PostActionTile(Icons.Rounded.PersonOutline, "查看 @${post.author} 的主页", enabled = post.uid.isNotBlank()) {
                    model.actionPost = null; model.openProfile(post)
                }
                if (!owned) PostActionTile(Icons.Outlined.Block, "屏蔽该博主", danger = true, enabled = post.uid.isNotBlank()) { model.block(post.uid) }
            }
        }
    }
    copyPost?.let { post ->
        CopyPostTextDialog(post, close = { copyPost = null }) { body ->
            copy("正文", body, "已复制微博文本至剪贴板")
            copyPost = null
        }
    }
    delete?.let { post -> ReviewAlertDialog(onDismissRequest = { delete = null }, title = { Text("确定删除微博？") }, text = { Text("删除后该条微博将不可恢复。") },
        confirmButton = { Button(colors = ButtonDefaults.buttonColors(containerColor = colors.error, contentColor = colors.onError),
            onClick = hapticClick { delete = null; model.postAction(post, "delete") }) { Text("确定删除") } },
        dismissButton = { TextButton(onClick = hapticClick { delete = null }) { Text("取消") } }) }
}

@Composable
private fun CopyPostTextDialog(post: Post, close: () -> Unit, copy: (String) -> Unit) {
    val model = LocalReview.current
    val cookie = model.sessionCookie
    var selecting by remember { mutableStateOf(false) }
    var retry by remember { mutableIntStateOf(0) }
    val available = remember(post) { post.availableFullText().takeIf(String::isNotBlank) ?: post.text.takeIf { !post.longText || post.demo } }
    var result by remember(post.id, cookie, retry) { mutableStateOf<Result<String>?>(null) }
    LaunchedEffect(post.id, cookie, retry) {
        if (available == null) {
            try { result = Result.success(model.repository.fullText(cookie, post.id)) }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { result = Result.failure(e) }
        }
    }
    val body = available ?: result?.getOrNull()
    val failed = result?.isFailure == true
    ReviewAlertDialog(onDismissRequest = close, title = { Text(if (selecting) "自由复制" else "复制微博正文") }, text = {
        if (selecting && body != null) {
            SelectionContainer(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) { Text(body) }
        } else Text(when {
            failed -> "未能获取完整正文，请重试。"
            body == null -> "正在加载全文…"
            else -> "自由复制时可长按选择要复制的文字。"
        })
    }, dismissButton = if (!selecting) {
        { TextButton(enabled = body != null, onClick = hapticClick { selecting = true }) { Text("自由复制") } }
    } else null, confirmButton = {
        TextButton(enabled = selecting || failed || body != null, onClick = hapticClick {
            when {
                selecting -> close()
                failed -> retry++
                body != null -> copy(body)
            }
        }) { Text(if (selecting) "关闭" else if (failed) "重试" else "复制全文") }
    })
}

@Composable
private fun PostActionTile(icon: ImageVector, label: String, subtitle: String? = null, danger: Boolean = false,
    iconColor: Color = MaterialTheme.colorScheme.onSurfaceVariant, enabled: Boolean = true, onClick: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    SettingsTile(headlineContent = { Text(label, fontSize = 15.sp, lineHeight = 20.25.sp, color = if (danger) colors.error else colors.onSurface) },
        supportingContent = subtitle?.let { { Text(it, fontSize = 12.5.sp, lineHeight = 17.5.sp) } },
        leadingContent = { Icon(icon, null, Modifier.size(24.dp), tint = if (danger) colors.error else iconColor) },
        modifier = Modifier.reviewClickable(enabled = enabled, onClick = onClick))
}
