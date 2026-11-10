package com.review.compose

import android.Manifest
import android.content.Intent
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect

@Composable
fun NotificationSettingsScreen() {
    val model = LocalReview.current; val context = LocalContext.current; val colors = MaterialTheme.colorScheme
    var permission by remember { mutableStateOf(notificationPermission(context)) }
    var requesting by remember { mutableStateOf(false) }
    var enableAfterPermission by remember { mutableStateOf(false) }
    fun enable(value: Boolean) {
        if (model.bool("message_notifications_enabled") != value) model.setOption("message_notifications_initialized", false)
        model.setOption("message_notifications_enabled", value); scheduleNotifications(context)
    }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        permission = granted && notificationPermission(context); requesting = false
        if (permission && enableAfterPermission) enable(true)
        else if (!permission) { enable(false); if (enableAfterPermission) model.notice = "未授予通知权限，无法开启消息提醒" }
        enableAfterPermission = false
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        permission = notificationPermission(context)
        if (!permission && model.bool("message_notifications_enabled")) enable(false)
        if (permission && enableAfterPermission) { enable(true); enableAfterPermission = false }
    }
    LaunchedEffect(Unit) { if (Build.VERSION.SDK_INT >= 33 && !permission) { requesting = true; launcher.launch(Manifest.permission.POST_NOTIFICATIONS) } }
    fun changeMaster(value: Boolean) {
        if (value && !notificationPermission(context)) {
            enableAfterPermission = true
            if (Build.VERSION.SDK_INT >= 33) { requesting = true; launcher.launch(Manifest.permission.POST_NOTIFICATIONS) }
            else context.startActivity(Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName))
        } else enable(value)
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 8.dp + LocalContentTop.current, bottom = 24.dp)) {
        SettingsCard {
            val master = model.bool("message_notifications_enabled") && permission
            SettingsTile(headlineContent = { Text("订阅消息提醒", fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.SemiBold), color = colors.onSurface.copy(alpha = if (requesting) .38f else 1f)) },
                supportingContent = { Text(if (permission) "允许后台定期检查微博未读消息" else if (requesting) "正在请求系统通知权限…" else "未授予系统通知权限", fontSize = 14.sp, color = if (requesting) colors.onSurface.copy(alpha = .38f) else colors.onSurfaceVariant) },
                leadingContent = { Icon(Icons.Outlined.NotificationsActive, null, tint = colors.primary) }, trailingContent = { Switch(master, null, modifier = Modifier.padding(horizontal = 4.dp), enabled = !requesting) },
                modifier = Modifier.reviewToggleable(master, !requesting, ::changeMaster).padding(vertical = 3.dp))
            val icons = listOf(Icons.Outlined.AlternateEmail, Icons.Outlined.FavoriteBorder, Icons.Outlined.ChatBubbleOutline, Icons.Outlined.Forum)
            val keys = listOf("mentions", "likes", "comments", "direct_messages")
            val titles = listOf("@通知", "点赞通知", "回复通知", "私信通知")
            val subtitles = listOf("有人在微博或评论中提及我", "收到新的赞", "收到新的评论或回复", "私信及未设置免打扰的群聊")
            keys.forEachIndexed { i, key ->
                val checked = model.bool("message_notification_$key", true)
                fun update(value: Boolean) { model.setOption("message_notification_$key", value); scheduleNotifications(context) }
                val foreground = colors.onSurface.copy(alpha = if (master) 1f else .38f)
                SettingsTile(headlineContent = { Text(titles[i], fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.SemiBold), color = foreground) },
                    supportingContent = { Text(subtitles[i], fontSize = 14.sp, color = if (master) colors.onSurfaceVariant else foreground) },
                    leadingContent = { Icon(icons[i], null, tint = if (master) colors.onSurfaceVariant else foreground) }, trailingContent = { Switch(checked, null, modifier = Modifier.padding(horizontal = 4.dp), enabled = master) },
                    modifier = Modifier.reviewToggleable(checked, master, ::update).padding(vertical = 3.dp))
            }
        }
        Text("后台提醒采用 Android 周期任务轮询，系统通常至少间隔 15 分钟执行一次；省电策略、网络状态可能造成更长延迟。提醒只在本机读取未读计数，不在通知中展示微博正文。", Modifier.padding(horizontal = 8.dp, vertical = 12.dp), fontSize = 14.sp, lineHeight = 20.3.sp, color = colors.onSurfaceVariant)
    }
}
