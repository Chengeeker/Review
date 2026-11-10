@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

@Composable
fun PublishScreen(editId: String? = null) {
    val model = LocalReview.current
    val context = LocalContext.current
    val original = LocalReviewRoute.current?.post?.takeIf { it.id == editId }
    var editor by rememberSaveable(editId, stateSaver = TextFieldValue.Saver) { mutableStateOf(TextFieldValue(model.draft, TextRange(model.draft.length))) }
    LaunchedEffect(model.draft) { if (editor.text != model.draft) editor = TextFieldValue(model.draft, TextRange(model.draft.length)) }
    fun updateEditor(value: TextFieldValue) { editor = value; model.saveDraft(value.text) }
    var selected by rememberSaveable { mutableStateOf(arrayListOf<String>()) }
    var video by rememberSaveable { mutableStateOf("") }
    var visibility by rememberSaveable(editId) { mutableIntStateOf(original?.data?.optJSONObject("visible")?.optInt("type")?.takeIf { it in setOf(0, 1, 5, 6, 10) } ?: 0) }
    var statement by rememberSaveable { mutableIntStateOf(0) }
    var options by remember { mutableStateOf<List<Pair<Int, String>>>(emptyList()) }
    var picker by remember { mutableStateOf("") }
    var topic by rememberSaveable { mutableStateOf("") }
    var topicMarker by rememberSaveable { mutableStateOf("") }
    var place by rememberSaveable { mutableStateOf("") }
    var film by rememberSaveable { mutableStateOf("") }
    var score by rememberSaveable { mutableFloatStateOf(5f) }
    var progress by remember { mutableFloatStateOf(0f) }
    var info by remember { mutableStateOf("") }
    var scheduleInfo by remember { mutableStateOf(false) }
    var emoji by rememberSaveable { mutableStateOf(false) }
    var ratingMovie by remember { mutableStateOf<JSONObject?>(null) }
    val focus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    LaunchedEffect(Unit) { focus.requestFocus() }
    var location by remember { mutableStateOf<android.location.Location?>(null) }
    val locationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        location = lastPublishLocation(context); picker = "place"
    }
    val images = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        uris.take(9 - selected.size).forEach { uri -> runCatching { context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } }
        selected = ArrayList((selected + uris.map(Uri::toString)).distinct().take(9))
    }
    val movie = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { runCatching { context.contentResolver.takePersistableUriPermission(it, Intent.FLAG_GRANT_READ_URI_PERMISSION) }; video = it.toString() }
    }
    LaunchedEffect(model.uid) {
        for (path in listOf("/ajax/getSpaConfig", "/ajax/statuses/config")) {
            try {
                val root = model.repository.get(path, model.sessionCookie)
                val source = findJson(root, "mblog_statement_list")
                val decoded = if (source is String) runCatching { JSONArray(source) }.getOrNull() else source
                if (decoded is JSONArray) options = decoded.objects().mapNotNull { o ->
                    val value = listOf("type", "value", "id", "code").firstNotNullOfOrNull { o.optString(it).toIntOrNull() }
                    val label = listOf("name", "text", "label", "title", "desc").firstNotNullOfOrNull { o.optString(it).takeIf(String::isNotBlank) }
                    if (value == null || label == null) null else value to label
                }
                if (options.isNotEmpty()) break
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) { }
        }
    }
    val colors = MaterialTheme.colorScheme
    val layer = rememberGraphicsLayer()
    val backdrop = remember(layer) { ReviewBackdrop(layer) }
    val toolbarTop = TopAppBarDefaults.windowInsets.asPaddingValues().calculateTopPadding() + 56.dp
    CompositionLocalProvider(LocalBackdrop provides backdrop) {
    Box(Modifier.fillMaxSize().imePadding()) {
    Column(Modifier.fillMaxSize().recordBackdrop(backdrop)) {
        Spacer(Modifier.height(toolbarTop))
        Column(Modifier.weight(1f).padding(horizontal = 16.dp, vertical = 8.dp)) {
            BasicTextField(editor, { if (!emoji || it.text != editor.text) updateEditor(it) }, Modifier.fillMaxWidth().weight(1f).focusRequester(focus).onFocusChanged { if (it.isFocused) emoji = false }, enabled = !model.actionBusy,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface, fontSize = 16.sp, lineHeight = 24.sp), cursorBrush = androidx.compose.ui.graphics.SolidColor(MaterialTheme.colorScheme.primary),
                decorationBox = { field -> Box { if (model.draft.isBlank()) Text(if (editId == null) "分享新鲜事..." else "修改你的微博内容...", fontSize = 16.sp, lineHeight = 24.sp, color = MaterialTheme.colorScheme.onSurfaceVariant); field() } })
            if (selected.isNotEmpty()) LazyRow(Modifier.padding(top = 8.dp).height(90.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(selected) { uri -> Box(Modifier.size(80.dp)) {
                    AsyncImage(Uri.parse(uri), "待发布图片", Modifier.fillMaxSize().clip(RoundedCornerShape(10.dp)), contentScale = ContentScale.Crop)
                    Icon(Icons.Outlined.Close, "移除图片", Modifier.align(Alignment.TopEnd).padding(4.dp).clip(CircleShape).background(Color.Black.copy(alpha = .54f)).reviewClickable(enabled = !model.actionBusy) { selected = ArrayList(selected - uri) }.padding(2.dp).size(14.dp), tint = Color.White)
                } }
                if (selected.size < 9) item { Box(Modifier.size(80.dp).border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(10.dp)).reviewClickable(enabled = !model.actionBusy) { images.launch(arrayOf("image/*")) }, contentAlignment = Alignment.Center) { Icon(Icons.Outlined.AddPhotoAlternate, "添加图片", tint = MaterialTheme.colorScheme.primary) } }
            }
            if (video.isNotBlank()) {
                Spacer(Modifier.height(8.dp))
                Row(Modifier.background(colors.primaryContainer.copy(alpha = .45f), RoundedCornerShape(12.dp)).padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.VideoFile, null, tint = colors.primary); Spacer(Modifier.width(8.dp))
                    val fileName by produceState(Uri.parse(video).lastPathSegment.orEmpty(), video) {
                        val name = withContext(Dispatchers.IO) { runCatching { context.contentResolver.query(Uri.parse(video), arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null } }.getOrNull() }
                        if (!name.isNullOrBlank()) value = name
                    }
                    Text(fileName, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    IconButton(onClick = hapticClick { video = "" }, enabled = !model.actionBusy, modifier = Modifier.size(40.dp)) { Icon(Icons.Rounded.Close, "移除视频") }
                }
            }
            Spacer(Modifier.height(6.dp))
            if (film.isNotBlank()) InputChip(true, onClick = {}, label = { Text("点评 ${score.toInt()} 星") }, leadingIcon = { Icon(Icons.Outlined.Star, null, Modifier.size(16.dp)) }, trailingIcon = { Icon(Icons.Outlined.Close, "取消点评", Modifier.reviewClickable(enabled = !model.actionBusy) { film = "" }) })
            Row(verticalAlignment = Alignment.CenterVertically) {
                val located = place.isNotBlank()
                CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides 0.dp) {
                Surface(onClick = hapticClick {
                    if (hasLocationPermission(context)) { location = lastPublishLocation(context); picker = "place" }
                    else locationPermission.launch(arrayOf(android.Manifest.permission.ACCESS_FINE_LOCATION, android.Manifest.permission.ACCESS_COARSE_LOCATION))
                }, enabled = !model.actionBusy, shape = RoundedCornerShape(16.dp), color = if (located) colors.primaryContainer.copy(alpha = .6f) else colors.surfaceContainerHighest.copy(alpha = .5f),
                    contentColor = if (located) colors.primary else colors.onSurfaceVariant, border = BorderStroke(.8.dp, if (located) colors.primary.copy(alpha = .4f) else Color.Transparent)) {
                    Row(Modifier.padding(horizontal = 10.8.dp, vertical = 5.8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.NearMe, null, Modifier.size(15.dp)); Spacer(Modifier.width(4.dp))
                        Text(if (located) JSONObject(place).optString("title") else "你在哪里", fontSize = 12.sp, fontWeight = reviewWeight(if (located) FontWeight.Bold else FontWeight.Normal))
                        if (located) { Spacer(Modifier.width(4.dp)); Icon(Icons.Rounded.Close, "清除地点", Modifier.size(13.dp).reviewClickable(enabled = !model.actionBusy) { place = "" }) }
                    }
                }
                }
                Spacer(Modifier.weight(1f)); Text("${model.draft.length} 字", fontSize = 12.sp, color = if (model.draft.length > 2000) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (model.actionBusy) LinearProgressIndicator(progress = { progress }, Modifier.fillMaxWidth())
        Column(Modifier.fillMaxWidth().background(colors.surfaceContainerHighest.copy(alpha = .35f))) {
        HorizontalDivider(thickness = 1.dp, color = colors.outlineVariant.copy(alpha = .3f))
        Row(Modifier.fillMaxWidth().padding(start = 8.dp, top = 6.dp, end = 8.dp, bottom = 8.dp).navigationBarsPadding(), verticalAlignment = Alignment.CenterVertically) {
            LazyRow(Modifier.weight(1f)) {
                items(listOf(Triple("表情", if (emoji) Icons.Outlined.KeyboardAlt else Icons.Rounded.SentimentSatisfiedAlt, "emoji"), Triple("媒体", Icons.Outlined.PermMedia, "media"), Triple("话题", Icons.Rounded.Tag, "topic"), Triple("超话", Icons.Outlined.Forum, "superTopic"), Triple("提及", Icons.Rounded.AlternateEmail, "mention"), Triple("点评", Icons.Outlined.RateReview, "review"))) { (label, icon, mode) ->
                    Column(Modifier.reviewClickable(enabled = !model.actionBusy) {
                        if (mode == "emoji") { emoji = !emoji; if (emoji) { focusManager.clearFocus(); keyboard?.hide() } else focus.requestFocus() }
                        else picker = mode
                    }.padding(horizontal = 8.dp, vertical = 2.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        val tint = if (mode == "emoji" && emoji) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
                        Icon(icon, label, Modifier.size(22.dp), tint = tint); Spacer(Modifier.height(2.dp)); Text(label, fontSize = 11.sp, color = tint)
                    }
                }
            }
            Spacer(Modifier.width(4.dp))
            Button(onClick = hapticClick {
                val submitted = model.draft
                val chosen = selected.toList()
                val chosenVideo = video
                if (submitted.isBlank() && chosen.isEmpty() && chosenVideo.isBlank()) model.notice = "请输入微博内容或添加图片/视频"
                else if (model.uid.isBlank() && !model.demo) model.notice = "请先登录微博账号"
                else model.mutate {
                    require(model.sessionCookie.isNotBlank()) { "发布或编辑需要网页会话，请导入同一账号的 Cookie" }
                    val poi = place.takeIf(String::isNotBlank)?.let(::JSONObject)
                    val content = contentWithPlace(submitted, poi)
                    val media = mutableListOf<Upload>()
                    chosen.forEachIndexed { i, uri -> media += model.repository.uploadImage(context, Uri.parse(uri), model.sessionCookie); progress = (i + 1f) / chosen.size }
                    if (chosenVideo.isNotBlank()) media += model.repository.uploadVideo(context, Uri.parse(chosenVideo), model.sessionCookie) { progress = it }
                    val extra = buildMap {
                        if (topic.isNotBlank() && content.contains(topicMarker)) { put("topic_id", topic); put("sync_mblog", "1") }
                        if (film.isNotBlank()) { put("rating_object_id", "1022:100120$film"); put("score", "${score / 5}") }
                        putAll(placeFields(poi))
                    }
                    val fields = publishFields(content, visibility, media, statement, extra).toMutableMap()
                    if (editId != null) fields["mid"] = numericStatusId(editId).also { require(it.isNotBlank()) { "内容标识无效" } }
                    // A timed-out publish cannot safely be retried on another endpoint.
                    if (model.repository.mobileOnly) {
                        require(editId == null && visibility == 0 && extra.isEmpty() && statement == 0 && chosenVideo.isBlank()) { "当前发布选项需要桌面会话，请补充登录" }
                        model.repository.api.post(ApiClient.MOBILE + "/api/statuses/update", model.sessionCookie, buildMap { put("content", content); if (media.isNotEmpty()) put("picId", media.joinToString(",") { it.id }) })
                    } else model.repository.api.post(ApiClient.DESKTOP + if (editId == null) "/ajax/statuses/update" else "/ajax/statuses/modify", model.sessionCookie, fields)
                    if (model.draft == submitted) model.saveDraft("")
                    selected = arrayListOf(); video = ""; model.refreshFeed(); model.back()
                }
            }, enabled = !model.actionBusy, modifier = Modifier.widthIn(min = 64.dp), shape = RoundedCornerShape(20.dp), contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp)) {
                if (model.actionBusy) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Text(if (editId == null) "发送" else "保存修改")
            }
        }
        }
        if (emoji) EmojiPanel(backspace = { updateEditor(editor.erasePhrase()) }) { updateEditor(editor.insertPhrase(it)) }
    }
        TopAppBar(title = { Text(if (editId == null) "发微博" else "编辑微博", Modifier.padding(start = 16.dp), fontSize = 18.sp) }, navigationIcon = { IconButton(onClick = hapticClick(model::back), enabled = !model.actionBusy) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回") } },
            actions = {
                PublishSettingChip("无定时", "定时微博", !model.actionBusy) { scheduleInfo = true }
                PublishSettingChip(mapOf(0 to "公开", 10 to "粉丝", 6 to "好友", 1 to "私密", 5 to "群友")[visibility].orEmpty(), "可见范围", !model.actionBusy) { picker = "visibility" }
                PublishSettingChip(if (statement == 0) "无声明" else declarationShortLabel(options.firstOrNull { it.first == statement }?.second.orEmpty()), "内容声明", !model.actionBusy) { if (options.isEmpty()) model.notice = "微博服务器暂未返回内容声明选项，请稍后重试" else picker = "declaration" }
                Spacer(Modifier.width(4.dp))
            }, expandedHeight = 56.dp, colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent), modifier = Modifier.frostedBackdrop(colors.background))
    }
    }
    if (picker in setOf("visibility", "declaration", "media")) ModalBottomSheet(onDismissRequest = { picker = "" }) {
        when (picker) {
            "visibility" -> listOf(0 to "公开", 10 to "粉丝", 6 to "好友圈", 1 to "仅自己可见", 5 to "群可见").forEach { (id, title) -> ReviewListItem(headlineContent = { Text(title) }, trailingContent = if (id == visibility) { { Icon(Icons.Rounded.Check, null, tint = colors.primary) } } else null, modifier = Modifier.reviewClickable { visibility = id; picker = "" }) }
            "declaration" -> (listOf(0 to "无") + options).forEach { (id, title) -> ReviewListItem(headlineContent = { Text(title) }, trailingContent = if (id == statement) { { Icon(Icons.Rounded.Check, null, tint = colors.primary) } } else null, modifier = Modifier.reviewClickable { statement = id; picker = "" }) }
            "media" -> {
                ReviewListItem(headlineContent = { Text("图片") }, modifier = Modifier.reviewClickable { picker = ""; if (video.isNotBlank()) info = "图片和视频不能同时发布，请先移除视频" else if (selected.size >= 9) info = "最多只能添加 9 张图片" else images.launch(arrayOf("image/*")) })
                ReviewListItem(headlineContent = { Text("视频") }, modifier = Modifier.reviewClickable { picker = ""; if (selected.isNotEmpty()) info = "图片和视频不能同时发布，请先移除图片" else movie.launch(arrayOf("video/*")) })
            }
        }
    }
    if (picker in setOf("mention", "topic", "superTopic", "place", "review")) PublishPicker(picker, { picker = "" }, location) { item ->
        val title = listOf("title", "screen_name", "suggestion", "word", "name", "nick").firstNotNullOfOrNull { item.optString(it).takeIf(String::isNotBlank) }.orEmpty()
        when (picker) {
            "mention" -> updateEditor(editor.insertPhrase("@$title "))
            "topic" -> {
                val superTopic = item.optBoolean("is_super_topic")
                topic = if (superTopic) item.optString("oid") else ""
                topicMarker = if (superTopic) "#${title}[超话]#" else ""
                updateEditor(editor.insertPhrase(if (superTopic) "$topicMarker " else "#${title.trim('#')}# "))
            }
            "superTopic" -> { topic = item.optString("oid").ifBlank { item.optString("topic_id").ifBlank { item.optString("page_id") } }; topicMarker = "#${title}[超话]#"; updateEditor(editor.insertPhrase("$topicMarker ")) }
            "place" -> place = item.toString()
            "review" -> ratingMovie = item
        }
        picker = ""
    }
    ratingMovie?.let { item -> ModalBottomSheet(onDismissRequest = { ratingMovie = null }) {
        val title = item.optString("title").ifBlank { item.optString("name") }
        ReviewListItem(headlineContent = { Text("点评《$title》") })
        listOf("很差", "一般", "还行", "不错", "超赞").forEachIndexed { index, label ->
            ReviewListItem(headlineContent = { Text(label) }, leadingContent = { Icon(Icons.Rounded.Star, null, tint = Color(0xFFFFC107)) }, modifier = Modifier.reviewClickable {
                film = item.optString("film_id").ifBlank { item.optString("id") }; score = index + 1f; updateEditor(editor.insertPhrase("《$title》")); ratingMovie = null
            })
        }
    } }
    if (info.isNotBlank()) ReviewAlertDialog(onDismissRequest = { info = "" }, text = { Text(info) }, confirmButton = { TextButton(onClick = hapticClick { info = "" }) { Text("知道了") } })
    if (scheduleInfo) ReviewAlertDialog(onDismissRequest = { scheduleInfo = false }, title = { Text("定时微博") }, text = { Text("定时发布由微博网页端的独立流程处理。当前账号的网页端入口需要开通会员，应用不会伪造一个本地定时发布。") }, confirmButton = { TextButton(onClick = hapticClick { scheduleInfo = false }) { Text("知道了") } })
}

