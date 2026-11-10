package com.review.compose

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.CopyAll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun PreferencesGroup(title: String, content: @Composable ColumnScope.() -> Unit) {
    Text(title, Modifier.padding(horizontal = 16.dp).padding(bottom = 12.dp), style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant)
    SettingsCard(content)
    Spacer(Modifier.height(32.dp))
}
@Composable
fun Preference(title: String, icon: ImageVector? = null, subtitle: String = "", onClick: () -> Unit) {
    SettingsTile(headlineContent = { Text(title, fontSize = 15.sp, lineHeight = 20.25.sp) }, supportingContent = if (subtitle.isBlank()) null else {{ Text(subtitle, fontSize = 12.5.sp, lineHeight = 17.5.sp) }},
        leadingContent = icon?.let { { Icon(it, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) } },
        trailingContent = { Icon(Icons.Outlined.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
        modifier = Modifier.reviewClickable(onClick = onClick))
}
@Composable
fun SettingsScreen(model: ReviewModel) {
    var dialog by remember { mutableStateOf("") }
    val top = WindowInsets.safeDrawing.asPaddingValues().calculateTopPadding()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = top + 20.dp, bottom = rootScrollBottom(model))) {
        PreferencesGroup("偏好与功能") {
            Preference("个性化", Icons.Outlined.Palette) { model.navigate("theme") }
            Preference("微博样式", Icons.Outlined.Style) { model.navigate("style") }
            Preference("订阅消息提醒", Icons.Outlined.NotificationsActive) { model.navigate("notifications") }
        }
        PreferencesGroup("存储与备份") {
            Preference("存储设置", Icons.Outlined.FolderOpen) { model.navigate("storage") }
            Preference("缓存管理", Icons.Outlined.CleaningServices) { model.navigate("cache") }
            Preference("WebDAV备份", Icons.Outlined.CloudSync) { model.navigate("backup") }
        }
        PreferencesGroup("账号设置") {
            if (model.uid.isBlank()) Preference("登录账号", Icons.Outlined.Login) { model.navigate("account") }
            else {
                Preference("检测账号凭据有效性", Icons.Outlined.VerifiedUser, "${model.me?.name ?: "已登录用户"} · UID ${model.uid}") {
                    model.mutate { model.checkAccount() }
                }
                if (model.sessionCookie.isBlank()) Preference("导入 Cookie", Icons.Outlined.Key) { model.navigate("account") }
                else Preference("导出账号凭据 / Cookie", Icons.Outlined.Key) { dialog = "export" }
                Preference("退出登录", Icons.Outlined.Logout) { dialog = "logout" }
            }
        }
        PreferencesGroup("关于与支持") { Preference("关于 Review", Icons.Outlined.Info, "版本 ${BuildConfig.VERSION_NAME}") { dialog = "about" } }
    }
    when (dialog) {
        "about" -> AboutDialog { dialog = "" }
        "export" -> AccountCredentialsSheet(model.me?.name.orEmpty(), model.uid, model.sessionCookie,
            onCopied = { model.notice = it }, onDismiss = { dialog = "" })
        "logout" -> ReviewAlertDialog(onDismissRequest = { dialog = "" }, title = { Text("确认退出登录？") },
            text = { Text("退出登录后将彻底清理本地所有 Cookie、会话凭据及 WebView 状态。") },
            confirmButton = { TextButton(onClick = hapticClick { model.logout(); dialog = "" }) { Text("退出") } },
            dismissButton = { TextButton(onClick = hapticClick { dialog = "" }) { Text("取消") } })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AccountCredentialsSheet(nickname: String, uid: String, cookie: String, onCopied: (String) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val colors = MaterialTheme.colorScheme
    val sub = remember(cookie) {
        cookie.splitToSequence(';').firstNotNullOfOrNull { entry ->
            if (entry.substringBefore('=').trim().equals("SUB", ignoreCase = true))
                entry.substringAfter('=', "").trim().takeIf { it.isNotEmpty() && it != "deleted" }
            else null
        }.orEmpty()
    }
    fun copy(value: String, label: String, notice: String) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText(label, value).apply {
            if (Build.VERSION.SDK_INT >= 33) description.extras = PersistableBundle().apply {
                putBoolean("android.content.extra.IS_SENSITIVE", true)
            }
        })
        onDismiss()
        onCopied(notice)
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("导出账号凭据 / Cookie", Modifier.weight(1f, fill = false), fontSize = 16.sp, fontWeight = FontWeight.Bold)
                IconButton(onClick = hapticClick(onDismiss)) { Icon(Icons.Rounded.Close, "关闭") }
            }
            Spacer(Modifier.height(8.dp))
            Text("当前账号: ${nickname.ifBlank { "未命名" }} (UID: ${uid.ifBlank { "未知 UID" }})",
                fontSize = 13.sp, color = colors.primary, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(14.dp))
            CredentialCopyBlock("SUB 核心令牌 (用于轻量鉴权)", sub, 60, "未检测到 SUB 凭据", "复制 SUB", Icons.Rounded.ContentCopy) {
                copy(sub, "SUB", "已复制 SUB 凭据到剪贴板")
            }
            Spacer(Modifier.height(12.dp))
            CredentialCopyBlock("完整 Cookie 字符串 (Full Session)", cookie, 80, "未检测到完整 Cookie", "复制全部", Icons.Rounded.CopyAll) {
                copy(cookie, "Cookie", "已复制完整 Cookie 字符串到剪贴板")
            }
            Spacer(Modifier.height(14.dp))
        }
    }
}

@Composable
private fun CredentialCopyBlock(title: String, value: String, previewLength: Int, empty: String, action: String, icon: ImageVector, onCopy: () -> Unit) {
    Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = .5f), RoundedCornerShape(12.dp)).padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, Modifier.weight(1f), fontSize = 13.sp, fontWeight = FontWeight.Bold)
            TextButton(onClick = hapticClick(onCopy), enabled = value.isNotBlank()) {
                Icon(icon, null, Modifier.size(14.dp))
                Spacer(Modifier.width(6.dp))
                Text(action)
            }
        }
        val preview = if (value.length > previewLength) value.take(previewLength) + "..." else value
        Text(preview.ifBlank { empty }, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
    }
}
@Composable
fun TogglePreference(title: String, key: String, default: Boolean = false, subtitle: String = "") {
    val model = LocalReview.current
    ReviewListItem(headlineContent = { Text(title) }, supportingContent = if (subtitle.isBlank()) null else {{ Text(subtitle) }},
        trailingContent = { Switch(model.bool(key, default), hapticChange { model.setOption(key, it) }) }, colors = ListItemDefaults.colors(containerColor = Color.Transparent))
}
