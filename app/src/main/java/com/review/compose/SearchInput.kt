@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package com.review.compose

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import org.json.JSONArray
import org.json.JSONObject

fun followerCount(value: String): Long {
    val clean = value.replace(",", "").trim()
    val match = Regex("^([0-9]+(?:\\.[0-9]+)?)\\s*([万亿]?)$").matchEntire(clean) ?: return 0
    val factor = when (match.groupValues[2]) { "万" -> 10000L; "亿" -> 100000000L; else -> 1L }
    return ((match.groupValues[1].toDoubleOrNull() ?: 0.0) * factor).toLong().coerceAtLeast(0)
}
fun searchWords(root: JSONObject): List<String> {
    val data = root.optJSONObject("data") ?: return emptyList()
    val array = data.optJSONArray("query_relates") ?: data.optJSONArray("hotquery") ?: return emptyList()
    return (0 until array.length()).mapNotNull { index -> when (val item = array.opt(index)) {
        is JSONObject -> item.optString("word"); is String -> item; else -> null
    }?.trim()?.takeIf(String::isNotBlank) }.distinct()
}
fun ReviewModel.searchHistory(): List<String> = runCatching {
    val array = JSONArray(option("searchHistory:$uid", "[]")); (0 until array.length()).mapNotNull { array.opt(it) as? String }
}.getOrDefault(emptyList())
fun ReviewModel.rememberSearch(value: String) {
    if (value.isNotBlank()) setOption("searchHistory:$uid", JSONArray((listOf(value.trim()) + searchHistory()).distinct().take(20)).toString())
}
fun ReviewModel.openSearchResults(value: String) {
    val clean = value.trim(); if (clean.isBlank()) return
    rememberSearch(clean); navigate("searchResults:${android.net.Uri.encode(clean)}")
}

@Composable
fun SearchPage(query: TextFieldValue, edit: (TextFieldValue) -> Unit, search: () -> Unit, showBorder: Boolean = true,
    content: @Composable (androidx.compose.ui.unit.Dp) -> Unit) {
    val model = LocalReview.current; val colors = MaterialTheme.colorScheme
    val layer = rememberGraphicsLayer(); val backdrop = remember(layer) { ReviewBackdrop(layer) }
    val focus = LocalFocusManager.current
    val submit = { focus.clearFocus(); search() }
    val top = TopAppBarDefaults.windowInsets.asPaddingValues().calculateTopPadding() + 56.dp
    CompositionLocalProvider(LocalBackdrop provides backdrop) {
        Box(Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize().recordBackdrop(backdrop)) { content(top) }
            TopAppBar(title = {
                BasicTextField(query, edit, Modifier.fillMaxWidth().height(40.dp).background(colors.surfaceContainerHighest.copy(alpha = .5f), RoundedCornerShape(20.dp)), singleLine = true,
                    textStyle = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.5.sp, lineHeight = 18.125.sp, color = colors.onSurface), cursorBrush = SolidColor(colors.primary),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { submit() }), decorationBox = { inner ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.width(38.dp).fillMaxHeight(), contentAlignment = Alignment.Center) { Icon(Icons.Outlined.Search, null, Modifier.size(20.dp), tint = colors.onSurfaceVariant) }
                            Box(Modifier.weight(1f)) { if (query.text.isEmpty()) Text("搜索微博、话题、用户...", fontSize = 14.sp, color = colors.onSurfaceVariant.copy(alpha = .6f)); inner() }
                            if (query.text.isNotEmpty()) IconButton(onClick = hapticClick { edit(TextFieldValue()) }, modifier = Modifier.width(36.dp)) { Icon(Icons.Outlined.Close, "清空", Modifier.size(18.dp)) }
                        }
                    })
            }, navigationIcon = { IconButton(onClick = hapticClick(model::back)) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回") } },
                actions = { Text("搜索", Modifier.padding(start = 4.dp, end = 12.dp).reviewClickable(onClick = submit).padding(horizontal = 10.dp, vertical = 8.dp), color = colors.primary, fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.Bold)) },
                expandedHeight = 56.dp, colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent), modifier = Modifier.frostedBackdrop(colors.background, showBorder = showBorder))
        }
    }
}