@Composable
private fun PublishSettingChip(label: String, description: String, enabled: Boolean, click: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    Box(Modifier.padding(horizontal = 2.dp, vertical = 6.dp).height(44.dp).reviewClickable(enabled = enabled, onClick = click).semantics { contentDescription = description }, contentAlignment = Alignment.Center) {
        Surface(shape = CircleShape, border = BorderStroke(1.dp, colors.outlineVariant.copy(alpha = .7f)), color = colors.surface, contentColor = colors.onSurfaceVariant) {
            Box(Modifier.height(34.dp).padding(horizontal = 15.dp), contentAlignment = Alignment.Center) {
                Text(label, fontSize = 11.sp, fontWeight = reviewWeight(FontWeight.SemiBold), maxLines = 1)
            }
        }
    }
}

internal fun declarationShortLabel(label: String): String = label.trim().let { text ->
    val normalized = text.lowercase()
    when {
        normalized.contains("转载") -> "转载"
        normalized.contains("自主创作") || normalized.contains("原创") || normalized == "创作" -> "创作"
        normalized.contains("ai") || normalized.contains("人工智能") || normalized.contains("生成式") -> "AI"
        normalized.contains("虚构") || normalized.contains("演绎") -> "虚构"
        text.isBlank() -> "无声明"
        else -> text
    }
}

