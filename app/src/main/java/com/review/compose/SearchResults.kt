@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
package com.review.compose

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.rounded.Diamond
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import org.json.JSONObject

@Composable
fun SearchResultsScreen(initial: String, gallery: (List<Media>, Int) -> Unit) {
    val model = LocalReview.current
    var query by rememberSaveable(stateSaver = TextFieldValue.Saver) { mutableStateOf(TextFieldValue(initial, TextRange(initial.length))) }
    var submitted by rememberSaveable { mutableStateOf(initial) }
    var revision by remember { mutableIntStateOf(0) }
    var selected by rememberSaveable { mutableIntStateOf(0) }
    val tabs = listOf("综合", "实时", "用户", "超话", "图片", "视频", "关注", "热门", "评论", "话题", "地点", "商品")
    val tab = tabs[selected]
    var posts by remember(submitted, revision) { mutableStateOf<List<Post>>(emptyList()) }
    var users by remember(submitted, revision) { mutableStateOf<List<User>>(emptyList()) }
    var topics by remember(submitted, revision) { mutableStateOf<List<JSONObject>>(emptyList()) }
    var header by remember(submitted, revision) { mutableStateOf<TopicHeader?>(null) }
    var topping by remember(submitted, revision) { mutableStateOf<Post?>(null) }
    DisposableEffect(model, submitted, revision) {
        val update: (String, Post?) -> Unit = { id, changed ->
            posts = posts.mapNotNull { if (it.id == id) changed else it }
            if (topping?.id == id) topping = changed
        }
        model.postObservers.add(update)
        onDispose { model.postObservers.remove(update) }
    }
    var next by remember(submitted, revision) { mutableStateOf("1") }
    var userNext by remember(submitted, revision) { mutableStateOf("1") }
    var busy by remember(submitted, revision) { mutableStateOf(false) }
    var refreshing by remember(submitted, revision) { mutableStateOf(false) }
    var error by remember(submitted, revision) { mutableStateOf<String?>(null) }
    var usersFailed by remember(submitted, revision) { mutableStateOf(false) }
    var retryRefresh by remember(submitted, revision) { mutableStateOf(true) }
    var retryFromPull by remember(submitted, revision) { mutableStateOf(false) }
    val currentIdentity by rememberUpdatedState(submitted to revision)
    val scope = rememberCoroutineScope()
    val state = rememberLazyListState()
    suspend fun fetch(refresh: Boolean = false, fromPull: Boolean = false) {
        if (busy) return
        val identity = submitted to revision
        val peopleOnly = !refresh && tab == "用户"
        val cursor = if (refresh) "1" else if (peopleOnly) userNext else next
        if (cursor == "0") return
        retryRefresh = refresh; retryFromPull = fromPull
        busy = true; refreshing = fromPull; error = null
        try {
            if (peopleOnly) {
                val result = model.repository.searchPeople(model.sessionCookie, submitted, cursor.toInt())
                if (currentIdentity != identity) return
                val merged = (users + result.items).distinctBy(User::id)
                userNext = if (merged.size > users.size && result.next != cursor) result.next else "0"; users = merged; usersFailed = false
            } else coroutineScope {
                val people = async {
                    if (!refresh || model.demo) null else try { model.repository.searchPeople(model.sessionCookie, submitted, 1) }
                    catch (e: CancellationException) { throw e } catch (_: Exception) { if (currentIdentity == identity) usersFailed = true; null }
                }
                val communities = async {
                    if (!refresh || model.demo) null else try { model.repository.topics(model.sessionCookie, submitted, 1).items }
                    catch (e: CancellationException) { throw e } catch (_: Exception) { null }
                }
                val content = async {
                    try { if (model.demo) SearchDetails(Page(PreviewContent.posts.filter { it.text.contains(submitted) }), null, null) else model.repository.searchDetails(model.sessionCookie, submitted, cursor.toInt()) }
                    catch (e: CancellationException) { throw e } catch (e: Exception) { if (currentIdentity == identity) error = e.message ?: "搜索失败"; null }
                }
                val result = content.await(); val peopleResult = people.await(); val communityResult = communities.await()
                if (currentIdentity != identity) return@coroutineScope
                val showNewHeader = refresh && !fromPull && !state.isScrollInProgress &&
                    state.firstVisibleItemIndex == 0 && state.firstVisibleItemScrollOffset == 0
                if (peopleResult != null) { users = peopleResult.items; userNext = peopleResult.next; usersFailed = false }
                if (communityResult != null) topics = communityResult
                if (result != null) {
                    val merged = ((if (refresh) emptyList() else posts) + result.page.items).distinctBy(Post::id)
                    next = if ((refresh || merged.size > posts.size) && result.page.next != cursor) result.page.next else "0"
                    posts = merged
                    if (refresh) { header = result.header; topping = result.topping }
                }
                // Override the tabs' stable-key anchor when first-page cards arrive above it.
                if (showNewHeader || (fromPull && result != null)) state.requestScrollToItem(0)
            }
        } catch (e: CancellationException) { throw e } catch (e: Exception) { if (currentIdentity == identity) { error = e.message; if (peopleOnly) usersFailed = true } }
        finally { if (currentIdentity == identity) { busy = false; refreshing = false } }
    }
    LaunchedEffect(submitted, revision) { state.scrollToItem(0); fetch(true) }
    val end by remember { derivedStateOf { val layout = state.layoutInfo; layout.visibleItemsInfo.lastOrNull()?.index?.let { it >= layout.totalItemsCount - 4 } ?: false } }
    LaunchedEffect(end, tab, posts.size, users.size) { if (end && error == null && !usersFailed && ((tab == "用户" && users.isNotEmpty()) || (tab != "用户" && tab != "超话" && posts.isNotEmpty()))) fetch() }
    SearchPage(query, { query = it }, { if (query.text.isNotBlank()) { submitted = query.text.trim(); model.rememberSearch(submitted); revision++ } }, showBorder = false) { top ->
        ReviewRefresh(refreshing, { scope.launch { fetch(refresh = true, fromPull = true) } }, Modifier.padding(top = top),
            failed = error != null, topInset = 0.dp, enabled = !busy || refreshing) {
            LazyColumn(Modifier.fillMaxSize(), state, contentPadding = PaddingValues(bottom = 24.dp)) {
                header?.let { topic -> item("topic-header") { SearchTopicHeader(topic, gallery) } }
                if (selected == 0) {
                    users.firstOrNull()?.takeIf { it.id != header?.host?.id }?.let { user -> item("matched-user") { Box(Modifier.padding(start = 14.dp, top = 10.dp, end = 14.dp)) { DirectSearchUser(user, matched = true) { model.openProfile(user) } } } }
                    topics.firstOrNull()?.let { topic -> item("matched-topic") { SearchTopicRow(topic, matched = true) } }
                }
                stickyHeader("tabs") {
                    PrimaryScrollableTabRow(selected, minTabWidth = 0.dp, edgePadding = 0.dp, containerColor = MaterialTheme.colorScheme.background) {
                        tabs.forEachIndexed { index, title -> Tab(index == selected, hapticClick { selected = index }, modifier = Modifier.height(48.dp), unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant) {
                            Text(title, Modifier.padding(horizontal = 14.dp), fontSize = if (index == selected) 14.5.sp else 14.sp,
                                maxLines = 1, fontWeight = reviewWeight(if (index == selected) FontWeight.Bold else FontWeight.Normal))
                        } }
                    }
                }
                when (tab) {
                    "用户" -> {
                        items(users, key = { "user:${it.id}" }) { user -> ReviewListItem(headlineContent = { Text(user.name, fontWeight = reviewWeight(FontWeight.Bold)) }, supportingContent = { Text(user.verified.ifBlank { "粉丝 ${user.followers}" }) }, leadingContent = { Avatar(user.name, user.avatar, verified = user.isVerified, verifiedType = user.verifiedType, shareWithProfile = true) }, trailingContent = { Icon(Icons.Outlined.ChevronRight, null, Modifier.size(14.dp)) }, modifier = Modifier.reviewClickable { model.openProfile(user) }) }
                        if (usersFailed) item { TextButton(onClick = hapticClick { scope.launch { fetch(users.isEmpty()) } }) { Text("用户搜索暂时不可用，点击重试") } }
                        else if (!busy && users.isEmpty()) item { SearchEmpty("暂无相关用户") }
                    }
                    "超话" -> { items(topics, key = { "topic:${topicId(it)}" }) { SearchTopicRow(it) }; if (topics.isEmpty() && !busy) item { SearchEmpty("暂无\"$submitted\"相关超话", topic = true) } }
                    "图片" -> {
                        val pictures = posts.flatMap { post -> post.images.mapIndexed { index, picture -> Triple(post, index, picture) } }.chunked(3)
                        itemsIndexed(pictures, key = { index, _ -> "pictures:$index" }) { _, row -> Row(Modifier.padding(horizontal = 12.dp, vertical = 3.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            row.forEach { (post, index, picture) -> MediaImage(picture, "${post.author}的图片", Modifier.weight(1f).aspectRatio(1f).clip(RoundedCornerShape(8.dp)).reviewClickable { gallery(post.images, index) }) }
                            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                        } }
                        if (pictures.isEmpty() && !busy) item { SearchEmpty("暂无图片内容") }
                    }
                    else -> {
                        val display = if (selected == 0) (listOfNotNull(topping) + posts).distinctBy(Post::id) else searchDisplayPosts(posts, tab)
                        items(display, key = { "post:${it.id}" }) { PostRow(it, gallery) }
                        if (display.isEmpty() && !busy && error == null) item { SearchEmpty("暂无\"$tab\"相关内容") }
                    }
                }
                if (busy) item { Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp)) } }
                error?.let { item { ErrorNotice(it) { scope.launch { fetch(retryRefresh, retryFromPull) } } } }
                if (!busy && error == null && tab != "超话" && (if (tab == "用户") userNext else next) != "0") item { TextButton(onClick = hapticClick { scope.launch { fetch() } }, modifier = Modifier.fillMaxWidth()) { Text("加载更多") } }
            }
        }
    }
}

