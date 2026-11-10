@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package com.review.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

internal fun profileCount(value: String): String = value.toLongOrNull()?.let { if (it > 10000) String.format(Locale.ROOT, "%.1f万", it / 10000.0) else "$it" } ?: value.ifBlank { "0" }

@Composable
private fun ProfileEmpty(message: String) {
    Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant) }
}

@Composable
private fun ProfileFeatureChip(label: String, selected: Boolean, onClick: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides 40.dp) {
    Surface(hapticClick(onClick), shape = RoundedCornerShape(8.dp), color = if (selected) colors.secondaryContainer else Color.Transparent,
        contentColor = if (selected) colors.onSecondaryContainer else colors.onSurfaceVariant,
        border = if (selected) null else BorderStroke(1.dp, colors.outlineVariant)) {
        Row(Modifier.heightIn(min = 30.dp).padding(start = if (selected) 12.dp else 16.dp, end = 16.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            if (selected) { Icon(Icons.Rounded.Check, null, Modifier.size(18.dp)); Spacer(Modifier.width(3.dp)) }
            Text(label, fontSize = 12.sp, fontWeight = reviewWeight(if (selected) FontWeight.Bold else FontWeight.Normal))
        }
    }
    }
}

@Composable
private fun ProfileVideoCard(post: Post, media: Media, modifier: Modifier) {
    val model = LocalReview.current
    val colors = MaterialTheme.colorScheme
    val plays = post.data.optJSONObject("page_info")?.optJSONObject("media_info")?.optLong("play_count") ?: 0L
    Surface(modifier.padding(horizontal = 10.dp, vertical = 5.dp).reviewClickable {
        model.mediaAuthor = post.author; model.navigate("video:${android.net.Uri.encode(media.video)}"); model.routeStack.last().media = media; model.routeStack.last().post = post
    }, shape = RoundedCornerShape(12.dp), color = colors.surfaceContainerLowest, border = BorderStroke(.8.dp, (if (colors.background == Color.Black) Color.White else colors.outlineVariant).copy(alpha = .1f))) {
        Column {
            Box(Modifier.fillMaxWidth().aspectRatio(16f / 9)) {
                if (media.url.isBlank()) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .87f)), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.VideoLibrary, null, Modifier.size(28.dp), tint = Color.White.copy(alpha = .7f)) }
                else MediaImage(media, "视频封面", Modifier.fillMaxSize())
                Box(Modifier.align(Alignment.Center).size(38.dp).background(Color.Black.copy(alpha = .54f), CircleShape).border(1.2.dp, Color.White.copy(alpha = .7f), CircleShape), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.PlayArrow, null, Modifier.size(24.dp), tint = Color.White) }
                Row(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(start = 6.dp, end = 6.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (plays > 0) Row(Modifier.background(Color.Black.copy(alpha = .54f), RoundedCornerShape(4.dp)).padding(horizontal = 4.dp, vertical = 1.5.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Outlined.PlayArrow, null, Modifier.size(10.dp), tint = Color.White); Spacer(Modifier.width(2.dp)); Text(profileCount("$plays"), fontSize = 10.sp, color = Color.White) }
                    Spacer(Modifier.weight(1f))
                    if (media.duration.isNotEmpty()) Text(media.duration, Modifier.background(Color.Black.copy(alpha = .54f), RoundedCornerShape(4.dp)).padding(horizontal = 4.dp, vertical = 1.5.dp), fontSize = 10.sp, color = Color.White, fontWeight = reviewWeight(FontWeight.Bold))
                }
            }
            Column(Modifier.weight(1f).padding(start = 8.dp, top = 8.dp, end = 8.dp, bottom = 6.dp), verticalArrangement = Arrangement.SpaceBetween) {
                Text(media.title.ifBlank { post.text.ifBlank { "视频动态" } }, fontSize = 12.5.sp, lineHeight = 16.25.sp, fontWeight = reviewWeight(FontWeight.SemiBold), maxLines = 2, overflow = TextOverflow.Ellipsis)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(postTime(post.time, model.option("timeMode", "relative") == "relative", model.bool("weekday"), model.bool("year"), model.bool("timezone"), model.bool("seconds")), Modifier.weight(1f), fontSize = 10.5.sp, color = colors.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (post.likes > 0) { Icon(Icons.Outlined.ThumbUp, null, Modifier.size(11.dp), tint = colors.onSurfaceVariant); Spacer(Modifier.width(2.dp)); Text("${post.likes}", fontSize = 10.sp, color = colors.onSurfaceVariant) }
                }
            }
        }
    }
}

