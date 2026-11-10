@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
package com.review.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.material.icons.rounded.Diamond
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import org.json.JSONObject
import java.io.IOException

suspend fun Repository.topics(cookie: String, query: String, page: Int): Page<JSONObject> {
    val root = get("/ajax/stopic/list", cookie, mapOf("keyword" to query, "page" to "$page"))
    val topics = responseArray(root, "list", "data").objects()
        .filter { it.optString("title").isNotBlank() && topicId(it).isNotBlank() }
    return Page(topics, if (topics.isEmpty()) "0" else "${page + 1}")
}
@Composable
fun TopicResults(query: String) {
    val model = LocalReview.current
    val colors = MaterialTheme.colorScheme
    val cookie = model.sessionCookie
    if (model.restoringWebSession && cookie.isBlank()) {
        Box(Modifier.fillMaxSize().padding(top = LocalContentTop.current), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }
    PagedContent("topics:$query:${model.uid}:${model.demo}:${cookie.isNotBlank()}", { cursor ->
        if (model.demo) Page(emptyList()) else {
            val page = cursor.toInt().coerceAtLeast(1)
            val result = model.repository.topics(cookie, query, page)
            if (page == 1 && query == "超话" && result.items.isEmpty()) {
                delay(300)
                model.repository.topics(cookie, query, page)
            } else result
        }
    }, ::topicId, empty = {
        Column(Modifier.fillMaxWidth().heightIn(min = 420.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Outlined.Diamond, null, Modifier.size(56.dp), tint = colors.outlineVariant)
            Spacer(Modifier.height(12.dp)); Text("暂未找到相关超话", fontSize = 15.sp, color = colors.onSurfaceVariant)
        }
    }) { item ->
        val title = item.optString("title")
        val open = { model.openTopic(item) }
        Row(Modifier.fillMaxWidth().reviewClickable(onClick = open).padding(horizontal = 20.dp, vertical = 6.dp).heightIn(min = 72.dp), verticalAlignment = Alignment.CenterVertically) {
            Avatar(title, secureImage(item.optString("image")), Modifier.size(48.dp))
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Diamond, null, Modifier.size(16.dp), tint = Color(0xFFFF8200)); Spacer(Modifier.width(4.dp))
                    Text(title, fontSize = 15.5.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Text(plainText(item.optString("description")).ifBlank { "微博热门超话社区" }, Modifier.padding(top = 4.dp), fontSize = 13.sp, lineHeight = 18.2.sp, color = colors.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.width(16.dp))
            FilledTonalButton(onClick = hapticClick(open), contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp), modifier = Modifier.height(32.dp)) { Text("进入", fontSize = 13.sp, fontWeight = reviewWeight(FontWeight.Bold)) }
        }
        ReviewDivider(Modifier.padding(horizontal = 16.dp), thickness = .5.dp, color = colors.outlineVariant.copy(alpha = .3f))
    }
}
@Composable
fun TopicsScreen() {
    val model = LocalReview.current
    val colors = MaterialTheme.colorScheme
    val focus = LocalFocusManager.current
    var category by rememberSaveable { mutableStateOf("推荐") }
    var query by rememberSaveable { mutableStateOf("") }
    var submitted by rememberSaveable { mutableStateOf("超话") }
    val top = TopAppBarDefaults.windowInsets.asPaddingValues().calculateTopPadding() + 56.dp
    val layer = rememberGraphicsLayer(); val backdrop = remember(layer) { ReviewBackdrop(layer) }
    CompositionLocalProvider(LocalBackdrop provides backdrop) {
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().recordBackdrop(backdrop)) { CompositionLocalProvider(LocalContentTop provides top + 112.dp) { TopicResults(submitted) } }
        Column(Modifier.fillMaxWidth().frostedBackdrop(colors.background, showBorder = false)) {
            TopAppBar(title = { Text("超话中心", Modifier.padding(start = 16.dp), fontSize = 18.sp, fontWeight = reviewWeight(FontWeight.Bold)) }, navigationIcon = { IconButton(onClick = hapticClick(model::back)) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回") } }, expandedHeight = 56.dp, colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent))
            Box(Modifier.padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 10.dp).fillMaxWidth().height(48.dp).background(colors.surfaceContainerHighest.copy(alpha = .45f), RoundedCornerShape(24.dp))) {
                BasicTextField(query, { query = it }, Modifier.fillMaxSize(), singleLine = true,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.onSurface), cursorBrush = SolidColor(colors.primary),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { if (query.isNotBlank()) { submitted = query.trim(); focus.clearFocus() } }),
                    decorationBox = { input -> Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) { Icon(Icons.Outlined.Search, null, Modifier.size(20.dp), tint = colors.onSurfaceVariant) }
                        Box(Modifier.weight(1f)) { if (query.isEmpty()) Text("搜索感兴趣的超话社区...", fontSize = 14.sp, color = colors.onSurfaceVariant); input() }
                        if (query.isNotEmpty()) IconButton(onClick = hapticClick { query = ""; submitted = if (category == "推荐") "超话" else category }) { Icon(Icons.Outlined.Clear, "清空", Modifier.size(18.dp)) }
                        else Spacer(Modifier.width(16.dp))
                    } })
            }
            LazyRow(Modifier.height(38.dp), contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                items(listOf("推荐", "游戏", "电竞", "动漫", "体育", "明星", "红人", "影视综", "AI", "读书", "生活", "学习")) { name ->
                    val selected = category == name
                    Surface(onClick = hapticClick { if (!selected) { category = name; query = ""; submitted = if (name == "推荐") "超话" else name } }, shape = RoundedCornerShape(18.dp),
                        color = if (selected) colors.primaryContainer else colors.surfaceContainerHighest.copy(alpha = .35f), border = BorderStroke(1.dp, if (selected) colors.primary else Color.Transparent)) {
                        Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                            if (selected) { Icon(Icons.Outlined.Check, null, Modifier.size(18.dp), tint = colors.onPrimaryContainer); Spacer(Modifier.width(8.dp)) }
                            Text(name, fontSize = 13.sp, fontWeight = reviewWeight(if (selected) FontWeight.Bold else FontWeight.Normal), color = if (selected) colors.onPrimaryContainer else colors.onSurface)
                        }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
    }
}
@Composable
fun TopicScreen(requestedId: String, gallery: (List<Media>, Int) -> Unit, route: ReviewRoute) {
    val model = LocalReview.current
    var id by rememberSaveable(requestedId) { mutableStateOf(topicPageId(requestedId) ?: requestedId) }
    val resolving = topicPageId(id) == null
    var resolveRetry by remember(requestedId) { mutableIntStateOf(0) }
    val colors = MaterialTheme.colorScheme
    var header by remember(id) { mutableStateOf(route.topic ?: JSONObject()) }
    val title = header.optString("title").ifBlank { header.optString("nick") }
    val description = plainText(header.optString("description").ifBlank { header.optString("desc") })
    val avatar = secureImage(header.optString("image").ifBlank { header.optString("portrait").ifBlank { header.optString("avatar").ifBlank { header.optString("pic") } } })
    var followed by remember(id) { mutableStateOf(false) }
    var checked by remember(id) { mutableStateOf(false) }
    var channels by remember(id) { mutableStateOf(listOf("热门" to "${id}_-_recommend", "最新" to "${id}_-_feed", "精华" to "${id}_-_soul")) }
    var channel by rememberSaveable(id) { mutableStateOf("${id}_-_recommend") }
    var headerError by remember(id) { mutableStateOf<String?>(null) }
    var headerHeight by remember { mutableStateOf(0.dp) }
    val density = LocalDensity.current
    val feeds = remember(id, model.uid) { mutableMapOf<String, PagedContentState<Post>>() }
    LaunchedEffect(id, model.uid, model.sessionCookie.isNotBlank(), resolveRetry) {
        if (model.demo) return@LaunchedEffect
        headerError = null
        try {
            if (resolving) {
                val query = topicName(title).ifBlank { title.trim() }
                check(query.isNotBlank()) { "超话信息不完整，请从超话中心重新进入" }
                val item = model.repository.topics(model.sessionCookie, query, 1).items.firstOrNull {
                    topicPageId(topicId(it)) != null && topicName(it.optString("title")).equals(query, ignoreCase = true)
                } ?: error("暂未找到「$query」超话")
                route.topic = item
                id = checkNotNull(topicPageId(topicId(item)))
                return@LaunchedEffect
            }
            val root = model.repository.api.get(ApiClient.DESKTOP + "/ajax_proxy/chaohua/page/extend", model.sessionCookie, mapOf("page_id" to id, "show_recommend" to "1"))
            val data = root.optJSONObject("data") ?: root
            followed = data.optBoolean("is_followed"); checked = data.optBoolean("is_checked")
        } catch (e: CancellationException) { throw e } catch (e: Exception) { headerError = e.message }
    }
    if (resolving) {
        Box(Modifier.fillMaxSize().padding(top = LocalContentTop.current), contentAlignment = Alignment.Center) {
            val failure = headerError
            if (failure != null || model.demo) ErrorNotice(failure ?: "预览模式暂无法查询超话") { resolveRetry++ }
            else CircularProgressIndicator()
        }
        return
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
    val available = maxHeight
    PagedContent("topic:$id:$channel:${model.uid}", { cursor ->
        val page = cursor.toInt().coerceAtLeast(1)
        if (model.demo) Page(emptyList()) else {
            val root = model.repository.api.get(ApiClient.DESKTOP + "/ajax_proxy/chaohua/page", model.sessionCookie, mapOf("containerid" to channel, "page" to "$page"))
            root.optJSONObject("header")?.optJSONObject("data")?.let { data ->
                val merged = JSONObject(header.toString())
                data.keys().forEach { key -> if (merged.optString(key).isBlank()) merged.put(key, data.opt(key)) }
                header = merged; route.topic = merged
                if (data.has("follow_relation")) followed = data.optInt("follow_relation") == 1
            }
            val nextChannels = root.optJSONObject("channelInfo")?.optJSONArray("channels").objects().mapNotNull {
                if (it.optString("title").isBlank() || it.optString("flowId").isBlank()) null else it.optString("title") to it.optString("flowId")
            }
            if (nextChannels.isNotEmpty()) channels = nextChannels
            val posts = model.repository.parsePosts(model.sessionCookie, topicStatusData(root))
            Page(posts, if (posts.isEmpty()) "0" else "${page + 1}")
        }
    }, Post::id, header = {
        item {
            Surface(Modifier.onSizeChanged { headerHeight = with(density) { it.height.toDp() } }.padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 12.dp), shape = RoundedCornerShape(16.dp), color = colors.surfaceContainerHighest.copy(alpha = .35f), border = BorderStroke(.8.dp, colors.outlineVariant.copy(alpha = .3f))) {
            Column(Modifier.padding(14.8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(56.dp).clip(RoundedCornerShape(12.dp)).background(colors.surfaceContainerHighest), contentAlignment = Alignment.Center) {
                        if (avatar.isNotBlank()) MediaImage(Media(avatar), title, Modifier.fillMaxSize()) else Icon(Icons.Rounded.Diamond, null, Modifier.size(28.dp), tint = Color(0xFFFF8200))
                    }
                    Spacer(Modifier.width(14.dp))
                    Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Diamond, null, Modifier.size(18.dp), tint = Color(0xFFFF8200)); Spacer(Modifier.width(4.dp))
                        Text(title, fontSize = 17.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                if (description.isNotBlank()) Text(description, Modifier.padding(top = 10.dp), fontSize = 12.5.sp, lineHeight = 16.875.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, color = colors.onSurfaceVariant)
                headerError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = hapticClick { model.saveDraft("#$title[超话]# "); model.navigate("draft") }, Modifier.weight(1f).height(40.dp).padding(vertical = 4.dp), shape = RoundedCornerShape(12.dp), border = BorderStroke(1.dp, colors.outline), colors = ButtonDefaults.outlinedButtonColors(contentColor = colors.primary), contentPadding = PaddingValues(vertical = 6.dp)) {
                        Icon(Icons.Outlined.EditNote, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("发帖", fontSize = 13.sp, fontWeight = reviewWeight(FontWeight.Bold))
                    }
                    FilledTonalButton(modifier = Modifier.weight(1f).height(40.dp).padding(vertical = 4.dp), shape = RoundedCornerShape(12.dp), contentPadding = PaddingValues(vertical = 8.dp), enabled = !model.actionBusy, onClick = hapticClick { model.mutate {
                        val root = model.repository.api.post(ApiClient.DESKTOP + "/ajax_proxy/chaohua/page/${if (followed) "unfollow" else "follow"}", model.sessionCookie, mapOf("page_id" to id), verify = false)
                        if (root.optInt("code") !in setOf(10000, 100000)) throw IOException(root.optString("msg", "操作未完成"))
                        followed = !followed
                    } }) { Text(if (followed) "已关注" else "关注", fontSize = 13.sp, fontWeight = reviewWeight(FontWeight.Bold), color = if (followed) colors.onSecondaryContainer else colors.primary) }
                    Button(modifier = Modifier.weight(1f).height(40.dp).padding(vertical = 4.dp), shape = RoundedCornerShape(12.dp), contentPadding = PaddingValues(vertical = 8.dp), colors = ButtonDefaults.buttonColors(containerColor = if (checked) colors.surfaceContainerHighest else colors.primary, contentColor = if (checked) colors.onSurfaceVariant else colors.onPrimary), enabled = !model.actionBusy, onClick = hapticClick { if (!checked) model.mutate {
                        val root = model.repository.api.post(ApiClient.DESKTOP + "/ajax_proxy/chaohua/page/checkin", model.sessionCookie,
                            mapOf("scene_id" to "pc_checkin", "page_id" to id, "timezone" to "Asia/Shanghai", "lang" to "zh-CN", "plat" to "Win32"), verify = false)
                        if (root.optInt("code") !in setOf(10000, 100000)) throw IOException(root.optString("msg", "签到未成功"))
                        checked = true
                        val result = root.optJSONObject("data")
                        model.notice = "🎉 签到成功！" + (result?.optString("rank")?.takeIf(String::isNotBlank)?.let { " 获得第 $it 名" } ?: "") + (result?.optString("score")?.takeIf(String::isNotBlank)?.let { "，经验值 +$it" } ?: "")
                    } }) { if (checked) { Icon(Icons.Outlined.Check, null, Modifier.size(16.dp)); Spacer(Modifier.width(2.dp)) }; Text(if (checked) "已签到" else "签到", fontSize = 13.sp, fontWeight = reviewWeight(FontWeight.Bold)) }
                }
            }
            }
        }
        stickyHeader {
            Column(Modifier.fillMaxWidth().background(colors.background)) {
                PrimaryScrollableTabRow(channels.indexOfFirst { it.second == channel }.coerceAtLeast(0), minTabWidth = 0.dp, edgePadding = 0.dp, containerColor = colors.background) {
                    channels.forEach { (label, flow) -> Tab(channel == flow, hapticClick { channel = flow }, Modifier.height(48.dp), selectedContentColor = colors.primary, unselectedContentColor = colors.onSurfaceVariant,
                        text = { Text(label, fontSize = 14.5.sp, fontWeight = reviewWeight(if (channel == flow) FontWeight.Bold else FontWeight.Normal)) }) }
                }
                ReviewDivider(thickness = .5.dp)
            }
        }
    }, retained = feeds.getOrPut(channel) { PagedContentState() }, empty = {
        Column(Modifier.fillMaxWidth().height((available - headerHeight - 49.dp).coerceAtLeast(160.dp)), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Outlined.Feed, null, Modifier.size(48.dp), tint = colors.onSurfaceVariant.copy(alpha = .5f))
            Spacer(Modifier.height(12.dp)); Text("暂无【${channels.firstOrNull { it.second == channel }?.first.orEmpty()}】相关动态", color = colors.onSurfaceVariant)
        }
    }) { PostRow(it, gallery) }
    }
}

fun topicStatusData(root: JSONObject): List<JSONObject> {
    val items = root.optJSONArray("items").objects().mapNotNull { it.optJSONObject("data") }.filter { (it.has("id") || it.has("idstr")) && (it.has("text") || it.has("text_raw")) }
    return items.ifEmpty { (root.optJSONArray("statuses") ?: root.optJSONObject("data")?.optJSONArray("statuses")).objects() }
}