@Composable
fun PublishPicker(mode: String, close: () -> Unit, location: android.location.Location? = null, select: (JSONObject) -> Unit) {
    val model = LocalReview.current
    var query by rememberSaveable(mode) { mutableStateOf("") }
    var results by remember(mode) { mutableStateOf<List<JSONObject>>(emptyList()) }
    var error by remember(mode) { mutableStateOf<String?>(null) }
    var busy by remember(mode) { mutableStateOf(false) }
    var retry by remember { mutableIntStateOf(0) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    LaunchedEffect(query, mode, retry) {
        delay(280); busy = true; error = null
        try { val fetched = model.repository.picker(model.sessionCookie, mode, query); results = if (mode == "place") nearbyPlaces(fetched, location) else fetched }
        catch (e: CancellationException) { throw e }
        catch (e: Exception) { error = e.message }
        finally { busy = false }
    }
    ModalBottomSheet(onDismissRequest = close) {
        Column(Modifier.fillMaxHeight(.82f).padding(start = 16.dp, top = 8.dp, end = 16.dp, bottom = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(when(mode) { "mention" -> "提及用户"; "place" -> "选择地点"; "superTopic" -> "选择超话"; "review" -> "选择点评对象"; else -> "选择话题" }, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontWeight = reviewWeight(FontWeight.Bold))
                IconButton(onClick = hapticClick(close)) { Icon(Icons.Outlined.Close, "关闭") }
            }
            OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().focusRequester(focus), placeholder = { Text(when(mode) { "mention" -> "搜索用户昵称"; "place" -> "搜索附近地点"; "review" -> "搜索电影"; "superTopic" -> "搜索超话"; else -> "搜索话题" }) }, singleLine = true,
                shape = RoundedCornerShape(14.dp), leadingIcon = { Icon(Icons.Outlined.Search, null) }, trailingIcon = { if (query.isNotEmpty()) IconButton(onClick = hapticClick { query = "" }) { Icon(Icons.Outlined.Close, "清空") } })
            Spacer(Modifier.height(10.dp))
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                when {
                    busy -> CircularProgressIndicator()
                    error != null -> ErrorNotice(error.orEmpty()) { retry++ }
                    results.isEmpty() -> Text(when(mode) { "mention" -> "输入昵称搜索微博用户"; "place" -> "输入地点名称搜索微博地点"; "review" -> "输入电影名称搜索点评对象"; "superTopic" -> "输入关键词搜索超话"; else -> "输入关键词搜索话题" }, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    else -> LazyColumn(Modifier.fillMaxSize()) { items(results) { item ->
                        val title = listOf("title", "screen_name", "suggestion", "word", "name", "nick").firstNotNullOfOrNull { item.optString(it).takeIf(String::isNotBlank) }.orEmpty()
                        val description = if (mode == "place") placeSubtitle(item) else if (mode == "topic") item.optLong("discuss_num").takeIf { it > 0 }?.let { "讨论 $it" }.orEmpty() else item.optString("description").ifBlank { item.optString("desc") }.ifBlank { if (mode == "mention") "微博用户" else if (mode == "superTopic") "超话" else "" }
                        ReviewListItem(headlineContent = { Text(title) }, supportingContent = if (description.isBlank()) null else { { Text(description, maxLines = 1, overflow = TextOverflow.Ellipsis) } },
                            leadingContent = {
                                when (mode) {
                                    "place" -> Icon(Icons.Outlined.LocationOn, null, tint = MaterialTheme.colorScheme.primary)
                                    "topic" -> Icon(if (item.optBoolean("is_super_topic")) Icons.Outlined.Diamond else Icons.Rounded.Tag, null, tint = MaterialTheme.colorScheme.primary)
                                    else -> Avatar(title, item.optString("profile_image_url").ifBlank { item.optString("avatar_large") }.ifBlank { item.optString("poster") }.ifBlank { item.optString("image") }, Modifier.size(if (mode == "mention") 42.dp else 44.dp))
                                }
                            }, trailingContent = if (mode in setOf("review", "superTopic", "topic")) { { Text(if (mode == "review") "点评" else if (mode == "superTopic" || item.optBoolean("is_super_topic")) "超话" else "话题") } } else null,
                            modifier = Modifier.reviewClickable { select(item) })
                        ReviewDivider(thickness = .5.dp)
                    } }
                }
            }
        }
    }
}
suspend fun Repository.picker(cookie: String, mode: String, query: String): List<JSONObject> {
    val path = when(mode) { "place" -> "/ajax/statuses/place"; "review" -> "/ajax/movie/${if (query.isBlank()) "hot_top" else "hot_search"}"; "superTopic" -> "/ajax/stopic/list"; else -> "/ajax/side/search" }
    val params = when(mode) {
        "place" -> mapOf("q" to query, "page" to "1")
        "review" -> if (query.isBlank()) mapOf("type" to "hotshow") else mapOf("k" to query)
        "superTopic" -> mapOf("keyword" to query, "page" to "1")
        else -> mapOf("q" to query, "type" to if (mode == "mention") "user" else "topic")
    }
    if (query.isBlank() && mode !in setOf("place", "review")) return emptyList()
    val root = get(path, cookie, params)
    val data = root.optJSONObject("data") ?: root
    return when(mode) {
        "place" -> data.optJSONArray("pois").objects()
        "mention" -> data.optJSONArray("user").objects()
        "topic" -> listOfNotNull(data.optJSONArray("hotquery"), data.optJSONArray("query_relates")).flatMap { array ->
            (0 until array.length()).mapNotNull { index ->
                val raw = array.opt(index)
                val item = (raw as? JSONObject)?.let { JSONObject(it.toString()) } ?: (raw as? String)?.let { JSONObject().put("word", it) } ?: return@mapNotNull null
                val word = listOf("suggestion", "word", "query").firstNotNullOfOrNull { item.optString(it).takeIf(String::isNotBlank) }.orEmpty().trim().trim('#')
                if (word.isBlank()) null else item.put("title", word.removeSuffix("[超话]").trim())
                    .put("word", word.removeSuffix("[超话]").trim())
                    .put("is_super_topic", word.endsWith("[超话]") || item.optInt("is_super_topic") == 1 || item.optString("topic_type") == "super")
                    .put("oid", item.optString("oid").ifBlank { item.optString("topic_id").ifBlank { item.optString("page_id") } })
                    .put("discuss_num", listOf("discuss_num", "discuss", "count").firstNotNullOfOrNull { item.optString(it).toLongOrNull() } ?: 0)
            }
        }.distinctBy { it.optString("word") }
        else -> responseArray(root, "list", "data").objects()
    }
}
