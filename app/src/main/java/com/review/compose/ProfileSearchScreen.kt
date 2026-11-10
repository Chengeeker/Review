@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Clear
import androidx.compose.material.icons.rounded.ManageSearch
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.SearchOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun ProfileSearchScreen(id: String, gallery: (List<Media>, Int) -> Unit) {
    val model = LocalReview.current
    val colors = MaterialTheme.colorScheme
    val route = LocalReviewRoute.current
    val name = (route?.profile ?: model.profileUser)?.takeIf { it.id == id }?.name ?: id
    var query by rememberSaveable(id) { mutableStateOf("") }
    var submitted by rememberSaveable(id) { mutableStateOf("") }
    var revision by rememberSaveable(id) { mutableIntStateOf(0) }
    val identity = "profileSearch:$id:$submitted:${model.uid}:$revision"
    val focus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val layer = rememberGraphicsLayer()
    val backdrop = remember(layer) { ReviewBackdrop(layer) }
    val top = TopAppBarDefaults.windowInsets.asPaddingValues().calculateTopPadding() + 56.dp
    fun submit() {
        if (query.isBlank()) return
        focusManager.clearFocus(); submitted = query.trim(); revision++
    }
    LaunchedEffect(Unit) { focus.requestFocus() }
    CompositionLocalProvider(LocalBackdrop provides backdrop) {
        Box(Modifier.fillMaxSize().imePadding()) {
            Box(Modifier.fillMaxSize().recordBackdrop(backdrop).padding(top = top)) {
                if (submitted.isBlank()) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Rounded.ManageSearch, null, Modifier.size(64.dp), tint = colors.onSurfaceVariant.copy(alpha = .4f))
                        Spacer(Modifier.height(16.dp)); Text("输入关键词，检索 @$name 的微博", fontSize = 14.5.sp, color = colors.onSurfaceVariant)
                    }
                } else {
                    val data = remember(identity) { PagedContentState<Post>() }
                    DisposableEffect(data) { onDispose { data.stopObservingPosts?.invoke() } }
                    PagedContent(identity, { model.repository.userPosts(model.sessionCookie, id, it.toInt().coerceAtLeast(1), submitted) }, Post::id,
                        retained = data, contentPadding = PaddingValues(0.dp), showLoadMore = false, loadOnScrollOnly = true,
                        header = { if (data.rows.value.isNotEmpty() && !data.refreshing.value) item {
                            Text("包含 \"$submitted\" 的微博 (${data.rows.value.size}${if (data.more.value) "+" else ""})", Modifier.padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 6.dp), fontSize = 13.sp, fontWeight = reviewWeight(FontWeight.Medium), color = colors.primary)
                        } },
                        body = { rows -> if (!data.refreshing.value) items(rows, key = Post::id) { PostRow(it, gallery) } },
                        loading = { if (data.refreshing.value || data.rows.value.isEmpty()) Box(Modifier.fillParentMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() } else LoadingRow() },
                        empty = { Box(Modifier.fillParentMaxSize(), contentAlignment = Alignment.Center) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(Icons.Rounded.SearchOff, null, Modifier.size(64.dp), tint = colors.onSurfaceVariant.copy(alpha = .4f))
                                Spacer(Modifier.height(16.dp)); Text("未找到与 \"$submitted\" 相关的微博", fontSize = 14.5.sp, color = colors.onSurfaceVariant)
                                Spacer(Modifier.height(8.dp)); Text("请尝试更换关键词搜索", fontSize = 12.5.sp, color = colors.outline)
                            }
                        } }) { PostRow(it, gallery) }
                }
            }
            TopAppBar(title = {
                BasicTextField(query, { query = it }, Modifier.padding(end = 8.dp).fillMaxWidth().height(42.dp).background(colors.surfaceContainerHighest.copy(alpha = .5f), RoundedCornerShape(21.dp)).focusRequester(focus),
                    singleLine = true, textStyle = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.5.sp, color = colors.onSurface), cursorBrush = SolidColor(colors.primary),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { submit() }), decorationBox = { inner ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.width(48.dp).fillMaxHeight(), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Search, null, Modifier.size(20.dp), tint = colors.onSurfaceVariant) }
                            Box(Modifier.weight(1f)) { if (query.isEmpty()) Text("搜索 @$name 的微博", style = MaterialTheme.typography.bodyMedium, fontSize = 14.sp, color = colors.onSurfaceVariant.copy(alpha = .7f)); inner() }
                            if (query.isNotEmpty()) IconButton(hapticClick { query = ""; submitted = "" }) { Icon(Icons.Rounded.Clear, "清空", Modifier.size(18.dp)) }
                        }
                    })
            }, navigationIcon = { IconButton(hapticClick(model::back)) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "返回") } },
                actions = { TextButton(hapticClick(::submit), modifier = Modifier.width(64.dp), enabled = query.isNotBlank()) { Text("搜索", fontWeight = reviewWeight(FontWeight.Bold), color = if (query.isNotBlank()) colors.primary else colors.onSurfaceVariant.copy(alpha = .4f)) } },
                expandedHeight = 56.dp, colors = TopAppBarDefaults.topAppBarColors(containerColor = androidx.compose.ui.graphics.Color.Transparent), modifier = Modifier.frostedBackdrop(colors.background))
        }
    }
}
