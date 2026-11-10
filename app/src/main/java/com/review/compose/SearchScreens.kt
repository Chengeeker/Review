@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package com.review.compose

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

@Composable
fun AdvancedSearchScreen(gallery: (List<Media>, Int) -> Unit) {
    val model = LocalReview.current
    var query by rememberSaveable { mutableStateOf("") }
    var types by rememberSaveable { mutableStateOf(ArrayList(searchTypes.keys)) }
    var start by rememberSaveable { mutableStateOf("") }
    var end by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }
    var submitted by remember { mutableStateOf<FollowingFilter?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    var total by remember { mutableIntStateOf(0) }
    var picker by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    if (model.uid.isBlank()) { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("登录后搜索我关注的人的微博", Modifier.reviewClickable { model.navigate("account") }) }; return }
    PagedContent("advanced:$revision:${model.uid}", { cursor ->
        submitted?.let { filter -> model.repository.followingSearch(model.sessionCookie, filter, cursor.toInt().coerceAtLeast(1)).let { total = it.second; it.first } } ?: Page(emptyList())
    }, Post::id, header = {
        item {
            Column(Modifier.padding(16.dp)) {
                OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth(), label = { Text("关键词（可留空）") }, singleLine = true)
                FlowRow { searchTypes.forEach { (key, title) -> Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(key in types, hapticChange { types = ArrayList(if (it) types + key else types - key) }); Text(title) } } }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedButton(onClick = hapticClick { picker = "start" }) { Text(start.ifBlank { "开始日期（不限）" }) }
                    if (start.isNotBlank()) IconButton(onClick = hapticClick { start = "" }) { Icon(Icons.Outlined.Close, "清除开始日期") }
                    Text("到", Modifier.padding(horizontal = 6.dp)); OutlinedButton(onClick = hapticClick { picker = "end" }) { Text(end) }
                }
                Button(onClick = hapticClick {
                    try { val filter = FollowingFilter(query, types.toSet(), start.takeIf(String::isNotBlank)?.let(LocalDate::parse), LocalDate.parse(end)); filter.params(1); submitted = filter; revision++; error = null }
                    catch (e: Exception) { error = e.message }
                }) { Icon(Icons.Outlined.Search, null); Text("搜索") }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                if (submitted != null && total >= 0) Text("搜索到 $total 条微博", Modifier.padding(top = 16.dp))
            }
        }
    }) { PostRow(it, gallery) }
    picker?.let { kind ->
        val date = (if (kind == "start") start else end).takeIf(String::isNotBlank)?.let(LocalDate::parse) ?: LocalDate.now()
        val state = rememberDatePickerState(date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(onDismissRequest = { picker = null }, confirmButton = { TextButton(onClick = hapticClick { state.selectedDateMillis?.let { value -> val text = Instant.ofEpochMilli(value).atZone(ZoneOffset.UTC).toLocalDate().toString(); if (kind == "start") start = text else end = text }; picker = null }) { Text("确定") } }, dismissButton = { TextButton(onClick = hapticClick { picker = null }) { Text("取消") } }) { DatePicker(state) }
    }
}
