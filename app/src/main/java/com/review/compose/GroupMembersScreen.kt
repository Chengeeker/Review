package com.review.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject

@Composable
fun GroupMembersScreen(id: String) {
    val model = LocalReview.current
    val route = LocalReviewRoute.current; val colors = MaterialTheme.colorScheme
    var members by remember(id, model.uid) { mutableStateOf<List<User>>(emptyList()) }
    val resolved = remember(id, model.uid) { mutableStateMapOf<String, User>() }
    var owner by remember(id) { mutableStateOf("") }
    var admins by remember(id) { mutableStateOf(emptySet<String>()) }
    var search by rememberSaveable(id) { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    var retry by remember { mutableIntStateOf(0) }
    val gate = remember { Semaphore(6) }
    suspend fun resolve(member: User) {
        if (resolved.containsKey(member.id) || model.demo) return
        try { gate.withPermit {
            if (!resolved.containsKey(member.id)) resolved[member.id] = model.repository.chatUser(model.sessionCookie, member.id).copy(joinedAt = member.joinedAt)
        } } catch (e: CancellationException) { throw e } catch (_: Exception) { }
    }
    LaunchedEffect(id, model.uid, retry) {
        loading = true; error = null
        try {
            val data = route?.group ?: if (model.demo) JSONObject() else model.repository.groupInfo(model.sessionCookie, id)
            route?.group = data
            owner = data.optString("owner")
            val array = data.optJSONArray("admins")
            admins = if (array == null) emptySet() else (0 until array.length()).map(array::optString).toSet()
            val all = mutableListOf<User>()
            var cursor = "0"; val seen = mutableSetOf<String>()
            if (!model.demo) do {
                val page = model.repository.groupMembers(model.sessionCookie, id, cursor)
                all += page.items; members = all.distinctBy(User::id)
                val next = page.next
                if (!canContinuePage(cursor, next, page.items.isNotEmpty()) || !seen.add(next)) break
                cursor = next
            } while (all.size < 10000)
            val ids = listOf(owner).filter(String::isNotBlank) + admins + members.map(User::id)
            members = ids.distinct().map { uid -> members.firstOrNull { it.id == uid } ?: User(uid, "", "") }
        } catch (e: CancellationException) { throw e } catch (e: Exception) { error = e.message } finally { loading = false }
        coroutineScope { members.take(50).forEach { launch { resolve(it) } } }
    }
    val query = search.trim()
    val filtered = members.filter { it.id.contains(query) || (resolved[it.id] ?: it).name.contains(query, true) }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp).fillMaxWidth().heightIn(min = 48.dp).background(colors.surfaceContainerHighest.copy(alpha = .5f), RoundedCornerShape(12.dp)), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) { Icon(Icons.Outlined.Search, null, Modifier.size(20.dp), tint = colors.outline) }
            BasicTextField(search, { search = it }, Modifier.weight(1f).padding(vertical = 12.dp), singleLine = true, cursorBrush = SolidColor(colors.primary), textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.onSurface), decorationBox = { input ->
                Box { if (search.isEmpty()) Text("搜索群成员昵称或 UID...", fontSize = 14.sp, color = colors.outline); input() }
            })
            if (query.isNotEmpty()) IconButton(onClick = hapticClick { search = "" }) { Icon(Icons.Outlined.Clear, "清空", Modifier.size(18.dp)) } else Spacer(Modifier.width(12.dp))
        }
        error?.let { ErrorNotice(it) { retry++ } }
        if (loading || filtered.isEmpty()) Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            if (loading) CircularProgressIndicator() else Text(if (query.isEmpty()) "暂无群成员信息" else "未找到相关群成员", color = colors.outline, fontSize = 14.sp)
        } else LazyColumn(Modifier.weight(1f)) {
            items(filtered, key = User::id) { member ->
                LaunchedEffect(member.id) { resolve(member) }
                val user = resolved[member.id] ?: member
                Row(Modifier.fillMaxWidth().reviewClickable { model.openProfile(user) }.heightIn(min = 72.dp).padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Avatar(user.name, user.avatar, Modifier.size(44.dp), shareWithProfile = true); Spacer(Modifier.width(16.dp))
                    Column(Modifier.weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(user.name.ifBlank { "群友 ${user.id}" }, Modifier.weight(1f, fill = false), fontSize = 14.5.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (user.id == owner || user.id in admins) {
                                Spacer(Modifier.width(8.dp))
                                Text(if (user.id == owner) "群主" else "管理员", Modifier.background(if (user.id == owner) Color(0xFFFFA000) else Color(0xFF1E88E5), RoundedCornerShape(4.dp)).padding(horizontal = 6.dp, vertical = 1.5.dp), fontSize = 10.sp, color = Color.White, fontWeight = reviewWeight(FontWeight.Bold))
                            }
                        }
                        Text("UID: ${user.id}", fontSize = 12.sp, color = colors.outline)
                        if (user.joinedAt > 0) Text(java.time.Instant.ofEpochSecond(user.joinedAt).atZone(java.time.ZoneId.systemDefault()).toLocalDate().toString() + " 加群", fontSize = 11.sp, color = colors.outline)
                    }
                }
                ReviewDivider(Modifier.padding(start = 68.dp), thickness = .5.dp)
            }
        }
    }
}

@Composable
fun GroupMembersTitle(route: ReviewRoute) {
    Column(Modifier.padding(start = 16.dp)) {
        Text("群成员", fontSize = 17.sp, fontWeight = reviewWeight(FontWeight.Bold))
        Text("${route.group?.optString("name").orEmpty().ifBlank { "群聊" }} (共 ${route.group?.optInt("member_count") ?: 0} 人)", fontSize = 12.sp, color = MaterialTheme.colorScheme.outline, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
