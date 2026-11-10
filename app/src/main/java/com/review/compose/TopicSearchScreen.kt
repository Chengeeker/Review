@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp

@Composable
fun TopicSearchScreen(id: String, title: String, gallery: (List<Media>, Int) -> Unit) {
    val model = LocalReview.current; val colors = MaterialTheme.colorScheme
    val layer = rememberGraphicsLayer(); val backdrop = remember(layer) { ReviewBackdrop(layer) }
    val focus = LocalFocusManager.current; val inputFocus = remember { FocusRequester() }
    var query by rememberSaveable(id) { mutableStateOf("") }
    var submitted by rememberSaveable(id) { mutableStateOf("") }
    var revision by remember { mutableIntStateOf(0) }
    fun search() { if (query.isNotBlank()) { submitted = query.trim(); revision++; focus.clearFocus() } }
    LaunchedEffect(Unit) { inputFocus.requestFocus() }
    CompositionLocalProvider(LocalBackdrop provides backdrop) {
    Scaffold(containerColor = colors.background, topBar = {
        TopAppBar(title = {
            BasicTextField(query, { query = it }, Modifier.fillMaxWidth().padding(start = 16.dp).focusRequester(inputFocus),
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.onSurface), cursorBrush = SolidColor(colors.primary), singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { search() }),
                decorationBox = { input -> Box { if (query.isEmpty()) Text("搜索 $title 内的帖子", color = colors.onSurfaceVariant); input() } })
        }, navigationIcon = { IconButton(onClick = hapticClick(model::back)) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回") } },
            actions = { IconButton(onClick = hapticClick(::search)) { Icon(Icons.Outlined.Search, "搜索本超话") } }, expandedHeight = 56.dp,
            colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent), modifier = Modifier.frostedBackdrop(colors.background))
    }) { padding ->
        Box(Modifier.fillMaxSize().padding(padding).recordBackdrop(backdrop)) {
            PagedContent("topicSearch:$id:$submitted:$revision:${model.uid}", { cursor ->
                if (submitted.isBlank() || model.demo) Page(emptyList()) else model.repository.globalSearch(model.sessionCookie, submitted, cursor.toInt().coerceAtLeast(1), id, title)
            }, Post::id, header = { item { Text("仅搜索「$title」内的帖子", Modifier.padding(16.dp)) } }, empty = {
                if (submitted.isNotBlank()) Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = androidx.compose.ui.Alignment.Center) { Text("暂无匹配帖子") }
            }) { PostRow(it, gallery) }
        }
    }
    }
}