@Composable
fun SearchScreen(model: ReviewModel, gallery: (List<Media>, Int) -> Unit) {
    var query by rememberSaveable(stateSaver = TextFieldValue.Saver) { mutableStateOf(TextFieldValue()) }
    var history by remember { mutableStateOf(model.searchHistory()) }
    var clear by remember { mutableStateOf(false) }
    var words by remember { mutableStateOf<List<String>>(emptyList()) }
    var users by remember { mutableStateOf<List<User>>(emptyList()) }
    var failed by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var retry by remember { mutableIntStateOf(0) }
    var hot by remember { mutableStateOf<List<Trend>>(emptyList()) }
    var hotLoading by remember { mutableStateOf(true) }
    var hotRetry by remember { mutableIntStateOf(0) }
    val vertical = model.bool("hotVertical")
    val colors = MaterialTheme.colorScheme
    val term = query.text.trim()
    fun submit(value: String) { model.openSearchResults(value); history = model.searchHistory() }
    fun edit(value: TextFieldValue) { query = value; words = emptyList(); users = emptyList(); failed = false; loading = value.text.isNotBlank() }
    LaunchedEffect(term, retry) {
        words = emptyList(); users = emptyList(); failed = false; loading = term.isNotEmpty()
        if (term.isEmpty()) return@LaunchedEffect
        delay(400)
        coroutineScope {
            val people = async { try { if (model.demo) emptyList() else model.repository.searchPeople(model.sessionCookie, term, 1).items } catch (e: CancellationException) { throw e } catch (_: Exception) { failed = true; emptyList() } }
            val suggestions = async { try { if (model.demo) emptyList() else searchWords(model.repository.get("/ajax/side/search", model.sessionCookie, mapOf("q" to term))) } catch (e: CancellationException) { throw e } catch (_: Exception) { emptyList() } }
            users = people.await().filter { followerCount(it.followers) >= 10000 }.take(3); words = suggestions.await(); loading = false
        }
    }
    LaunchedEffect(hotRetry) { hotLoading = true; try { hot = if (model.demo) PreviewContent.trends else model.repository.hotList(model.sessionCookie, "hot") } catch (e: CancellationException) { throw e } catch (_: Exception) { } finally { hotLoading = false } }
    SearchPage(query, ::edit, { submit(term) }) { top ->
        if (term.isNotEmpty() && loading) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        else LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = top + 12.dp, bottom = 12.dp)) {
            if (term.isNotEmpty()) {
                if (failed) item { TextButton(onClick = hapticClick { retry++ }) { Text("用户直达加载失败，点击重试") } }
                if (users.isNotEmpty()) {
                    item { Row(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Outlined.PersonPin, null, Modifier.size(18.dp), colors.primary); Spacer(Modifier.width(6.dp)); Text("用户直达", fontSize = 14.sp, fontWeight = reviewWeight(FontWeight.Bold)) } }
                    items(users, key = User::id) { user -> DirectSearchUser(user) { model.rememberSearch(user.name); history = model.searchHistory(); model.openProfile(user) } }
                    item { Spacer(Modifier.height(12.dp)); ReviewDivider(thickness = .5.dp); Spacer(Modifier.height(8.dp)) }
                }
                if (words.isNotEmpty()) item { Text("相关搜索建议", Modifier.padding(vertical = 6.dp), fontSize = 13.sp, color = colors.onSurfaceVariant) }
                items(words) { word -> ReviewListItem(headlineContent = { Text(word, fontSize = 14.5.sp) }, leadingContent = { Icon(Icons.Outlined.Search, null, Modifier.size(18.dp)) }, trailingContent = { IconButton(onClick = hapticClick { edit(TextFieldValue(word, TextRange(word.length))) }) { Icon(Icons.Outlined.NorthWest, "填入搜索框", Modifier.size(15.dp)) } }, modifier = Modifier.reviewClickable { submit(word) }, colors = ListItemDefaults.colors(containerColor = Color.Transparent)) }
                item { ReviewListItem(headlineContent = { Text("搜索 \"$term\"", color = colors.primary, fontWeight = reviewWeight(FontWeight.Bold)) }, leadingContent = { Icon(Icons.Outlined.Search, null, tint = colors.primary) }, trailingContent = { Icon(Icons.Outlined.ChevronRight, null, Modifier.size(13.dp)) }, modifier = Modifier.reviewClickable { submit(term) }, colors = ListItemDefaults.colors(containerColor = Color.Transparent)) }
            } else {
                item {
                    Row(Modifier.heightIn(min = 40.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Outlined.History, null, Modifier.size(19.dp), colors.primary); Spacer(Modifier.width(6.dp)); Text("搜索历史", Modifier.weight(1f), fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.Bold)); if (history.isNotEmpty()) IconButton(onClick = hapticClick { clear = true }) { Icon(Icons.Outlined.DeleteOutline, "清空历史", Modifier.size(20.dp)) } }
                    Spacer(Modifier.height(8.dp))
                    if (history.isEmpty()) Text("暂无搜索历史", Modifier.padding(vertical = 8.dp), fontSize = 13.sp, color = colors.onSurfaceVariant.copy(alpha = .6f))
                    else FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        history.forEach { word -> Row(Modifier.background(colors.surfaceContainerHighest.copy(alpha = .55f), RoundedCornerShape(16.dp)).border(.8.dp, colors.outlineVariant.copy(alpha = .12f), RoundedCornerShape(16.dp)).reviewClickable { submit(word) }.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(word, fontSize = 13.sp); Spacer(Modifier.width(4.dp)); Icon(Icons.Outlined.Close, "删除 $word", Modifier.reviewClickable { history = history - word; model.setOption("searchHistory:${model.uid}", JSONArray(history).toString()) }.padding(2.dp).size(13.dp), tint = colors.onSurfaceVariant.copy(alpha = .7f))
                        } }
                    }
                    Spacer(Modifier.height(20.dp)); ReviewDivider(thickness = .6.dp); Spacer(Modifier.height(16.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Spacer(Modifier.width(14.dp)); Icon(Icons.Outlined.LocalFireDepartment, null, Modifier.size(19.dp), Color(0xFFFF5722)); Spacer(Modifier.width(6.dp)); Text("热门搜索", Modifier.weight(1f), fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.Bold))
                        IconButton(onClick = hapticClick { model.setOption("hotVertical", !vertical) }) { Icon(if (vertical) Icons.Outlined.ViewList else Icons.Outlined.GridView, if (vertical) "切换为横向显示" else "切换为竖向显示", Modifier.size(20.dp)) }
                        IconButton(onClick = hapticClick { hotRetry++ }) { Icon(Icons.Outlined.Refresh, "刷新热搜", Modifier.size(20.dp)) }
                    }
                    Spacer(Modifier.height(8.dp))
                    if (hotLoading) Box(Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.5.dp) }
                    else if (hot.isEmpty()) Text("暂无热门搜索", Modifier.padding(vertical = 8.dp), fontSize = 13.sp, color = colors.onSurfaceVariant.copy(alpha = .6f))
                    else Column(Modifier.background(colors.surfaceContainerHighest.copy(alpha = .35f), RoundedCornerShape(12.dp)).padding(horizontal = 10.dp, vertical = 8.dp)) {
                        val entries = hot.take(if (vertical) 10 else 9)
                        if (vertical) { entries.forEachIndexed { i, item -> CompactHot(item, i, Modifier.fillMaxWidth().padding(vertical = 4.dp)) { submit(item.word) } }; MoreHot(Modifier.fillMaxWidth()) }
                        else (0..entries.size).toList().chunked(2).forEach { row -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { row.forEach { i -> if (i < entries.size) CompactHot(entries[i], i, Modifier.weight(1f).aspectRatio(3.8f)) { submit(entries[i].word) } else MoreHot(Modifier.weight(1f).aspectRatio(3.8f)) }; if (row.size == 1) Spacer(Modifier.weight(1f)) }; Spacer(Modifier.height(2.dp)) }
                    }
                }
            }
        }
    }
    if (clear) ReviewAlertDialog(onDismissRequest = { clear = false }, title = { Text("清空搜索历史") }, text = { Text("确定要清空全部搜索历史记录吗？") }, confirmButton = { Button(onClick = hapticClick { history = emptyList(); model.setOption("searchHistory:${model.uid}", "[]"); clear = false }) { Text("清空") } }, dismissButton = { TextButton(onClick = hapticClick { clear = false }) { Text("取消") } })
}