@Composable private fun SearchEmpty(text: String, topic: Boolean = false) {
    Column(Modifier.fillMaxWidth().heightIn(min = 240.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(if (topic) Icons.Outlined.Diamond else Icons.Outlined.SearchOff, null, Modifier.size(54.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .4f))
        Spacer(Modifier.height(12.dp)); Text(text, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
fun topicId(item: JSONObject) = item.optString("page_id").ifBlank { item.optString("oid").ifBlank { item.optString("topic_id") } }.removePrefix("1022:")
@Composable fun SearchTopicRow(item: JSONObject, matched: Boolean = false) {
    val model = LocalReview.current; val colors = MaterialTheme.colorScheme
    val title = item.optString("title").let { if (it.endsWith("超话")) it else "${it}超话" }
    val click = { model.openTopic(item) }
    val dark = colors.background.luminance() < .5f
    Surface(Modifier.padding(start = if (matched) 14.dp else 0.dp, top = if (matched) 6.dp else 0.dp, end = if (matched) 14.dp else 0.dp, bottom = if (matched) 8.dp else 0.dp)
        .then(if (matched) Modifier.glassEdgeShadow(GlassShadow(8f, 2f, Color.Black.copy(alpha = if (dark) .25f else .04f)), cornerRadius = 16.dp, clearCenter = false) else Modifier)
        .reviewClickable(onClick = click), shape = RoundedCornerShape(if (matched) 16.dp else 0.dp), color = if (matched) { if (dark) Color(0xFF1E1F24) else colors.surfaceContainerHighest.copy(alpha = .55f) } else Color.Transparent,
        border = if (matched) BorderStroke(.8.dp, (if (dark) Color.White else Color.Black).copy(alpha = .12f)) else null) {
        Row(Modifier.padding(horizontal = if (matched) 14.8.dp else 16.dp, vertical = if (matched) 14.8.dp else 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(if (matched) 50.dp else 48.dp).clip(RoundedCornerShape(12.dp)).background(colors.primaryContainer), contentAlignment = Alignment.Center) {
                val image = secureImage(item.optString("image")); if (image.isNotBlank()) MediaImage(Media(image), title, Modifier.fillMaxSize()) else Icon(Icons.Rounded.Diamond, null, tint = colors.onPrimaryContainer)
            }
            Spacer(Modifier.width(14.dp)); Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) { Text(title, Modifier.weight(1f, false), fontSize = if (matched) 15.5.sp else 16.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis); Spacer(Modifier.width(4.dp)); Icon(Icons.Rounded.Diamond, null, Modifier.size(15.dp), colors.primary) }
                if (item.optString("description").isNotBlank()) Text(plainText(item.optString("description")), Modifier.padding(top = 3.dp), maxLines = if (matched) 1 else 2, fontSize = if (matched) 12.sp else 12.5.sp, color = colors.onSurfaceVariant, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.width(6.dp)); Row(Modifier.background(if (matched) colors.primary else colors.secondaryContainer, RoundedCornerShape(16.dp)).padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("进入超话", fontSize = 12.sp, fontWeight = reviewWeight(FontWeight.Bold), color = if (matched) colors.onPrimary else colors.onSecondaryContainer)
                if (matched) Icon(Icons.Outlined.ChevronRight, null, Modifier.size(10.dp), colors.onPrimary)
            }
        }
    }
}

@Composable fun SearchTopicHeader(topic: TopicHeader, gallery: (List<Media>, Int) -> Unit) {
    val colors = MaterialTheme.colorScheme; val model = LocalReview.current; val context = LocalContext.current
    val dark = colors.background.luminance() < .5f
    val title = "#${topic.title.trim('#')}#"
    Surface(Modifier.padding(horizontal = 14.dp, vertical = 8.dp).glassEdgeShadow(GlassShadow(8f, 2f, Color.Black.copy(alpha = if (dark) .2f else .04f)), cornerRadius = 16.dp, clearCenter = false), color = if (dark) Color(0xFF1E1F24) else colors.surfaceContainerHighest.copy(alpha = .55f), shape = RoundedCornerShape(16.dp), border = BorderStroke(.8.dp, colors.outlineVariant.copy(alpha = if (dark) .2f else .4f))) {
        Column(Modifier.padding(12.8.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                val image = topic.image.ifBlank { topic.host?.avatar.orEmpty() }
                Box(Modifier.size(68.dp).clip(RoundedCornerShape(12.dp)).background(Brush.linearGradient(listOf(colors.primaryContainer, colors.secondaryContainer))).reviewClickable(enabled = topic.image.isNotBlank()) { gallery(listOf(Media(topic.image)), 0) }, contentAlignment = Alignment.Center) {
                    if (image.isBlank()) Text(topic.title.take(1).ifBlank { "#" }, fontSize = 24.sp, fontWeight = reviewWeight(FontWeight.Bold), color = colors.onPrimaryContainer) else MediaImage(Media(image), title, Modifier.fillMaxSize())
                }
                Spacer(Modifier.width(12.dp)); Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(title, Modifier.weight(1f), fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.Bold), letterSpacing = .2.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Spacer(Modifier.width(6.dp)); Row(Modifier.background(colors.primary.copy(alpha = .1f), RoundedCornerShape(12.dp)).reviewClickable {
                            val url = topic.url.ifBlank { "https://s.weibo.com/weibo?q=${Uri.encode(title)}" }
                            (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("话题", url)); model.notice = "已复制话题链接到剪贴板"
                        }.padding(horizontal = 8.dp, vertical = 3.5.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Outlined.Share, null, Modifier.size(12.5.dp), colors.primary); Spacer(Modifier.width(3.dp)); Text("分享", fontSize = 11.5.sp, fontWeight = reviewWeight(FontWeight.SemiBold), color = colors.primary) }
                    }
                    Spacer(Modifier.height(5.dp)); Row { Text("阅读量 ${topicCount(topic.reads)}", fontSize = 12.sp, color = colors.onSurfaceVariant); Spacer(Modifier.width(12.dp)); Text("讨论量 ${topicCount(topic.mentions)}", fontSize = 12.sp, color = colors.onSurfaceVariant) }
                    topic.host?.takeIf { it.name.isNotBlank() }?.let { host -> Row(Modifier.padding(top = 4.dp).reviewClickable(enabled = host.id.isNotBlank()) { model.navigate("profile:${host.id}") }, verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Outlined.VerifiedUser, null, Modifier.size(13.dp), colors.primary); Spacer(Modifier.width(4.dp)); Text("主持人: ${host.name}", Modifier.weight(1f, false), fontSize = 11.5.sp, fontWeight = reviewWeight(FontWeight.SemiBold), color = colors.primary, maxLines = 1, overflow = TextOverflow.Ellipsis); Icon(Icons.Outlined.ChevronRight, null, Modifier.size(13.dp), colors.primary.copy(alpha = .7f)) } }
                }
            }
            if (topic.summary.isNotBlank()) {
                Spacer(Modifier.height(10.dp)); val bold = reviewWeight(FontWeight.Bold)
                Text(androidx.compose.ui.text.buildAnnotatedString { pushStyle(androidx.compose.ui.text.SpanStyle(color = colors.primary, fontWeight = bold)); append("导语："); pop(); append(topic.summary) }, Modifier.fillMaxWidth().background(colors.surfaceContainerLowest.copy(alpha = if (dark) .4f else .6f), RoundedCornerShape(10.dp)).padding(horizontal = 10.dp, vertical = 7.dp), fontSize = 12.5.sp, lineHeight = 16.875.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}