fun matchesProfilePost(post: Post, owner: String, liked: Boolean, year: Int, month: Int): Boolean {
    if (!liked && (post.data.optJSONObject("title")?.optString("text").orEmpty().contains("赞") || (post.uid.isNotBlank() && post.uid != owner && post.repost == null))) return false
    if (year == 0 || post.time.isBlank()) return true
    val date = runCatching { LocalDateTime.parse(post.time, DateTimeFormatter.ofPattern("EEE MMM dd HH:mm:ss Z yyyy", Locale.ENGLISH)) }.getOrNull()
        ?: runCatching { OffsetDateTime.parse(post.time).toLocalDateTime() }.getOrNull()
        ?: runCatching { LocalDateTime.parse(post.time) }.getOrNull()
    return if (date == null) post.time.contains("$year") else date.year == year && (month == 0 || date.monthValue == month)
}

@Composable
fun ProfileScreen(id: String, gallery: (List<Media>, Int) -> Unit) {
    val model = LocalReview.current
    val route = LocalReviewRoute.current
    val preview = route?.profilePreview?.takeIf { it.id == id }
    var user by remember(id, model.uid) { mutableStateOf<User?>(null) }
    var error by remember(id) { mutableStateOf<String?>(null) }
    var retry by remember { mutableIntStateOf(0) }
    var tab by rememberSaveable(id) { mutableIntStateOf(0) }
    var feature by rememberSaveable(id) { mutableIntStateOf(0) }
    var year by rememberSaveable(id) { mutableIntStateOf(0) }
    var month by rememberSaveable(id) { mutableIntStateOf(0) }
    var dates by remember { mutableStateOf(false) }
    val colors = MaterialTheme.colorScheme
    LaunchedEffect(id, model.uid, retry) {
        try { error = null; user = model.repository.profile(model.sessionCookie, id); route?.profile = user; if (route?.key == model.routeStack.lastOrNull()?.key) model.profileUser = user }
        catch (e: CancellationException) { throw e }
        catch (e: Exception) { error = e.message }
    }
    val owner = user?.id ?: id
    val timelineAvailable = user != null || id.matches(Regex("[1-9][0-9]*"))
    val includeLikes = model.bool("profileLikes")
    PagedContent("profile:$owner:$timelineAvailable:$feature:$includeLikes:$year:$month:${model.uid}", { cursor ->
        if (!timelineAvailable) Page(emptyList()) else {
            val page = model.repository.userPosts(model.sessionCookie, owner, cursor.toInt().coerceAtLeast(1), feature = feature, longText = false)
            page.copy(items = page.items.filter { matchesProfilePost(it, owner, includeLikes, year, month) })
        }
    }, Post::id, header = {
        item {
            (user ?: preview)?.let { person ->
                val avatar = preview?.avatar.orEmpty().ifBlank { person.avatar }
                Surface(Modifier.padding(start = 12.dp, end = 12.dp, top = 8.dp, bottom = 10.dp), shape = RoundedCornerShape(16.dp), color = colors.surfaceContainerLowest) {
                    Column(Modifier.fillMaxWidth().padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Avatar(person.name, avatar, Modifier.size(64.dp).reviewClickable { if (avatar.isNotBlank()) gallery(listOf(Media(person.avatar.ifBlank { avatar })), 0) }, verified = person.isVerified, verifiedType = person.verifiedType, shareWithProfile = true)
                            Spacer(Modifier.width(16.dp))
                            Column(Modifier.weight(1f)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(person.name, Modifier.weight(1f, fill = false), fontSize = 18.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    if (person.gender in setOf("f", "m")) Icon(if (person.gender == "f") Icons.Rounded.Female else Icons.Rounded.Male, null, Modifier.padding(start = 4.dp).size(16.dp), tint = if (person.gender == "f") Color(0xFFFF4081) else Color(0xFF448AFF))
                                }
                                Spacer(Modifier.height(4.dp)); Text("UID: ${person.id}", fontSize = 12.sp, color = colors.onSurfaceVariant)
                                if (person.ip.isNotBlank()) Text("IP属地: ${person.ip}", fontSize = 11.sp, color = colors.onSurfaceVariant.copy(alpha = .8f))
                            }
                            if (user != null && owner != model.uid) {
                                val follow = { model.mutate { model.repository.interact(model.sessionCookie, "follow", owner, !person.following); user = person.copy(following = !person.following) }; Unit }
                                if (model.actionBusy) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                                else CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides 40.dp) {
                                    if (person.following) OutlinedButton(onClick = hapticClick(follow), modifier = Modifier.height(32.dp), contentPadding = PaddingValues(start = 16.dp, end = 24.dp), shape = RoundedCornerShape(20.dp), border = BorderStroke(1.dp, colors.outline), colors = ButtonDefaults.outlinedButtonColors(contentColor = colors.primary)) { Icon(Icons.Rounded.Check, null, Modifier.size(14.dp)); Spacer(Modifier.width(8.dp)); Text(if (person.followMe) "互相关注" else "已关注") }
                                    else Button(onClick = hapticClick(follow), modifier = Modifier.height(32.dp), contentPadding = PaddingValues(start = 16.dp, end = 24.dp), shape = RoundedCornerShape(20.dp)) { Icon(Icons.Rounded.Add, null, Modifier.size(16.dp)); Spacer(Modifier.width(8.dp)); Text("关注") }
                                }
                            }
                        }
                        if (person.description.isNotBlank()) Text(person.description, Modifier.padding(top = 12.dp), fontSize = 13.sp, lineHeight = 17.55.sp, color = colors.onSurfaceVariant)
                        if (user != null) Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(24.dp), verticalAlignment = Alignment.CenterVertically) {
                            listOf(Triple(person.friends, "关注", "relations:$owner:false"), Triple(person.followers, "粉丝", "relations:$owner:true"), Triple(person.posts, "微博", "")).forEach { (count, label, route) ->
                                Row(Modifier.reviewClickable(enabled = route.isNotBlank()) { model.navigate(route) }.then(if (route.isNotBlank()) Modifier.padding(4.dp) else Modifier), verticalAlignment = Alignment.CenterVertically) { Text(profileCount(count), fontSize = 14.sp, fontWeight = reviewWeight(FontWeight.Bold)); Spacer(Modifier.width(4.dp)); Text(label, fontSize = 12.sp, color = colors.onSurfaceVariant) }
                            }
                        }
                    }
                }
            }
            error?.let { ErrorNotice(it) { retry++ } }
            Row(Modifier.padding(horizontal = 12.dp).clip(RoundedCornerShape(12.dp)).background(colors.surfaceContainerHighest.copy(alpha = .35f))) {
                listOf("微博", "相册", "视频").forEachIndexed { i, title ->
                    Box(Modifier.weight(1f).height(48.dp).clip(RoundedCornerShape(10.dp)).background(if (tab == i) colors.primaryContainer else Color.Transparent).selectable(tab == i, role = Role.Tab, onClick = hapticClick { tab = i }), contentAlignment = Alignment.Center) { Text(title, fontSize = 14.sp, fontWeight = reviewWeight(if (tab == i) FontWeight.Bold else FontWeight.Medium), color = if (tab == i) colors.onPrimaryContainer else colors.onSurfaceVariant) }
                }
            }
            if (tab == 0) BoxWithConstraints(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 10.dp, bottom = 6.dp)) {
                val viewport = maxWidth
                Row(Modifier.horizontalScroll(rememberScrollState()).widthIn(min = viewport), verticalAlignment = Alignment.CenterVertically) {
                listOf("全部", "原创", "图片", "视频").forEachIndexed { i, label ->
                    if (i > 0) Spacer(Modifier.width(6.dp))
                    ProfileFeatureChip(label, feature == i) { feature = i }
                }
                Spacer(Modifier.widthIn(min = 6.dp).weight(1f))
                val selected = year > 0 || month > 0
                Surface(onClick = hapticClick { dates = true }, shape = RoundedCornerShape(16.dp), color = if (selected) colors.primaryContainer else colors.surfaceContainerHighest.copy(alpha = .5f), contentColor = if (selected) colors.onPrimaryContainer else colors.onSurfaceVariant, border = BorderStroke(.8.dp, if (selected) colors.primary else colors.outlineVariant.copy(alpha = .5f))) {
                    Row(Modifier.padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Outlined.CalendarMonth, null, Modifier.size(14.dp)); Spacer(Modifier.width(4.dp)); Text(if (year == 0) "日期筛选" else "${year}年${if (month > 0) "${month}月" else ""}", fontSize = 12.sp, maxLines = 1, softWrap = false, fontWeight = reviewWeight(if (selected) FontWeight.Bold else FontWeight.Normal)) }
                }
                }
            }
        }
    }, body = { posts ->
        if (tab == 0) items(posts, key = Post::id) { PostRow(it, gallery) }
        else if (tab == 1) {
            val photos = posts.flatMap { post -> post.images.mapIndexedNotNull { index, media -> if (media.video.isBlank() || media.live) Triple(post, index, media) else null } }
            if (photos.isEmpty() && posts.isNotEmpty()) item { ProfileEmpty("相册暂无图片") }
            if (photos.isNotEmpty()) item { Spacer(Modifier.height(9.dp)) }
            items(photos.chunked(3)) { row ->
                Row(Modifier.padding(horizontal = 12.dp, vertical = 3.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    row.forEach { (post, index, media) -> Box(Modifier.weight(1f).aspectRatio(1f).clip(RoundedCornerShape(8.dp)).reviewClickable { model.mediaAuthor = post.author; gallery(post.images, index) }) {
                        MediaImage(media, "相册图片", Modifier.fillMaxSize())
                        if (media.live) Row(Modifier.align(Alignment.TopEnd).padding(4.dp).background(Color.Black.copy(alpha = .54f), RoundedCornerShape(4.dp)).padding(horizontal = 5.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.MotionPhotosOn, null, Modifier.size(10.dp), tint = Color.White); Spacer(Modifier.width(2.dp)); Text("LIVE", color = Color.White, fontSize = 9.sp, fontWeight = reviewWeight(FontWeight.Bold)) }
                    } }
                    repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
            if (photos.isNotEmpty()) item { Spacer(Modifier.height(9.dp)) }
        } else {
            val videos = posts.mapNotNull { post -> post.images.firstOrNull { it.video.isNotBlank() && !it.live }?.let { post to it } }
            if (videos.isEmpty() && posts.isNotEmpty()) item { ProfileEmpty("暂无视频动态") }
            if (videos.isNotEmpty()) item { Spacer(Modifier.height(7.dp)) }
            items(videos.chunked(2)) { row ->
                Row(Modifier.padding(horizontal = 12.dp, vertical = 5.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    row.forEach { (post, media) -> ProfileVideoCard(post, media, Modifier.weight(1f).aspectRatio(.72f)) }
                    if (row.size == 1) Spacer(Modifier.weight(1f))
                }
            }
            if (videos.isNotEmpty()) item { Spacer(Modifier.height(7.dp)) }
        }
    }, empty = { ProfileEmpty(when (tab) { 1 -> "相册暂无图片"; 2 -> "暂无视频动态"; else -> "暂无符合条件的微博" }) }) { }
    if (dates) ModalBottomSheet(onDismissRequest = { dates = false }, dragHandle = null, containerColor = colors.surface, shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)) {
        var selectedYear by remember { mutableIntStateOf(year) }; var selectedMonth by remember { mutableIntStateOf(month) }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) { Text("按年份与月份筛选微博", Modifier.weight(1f), fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.Bold)); if (selectedYear > 0 || selectedMonth > 0) TextButton(onClick = hapticClick { year = 0; month = 0; dates = false }) { Text("重置筛选") } }
            Spacer(Modifier.height(12.dp)); Text("选择年份", fontSize = 13.sp, color = Color.Gray)
            Spacer(Modifier.height(8.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { (2026 downTo 2020).forEach { value -> FilterChip(selectedYear == value, hapticClick { selectedYear = if (selectedYear == value) 0 else value }, { Text("${value}年") }, leadingIcon = if (selectedYear == value) { { Icon(Icons.Rounded.Check, null, Modifier.size(18.dp)) } } else null) } }
            Spacer(Modifier.height(14.dp)); Text("选择月份", fontSize = 13.sp, color = Color.Gray)
            Spacer(Modifier.height(8.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) { (1..12).forEach { value -> FilterChip(selectedMonth == value, hapticClick { selectedMonth = if (selectedMonth == value) 0 else value }, { Text("${value}月") }, leadingIcon = if (selectedMonth == value) { { Icon(Icons.Rounded.Check, null, Modifier.size(18.dp)) } } else null) } }
            Button(onClick = hapticClick { year = selectedYear; month = selectedMonth; dates = false }, Modifier.fillMaxWidth().padding(top = 16.dp)) { Text("确定筛选") }
        }
    }
}
