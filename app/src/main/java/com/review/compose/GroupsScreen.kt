@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package com.review.compose

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

fun decodeGroups(raw: String, section: String): List<FeedGroup> = runCatching { JSONArray(raw).objects().mapNotNull {
    val id = it.optString("id"); val name = it.optString("name")
    if (id.isBlank() || name.isBlank() || id.startsWith("custom_")) null else FeedGroup(id, name, section)
} }.getOrDefault(emptyList())
fun encodeGroups(groups: List<FeedGroup>) = JSONArray(groups.map { JSONObject().put("id", it.id).put("name", it.title) }).toString()
private var defaultGroups: List<FeedGroup>? = null
fun ReviewModel.displayGroups(): List<FeedGroup> {
    val defaults = option("saved_default_groups_json").takeIf(String::isNotBlank)?.let { decodeGroups(it, "默认分组") }
        ?: defaultGroups ?: decodeGroups(getApplication<android.app.Application>().assets.open("groups.json").bufferedReader().use { JSONObject(it.readText().removePrefix("\uFEFF")).getJSONArray("default").toString() }, "默认分组").also { defaultGroups = it }
    val personal = if (option("groupsOwner") != uid) emptyList() else option("saved_personal_groups_json").takeIf(String::isNotBlank)?.let { decodeGroups(it, "我的分组") } ?: groups.filter { it.section == "我的分组" }
    val hot = decodeGroups(option("saved_hot_groups_json", "[]"), "热门分组")
    return defaults + personal + hot
}
@Composable
fun GroupDropdown(close: () -> Unit) {
    val model = LocalReview.current
    val colors = MaterialTheme.colorScheme
    val groups = model.displayGroups()
    Column(Modifier.fillMaxWidth().heightIn(max = LocalConfiguration.current.screenHeightDp.dp * .65f)
        .clip(RoundedCornerShape(bottomStart = 20.dp, bottomEnd = 20.dp)).frostedBackdrop(colors.background, panel = true)
        .verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 16.dp)) {
        listOf("默认分组", "我的分组", "热门分组").forEachIndexed { sectionIndex, section ->
            val items = groups.filter { it.section == section }
            if (sectionIndex == 0 || items.isNotEmpty()) {
                if (sectionIndex > 0) Spacer(Modifier.height(16.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(if (sectionIndex == 2) "热门频道" else section, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontWeight = reviewWeight(FontWeight.Bold))
                    if (sectionIndex == 0) Text("编辑", Modifier.reviewClickable { close(); model.navigate("groups") }.padding(horizontal = 8.dp, vertical = 4.dp), fontSize = 13.5.sp, color = colors.primary, fontWeight = reviewWeight(FontWeight.SemiBold))
                }
                Spacer(Modifier.height(10.dp))
                items.chunked(4).forEachIndexed { rowIndex, row ->
                    if (rowIndex > 0) Spacer(Modifier.height(10.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        row.forEach { group ->
                            val selected = model.group.id == group.id
                            Box(Modifier.weight(1f).aspectRatio(2.2f).clip(RoundedCornerShape(10.dp))
                                .background(if (selected) colors.primaryContainer else colors.surfaceContainerHighest.copy(alpha = .35f))
                                .border(if (selected) 1.2.dp else .8.dp, if (selected) colors.primary else colors.outlineVariant.copy(alpha = .25f), RoundedCornerShape(10.dp))
                                .reviewClickable { close(); model.selectGroup(group) }.padding(horizontal = 4.dp), contentAlignment = Alignment.Center) {
                                Text(group.title, maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 13.sp, fontWeight = reviewWeight(if (selected) FontWeight.Bold else FontWeight.Normal), color = if (selected) colors.onPrimaryContainer else colors.onSurface)
                            }
                        }
                        repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
        model.groupsError?.let { ErrorNotice(it, model::loadGroups) }
    }
}
@Composable
fun GroupsScreen() {
    val model = LocalReview.current
    val context = LocalContext.current
    val candidates = remember { context.assets.open("groups.json").bufferedReader().use { JSONObject(it.readText().removePrefix("\uFEFF")) } }
    var selected by remember { mutableStateOf(model.displayGroups()) }
    val pager = rememberPagerState { 3 }
    val scope = rememberCoroutineScope()
    val tab = pager.currentPage
    var create by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<FeedGroup?>(null) }
    var name by remember { mutableStateOf("") }
    val sections = listOf("我的分组", "默认分组", "热门分组")
    var recommendedDefault by remember { mutableStateOf(decodeGroups(candidates.getJSONArray("default").toString(), sections[1]).filterNot { candidate -> selected.any { it.id == candidate.id } }) }
    var recommendedHot by remember { mutableStateOf(decodeGroups(candidates.getJSONArray("hot").toString(), sections[2]).filterNot { candidate -> selected.any { it.id == candidate.id } }) }
    val layer = rememberGraphicsLayer()
    val backdrop = remember(layer) { ReviewBackdrop(layer) }
    val contentTop = TopAppBarDefaults.windowInsets.asPaddingValues().calculateTopPadding() + 104.dp
    val colors = MaterialTheme.colorScheme
    CompositionLocalProvider(LocalBackdrop provides backdrop) {
    Box(Modifier.fillMaxSize()) {
        HorizontalPager(pager, Modifier.fillMaxSize().recordBackdrop(backdrop).testTag("groups-pager"), verticalAlignment = Alignment.Top) { page ->
            val mine = selected.filter { it.section == sections[page] }
            if (page == 0) {
                if (mine.isEmpty()) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Rounded.FolderOpen, null, Modifier.size(48.dp), tint = colors.onSurfaceVariant.copy(alpha = .5f))
                        Spacer(Modifier.height(12.dp))
                        Text("暂无个人分组（请先在微博官方页面创建）", style = MaterialTheme.typography.bodyLarge, color = colors.onSurfaceVariant)
                    }
                } else LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = contentTop + 8.dp, bottom = 8.dp)) {
                    itemsIndexed(mine, key = { _, item -> item.id }) { index, item ->
                        if (index > 0) ReviewDivider(color = colors.outlineVariant.copy(alpha = .2f))
                        ReviewListItem(headlineContent = { Text(item.title, style = MaterialTheme.typography.bodyLarge, fontWeight = reviewWeight(FontWeight.Medium)) }, trailingContent = { Row {
                            IconButton(onClick = hapticClick { editing = item; name = item.title }) { Icon(Icons.Outlined.Edit, "重命名", Modifier.size(20.dp)) }
                            IconButton(onClick = hapticClick { selected = selected.filterNot { it == item } }) { Icon(Icons.Rounded.DeleteOutline, "删除", Modifier.size(20.dp)) }
                        } })
                    }
                }
            } else {
                val recommended = if (page == 1) recommendedDefault else recommendedHot
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, top = contentTop + 16.dp, end = 16.dp, bottom = 16.dp)) {
                    Text("我的分类 (仅调整本地显示，点击每项移除)", style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
                    Spacer(Modifier.height(12.dp))
                    if (mine.isEmpty()) Text(if (page == 1) "已清空全部默认分类（可从下方推荐分类点击添加）" else "暂未添加任何热门频道（可从下方推荐分类点击添加）", Modifier.padding(vertical = 8.dp), style = MaterialTheme.typography.bodySmall, color = colors.outline)
                    if (mine.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { mine.forEach { item ->
                        GroupChip(item.title, true) {
                            selected = selected.filterNot { it == item }
                            if (page == 1) recommendedDefault = recommendedDefault + item else recommendedHot = listOf(item) + recommendedHot
                        }
                    } }
                    Spacer(Modifier.height(28.dp))
                    Text("推荐分类 (点击添加到我的分类)", style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
                    Spacer(Modifier.height(12.dp))
                    if (page == 1 && recommended.isEmpty()) Text("已添加全部默认分类", style = MaterialTheme.typography.bodySmall, color = colors.outline)
                    if (recommended.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { recommended.forEach { item ->
                        GroupChip(item.title, false) {
                            selected = selected + item
                            if (page == 1) recommendedDefault = recommendedDefault.filterNot { it == item } else recommendedHot = recommendedHot.filterNot { it == item }
                        }
                    } }
                }
            }
        }
        Column(Modifier.fillMaxWidth().frostedBackdrop(colors.background)) {
        TopAppBar(title = { Text("分组管理", Modifier.padding(start = 16.dp), fontSize = 18.sp) }, navigationIcon = { IconButton(onClick = hapticClick(model::back)) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回") } }, actions = {
            if (tab == 0) TextButton(onClick = hapticClick { create = true }) { Text("新建", fontWeight = reviewWeight(FontWeight.Bold)) }
            TextButton(onClick = hapticClick {
                listOf("默认分组" to "default", "我的分组" to "personal", "热门分组" to "hot").forEach { (group, key) -> model.setOption("saved_${key}_groups_json", encodeGroups(selected.filter { it.section == group })) }
                model.notice = "🎉 分组配置已保存并即时生效"; model.back()
            }) { Text("保存", fontWeight = reviewWeight(FontWeight.Bold)) }; Spacer(Modifier.width(8.dp))
        }, expandedHeight = 56.dp, colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent))
        PrimaryTabRow(tab, containerColor = Color.Transparent, contentColor = colors.onSurface) { listOf("个人分组", "默认分组", "热门分组").forEachIndexed { i, title -> Tab(tab == i, hapticClick { scope.launch { pager.animateScrollToPage(i) } }, Modifier.height(48.dp), unselectedContentColor = colors.onSurfaceVariant, text = { Text(title, fontSize = 15.sp, fontWeight = reviewWeight(if (tab == i) FontWeight.SemiBold else FontWeight.Normal)) }) } }
        }
    }
    }
    if (create) ReviewAlertDialog(onDismissRequest = { create = false }, title = { Text("暂不支持新建云端分组") }, text = { Text("当前只能使用微博账号已有的个人分组。本地伪造分组无法读取微博内容，因此已停止创建。") }, confirmButton = { Button(onClick = hapticClick { create = false }) { Text("知道了") } })
    editing?.let { item ->
        val focus = remember { FocusRequester() }
        ReviewAlertDialog(onDismissRequest = { editing = null }, title = { Text("重命名分组") }, text = {
            LaunchedEffect(item.id) { focus.requestFocus() }
            TextField(name, { name = it }, Modifier.focusRequester(focus), singleLine = true)
        }, confirmButton = { Button(onClick = hapticClick { selected = selected.map { if (it == item) it.copy(title = name.trim()) else it }; editing = null }, enabled = name.isNotBlank()) { Text("确定") } }, dismissButton = { TextButton(onClick = hapticClick { editing = null }) { Text("取消") } })
    }
}

@Composable
private fun GroupChip(label: String, included: Boolean, click: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    Surface(onClick = hapticClick(click), shape = RoundedCornerShape(10.dp),
        color = colors.surfaceContainerHighest.copy(alpha = if (included) .5f else .25f), contentColor = colors.onSurface,
        border = androidx.compose.foundation.BorderStroke(1.dp, colors.outlineVariant)) {
        Text(label, Modifier.padding(horizontal = 17.dp, vertical = 9.dp), fontSize = 14.sp, lineHeight = 20.sp, fontWeight = reviewWeight(FontWeight.SemiBold))
    }
}
