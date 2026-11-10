package com.review.compose

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject

fun groupQrCode(id: String) = QRCodeWriter().encode("https://weibo.com/p/230491$id", BarcodeFormat.QR_CODE, 0, 0, mapOf(EncodeHintType.MARGIN to 1))

@Composable
fun GroupInfoScreen(id: String) {
    val model = LocalReview.current; val route = LocalReviewRoute.current
    val colors = MaterialTheme.colorScheme; val context = LocalContext.current; val scope = rememberCoroutineScope()
    var info by remember(id, model.uid) { mutableStateOf(route?.group ?: JSONObject()) }
    var members by remember(id, model.uid) { mutableStateOf<List<User>>(emptyList()) }
    var loading by remember(id) { mutableStateOf(!model.demo) }
    var error by remember(id) { mutableStateOf<String?>(null) }
    var retry by remember { mutableIntStateOf(0) }
    var dialog by remember { mutableStateOf("") }
    var exiting by remember { mutableStateOf(false) }
    LaunchedEffect(id, model.uid, retry) {
        if (model.demo) return@LaunchedEffect
        loading = true; error = null
        try {
            coroutineScope {
                val details = async { model.repository.groupInfo(model.sessionCookie, id) }
                val people = async { model.repository.groupMembers(model.sessionCookie, id, "0", 50) }
                info = details.await(); route?.group = info
                members = people.await().items
            }
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) { error = e.message ?: "群资料加载失败" }
        finally { loading = false }
        val owner = info.optString("owner"); val admins = info.optJSONArray("admins")
        val ids = (listOf(owner) + (0 until (admins?.length() ?: 0)).map { admins!!.optString(it) } + members.map(User::id)).filter(String::isNotBlank).distinct().take(15)
        val gate = Semaphore(4)
        val resolved = coroutineScope { ids.map { uid -> async {
            try { gate.withPermit { model.repository.chatUser(model.sessionCookie, uid) } }
            catch (e: CancellationException) { throw e } catch (_: Exception) { null }
        } }.awaitAll().filterNotNull() }
        members = (resolved + members).distinctBy(User::id)
    }
    val name = info.optString("name").ifBlank { route?.contact?.name.orEmpty().ifBlank { "群聊" } }
    val avatar = chatAvatar(info).ifBlank { route?.contact?.avatar.orEmpty() }
    val bulletin = info.optJSONObject("bulletin")?.optString("content").orEmpty().ifBlank { info.optString("notice").ifBlank { "暂无群公告" } }
    fun copy(value: String, label: String) {
        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText(label, value))
        dialog = ""; model.notice = if (label == "群链接") "已复制群链接至剪贴板" else "已复制群公告内容"
    }
    if (loading) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
    else LazyColumn(Modifier.fillMaxSize().background(colors.background), contentPadding = PaddingValues(top = LocalContentTop.current)) {
        error?.let { item { ErrorNotice(it) { retry++ } } }
        item {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Avatar(name, avatar, Modifier.size(56.dp)); Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(name, fontSize = 16.5.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    info.optString("summary").takeIf(String::isNotBlank)?.let { Text(it, Modifier.padding(top = 4.dp), fontSize = 13.5.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, color = colors.onSurfaceVariant) }
                }
            }
            GroupDivider()
            GroupInfoRow("群二维码", onClick = { dialog = "qr" })
            GroupDivider()
            Column(Modifier.fillMaxWidth().reviewClickable { model.navigate("groupMembers:$id"); model.routeStack.last().group = info }.padding(horizontal = 16.dp, vertical = 14.dp)) {
                GroupHeading("群成员(${info.optInt("member_count", members.size)}/${info.optInt("max_member", 3000)})")
                Spacer(Modifier.height(14.dp))
                LazyRow(Modifier.height(76.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    item { Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.size(48.dp).border(1.2.dp, colors.outline.copy(alpha = .4f), CircleShape), contentAlignment = Alignment.Center) { Icon(Icons.Outlined.Add, null, Modifier.size(26.dp), tint = colors.onSurfaceVariant) }
                        Spacer(Modifier.height(6.dp)); Text("添加成员", fontSize = 11.sp, color = colors.onSurfaceVariant)
                    } }
                    items(members, key = User::id) { user -> Column(Modifier.reviewClickable { model.openProfile(user) }, horizontalAlignment = Alignment.CenterHorizontally) {
                        Avatar(user.name, user.avatar, Modifier.size(48.dp), shareWithProfile = true); Spacer(Modifier.height(6.dp))
                        Text(user.name.ifBlank { "群友" }, Modifier.width(54.dp), fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
                    } }
                }
            }
            GroupDivider()
            Column(Modifier.fillMaxWidth().reviewClickable { dialog = "bulletin" }.padding(horizontal = 16.dp, vertical = 14.dp)) {
                GroupHeading("群公告"); Spacer(Modifier.height(8.dp))
                RichText(bulletin, style = MaterialTheme.typography.bodyMedium.copy(fontSize = 13.5.sp, lineHeight = 18.9.sp, color = colors.onSurfaceVariant))
            }
            GroupDivider()
            GroupInfoRow("群微博", onClick = {
                val owner = info.optString("owner")
                if (owner.isBlank()) model.notice = "尚未获取群主资料，请重试" else model.navigate("groupPosts:$owner")
            })
            GroupDivider()
            listOf("置顶聊天" to "pin:${model.uid}:$id", "消息免打扰" to "mute:${model.uid}:$id").forEachIndexed { index, (title, key) ->
                if (index > 0) GroupDivider(Modifier.padding(start = 16.dp))
                Row(Modifier.fillMaxWidth().reviewClickable { model.setOption(key, !model.bool(key)); model.refreshMessages() }.padding(horizontal = 16.dp).heightIn(min = 52.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(title, Modifier.weight(1f), fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.SemiBold))
                    Switch(model.bool(key), hapticChange { model.setOption(key, it); model.refreshMessages() }, Modifier.padding(horizontal = 4.dp))
                }
            }
            GroupDivider(); Spacer(Modifier.height(24.dp))
            Box(Modifier.fillMaxWidth().heightIn(min = 62.dp).reviewClickable(enabled = !exiting) { dialog = "exit" }, contentAlignment = Alignment.Center) {
                Text("退出群聊", fontSize = 15.5.sp, fontWeight = reviewWeight(FontWeight.SemiBold), color = Color(0xFFF44336))
            }
            Spacer(Modifier.height(40.dp))
        }
    }
    if (dialog == "qr") ReviewAlertDialog(onDismissRequest = { dialog = "" }, shape = RoundedCornerShape(16.dp), contentPadding = PaddingValues(20.dp), text = {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(name, avatar, Modifier.size(48.dp)); Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(name, fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text("群号: $id", Modifier.padding(top = 2.dp), fontSize = 12.sp, color = colors.outline)
                }
            }
            Spacer(Modifier.height(20.dp))
            val matrix = remember(id) { groupQrCode(id) }
            Surface(shape = RoundedCornerShape(12.dp), color = Color.White, shadowElevation = 4.dp) {
                Canvas(Modifier.padding(12.dp).size(200.dp).semantics { contentDescription = "群聊二维码" }) {
                    val unit = size.width / matrix.width
                    for (y in 0 until matrix.height) for (x in 0 until matrix.width) if (matrix[x, y]) drawRect(Color.Black, Offset(x * unit, y * unit), Size(unit, unit))
                }
            }
            Spacer(Modifier.height(16.dp)); Text("扫一扫二维码，加入群聊", fontSize = 13.sp, color = colors.outline)
        }
    }, dismissButton = { TextButton(onClick = hapticClick { copy("https://weibo.com/p/230491$id", "群链接") }) { Icon(Icons.Outlined.ContentCopy, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("复制群链接") } }, confirmButton = { Button(onClick = hapticClick { dialog = "" }) { Text("关闭") } })
    if (dialog == "bulletin") ReviewAlertDialog(onDismissRequest = { dialog = "" }, title = { Text("群公告", fontWeight = reviewWeight(FontWeight.Bold)) }, text = {
        RichText(bulletin, modifier = Modifier.verticalScroll(rememberScrollState()), style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.5.sp, lineHeight = 21.75.sp))
    }, dismissButton = { TextButton(onClick = hapticClick { copy(bulletin, "群公告") }) { Icon(Icons.Outlined.ContentCopy, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("复制公告") } }, confirmButton = { Button(onClick = hapticClick { dialog = "" }) { Text("确定") } })
    if (dialog == "exit") ReviewAlertDialog(onDismissRequest = { if (!exiting) dialog = "" }, title = { Text("退出群聊") }, text = { Text("确定要退出群聊 “$name” 吗？") }, dismissButton = { TextButton(enabled = !exiting, onClick = hapticClick { dialog = "" }) { Text("取消") } }, confirmButton = {
        Button(enabled = !exiting, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF44336), contentColor = Color.White), onClick = hapticClick {
            if (model.demo) { dialog = ""; model.navigate("account") } else {
                exiting = true
                scope.launch {
                    try {
                        model.repository.exitGroup(model.sessionCookie, id)
                        model.refreshMessages(); dialog = ""; model.back()
                        if (model.screen == "chat:$id:true") model.back()
                        model.notice = "已退出群聊"
                    } catch (e: CancellationException) { throw e }
                    catch (e: Exception) { dialog = ""; model.notice = e.message ?: "退出结果未确认，请刷新核实" }
                    finally { exiting = false }
                }
            }
        }) { Text(if (exiting) "处理中…" else "确定退出") }
    })
}

@Composable
private fun GroupInfoRow(title: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().reviewClickable(onClick = onClick).heightIn(min = 62.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.SemiBold))
        Icon(Icons.Outlined.ChevronRight, null, tint = MaterialTheme.colorScheme.outline)
    }
}
@Composable
private fun GroupHeading(title: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.SemiBold))
        Icon(Icons.Outlined.ChevronRight, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.outline)
    }
}
@Composable
private fun GroupDivider(modifier: Modifier = Modifier) { Box(modifier.height(1.dp), contentAlignment = Alignment.Center) { ReviewDivider(thickness = .5.dp) } }