@Composable
fun DirectSearchUser(user: User, matched: Boolean = false, click: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    val dark = colors.background.luminance() < .5f
    Surface(Modifier.padding(top = if (matched) 0.dp else 4.dp, bottom = 4.dp)
        .then(if (matched) Modifier.glassEdgeShadow(GlassShadow(8f, 2f, Color.Black.copy(alpha = if (dark) .25f else .04f)), cornerRadius = 16.dp, clearCenter = false) else Modifier)
        .reviewClickable(onClick = click), shape = RoundedCornerShape(16.dp), color = if (matched && dark) Color(0xFF1E1F24) else colors.surfaceContainerHighest.copy(alpha = if (matched) .55f else .45f), border = BorderStroke(.8.dp, (if (dark) Color.White else Color.Black).copy(alpha = .12f))) {
        Row(Modifier.padding(if (matched) 14.8.dp else 12.8.dp), verticalAlignment = Alignment.CenterVertically) {
            Avatar(user.name, user.avatar, Modifier.size(if (matched) 50.dp else 48.dp), user.isVerified, user.verifiedType, shareWithProfile = true); Spacer(Modifier.width(if (matched) 14.dp else 12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) { Text(user.name, Modifier.weight(1f, false), fontSize = if (matched) 15.5.sp else 15.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis); if (user.isVerified) { Spacer(Modifier.width(4.dp)); Icon(Icons.Filled.Verified, null, Modifier.size(15.dp), if (user.verifiedType == 0) Color(0xFFFFB300) else Color(0xFF00B0FF)) } }
                Spacer(Modifier.height(2.dp)); val description = user.verified.ifBlank { user.description }
                if (description.isNotBlank()) Text(description, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, color = colors.onSurfaceVariant)
                Spacer(Modifier.height(2.dp)); Row { Text("粉丝 ${compactCount(user.followers)}", fontSize = 11.5.sp, color = colors.primary, fontWeight = reviewWeight(FontWeight.SemiBold)); if ((user.posts.toLongOrNull() ?: 0) > 0) Text(" · 微博 ${user.posts}", fontSize = 11.5.sp, color = colors.onSurfaceVariant) }
            }
            if (matched) Row(Modifier.background(colors.primaryContainer, RoundedCornerShape(16.dp)).padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) { Text("主页", fontSize = 12.sp, fontWeight = reviewWeight(FontWeight.Bold), color = colors.onPrimaryContainer); Icon(Icons.Outlined.ChevronRight, null, Modifier.size(10.dp), colors.onPrimaryContainer) }
            else Icon(Icons.Outlined.ChevronRight, null, Modifier.size(14.dp), colors.onSurfaceVariant.copy(alpha = .6f))
        }
    }
}
@Composable
private fun CompactHot(item: Trend, index: Int, modifier: Modifier, click: () -> Unit) {
    Row(modifier.reviewClickable(onClick = click).padding(horizontal = 4.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("${index + 1}", Modifier.width(20.dp), fontSize = 14.sp, color = listOf(Color(0xFFFF2442), Color(0xFFFF7700), Color(0xFFFFB300)).getOrElse(index) { MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .6f) }); Spacer(Modifier.width(4.dp))
        Text(item.word, Modifier.weight(1f), fontSize = 13.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (item.label.isNotBlank()) { Spacer(Modifier.width(4.dp)); TrendBadge(item.label) }
    }
}
@Composable
private fun MoreHot(modifier: Modifier) {
    val model = LocalReview.current; val colors = MaterialTheme.colorScheme
    Row(modifier.padding(vertical = 2.dp).background(colors.primaryContainer.copy(alpha = .6f), RoundedCornerShape(8.dp)).reviewClickable { model.navigate("trends") }.padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
        Icon(Icons.Outlined.LocalFireDepartment, null, Modifier.size(15.dp), colors.primary); Spacer(Modifier.width(4.dp)); Text("更多热搜", fontSize = 13.sp, fontWeight = reviewWeight(FontWeight.Bold), color = colors.primary); Spacer(Modifier.width(2.dp)); Icon(Icons.Outlined.ChevronRight, null, Modifier.size(11.dp), colors.primary)
    }
}
