package com.review.compose

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.work.*
import org.json.JSONObject
import java.util.concurrent.TimeUnit

fun notificationPermission(context: Context): Boolean = (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
    (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()

fun scheduleNotifications(context: Context) {
    val prefs = context.getSharedPreferences("preferences", 0)
    val manager = WorkManager.getInstance(context)
    // Reuse the existing work slot when updating the Flutter installation.
    val workName = "review_message_notifications"
    if (!prefs.getBoolean("message_notifications_enabled", false) || prefs.getString("uid", "").isNullOrBlank()) manager.cancelUniqueWork(workName)
    else manager.enqueueUniquePeriodicWork(workName, ExistingPeriodicWorkPolicy.UPDATE,
        PeriodicWorkRequestBuilder<MessageNotificationWorker>(15, TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()).build())
}

fun unreadCount(root: JSONObject, keys: List<String>, depth: Int = 0): Int? {
    if (depth > 12) return null
    for (key in keys) {
        val value = root.opt(key)
        if (value is Number) return value.toLong().coerceIn(0, Int.MAX_VALUE.toLong()).toInt()
        if (value is String) value.toIntOrNull()?.let { return it.coerceAtLeast(0) }
        if (value is JSONObject) unreadCount(value, listOf("unread_count", "count", "unread", "num"), depth + 1)?.let { return it }
    }
    for (key in root.keys()) root.optJSONObject(key)?.let { unreadCount(it, keys, depth + 1)?.let { count -> return count } }
    return null
}

internal suspend fun <T> messagePoll(load: suspend () -> T): T? = try { load() }
catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
catch (_: Exception) { null }

internal fun interactionCounts(root: JSONObject): Map<String, Int> = buildMap {
    val statuses = unreadCount(root, listOf("mention_status", "mentionStatus"))
    val comments = unreadCount(root, listOf("all_mention_cmt", "mention_cmt", "mention_comment", "mentionComment"))
    val mentions = if (statuses != null || comments != null)
        ((statuses ?: 0).toLong() + (comments ?: 0)).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    else unreadCount(root, listOf("mention", "mentions", "at_me"))
    mentions?.let { put("mentions", it) }
    unreadCount(root, listOf("like", "likes", "attitude", "attitudes"))?.let { put("likes", it) }
    unreadCount(root, listOf("cmt", "comment", "comments"))?.let { put("comments", it) }
}

internal fun unreadAfterRead(raw: Int, read: Int): Int = if (raw < read) raw else raw - read

class MessageNotificationWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences("preferences", 0)
        if (!prefs.getBoolean("message_notifications_enabled", false) || !notificationPermission(applicationContext)) return Result.success()
        val uid = prefs.getString("uid", "").orEmpty()
        if (uid.isBlank()) return Result.success()
        return try {
            val cookie = SessionStore(applicationContext).load()
            val native = com.review.weiboauth.WeiboAuthManager(applicationContext)
            val matchingNative = native.hasNativeSessionFor(uid)
            if (cookie.isBlank() && !matchingNative) return Result.success()
            val repository = Repository(native.takeIf { matchingNative })
            repository.api.configureSession(cookie, prefs.getBoolean("mobileOnly", false))
            val reminder = messagePoll { repository.unreadMessages(cookie, uid) }
            val contacts = messagePoll { repository.contacts(cookie) }
            val current = buildMap {
                reminder?.let { putAll(interactionCounts(it)) }
                contacts?.let { rows ->
                    val total = rows.filterNot { it.group && prefs.getBoolean("mute:$uid:${it.id}", false) }
                        .sumOf { it.unread.coerceAtLeast(0).toLong() }
                    put("direct_messages", total.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
                }
            }
            if (current.isEmpty()) return if (runAttemptCount >= 3) Result.failure() else Result.retry()
            // An account switched during the request must never receive the previous account's reminders.
            if (prefs.getString("uid", "") != uid || !prefs.getBoolean("message_notifications_enabled", false)) return Result.success()
            val previous = runCatching { JSONObject(prefs.getString("message_notifications_last_counts_json", "{}").orEmpty()) }.getOrDefault(JSONObject())
            val initialized = prefs.getBoolean("message_notifications_initialized", false) && prefs.getString("message_notifications_user_uid", "") == uid
            if (initialized) {
                val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.createNotificationChannel(NotificationChannel("message_updates", "微博消息提醒", NotificationManager.IMPORTANCE_DEFAULT))
                current.forEach { (key, value) ->
                    val read = prefs.getFloat("read-interaction:$uid:$key", 0f).toInt()
                    val delta = value - maxOf(previous.optInt(key), if (value >= read) read else 0)
                    if (previous.has(key) && delta > 0 && prefs.getBoolean("message_notification_$key", true)) {
                        val title = mapOf("mentions" to "@通知", "likes" to "点赞通知", "comments" to "回复通知", "direct_messages" to "私信通知").getValue(key)
                        val launch = applicationContext.packageManager.getLaunchIntentForPackage(applicationContext.packageName)
                        val pending = launch?.let { PendingIntent.getActivity(applicationContext, key.hashCode(), it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
                        manager.notify(key.hashCode(), Notification.Builder(applicationContext, "message_updates").setSmallIcon(R.mipmap.ic_launcher)
                            .setContentTitle("Review · $title").setContentText("有 $delta 条新消息").setContentIntent(pending).setAutoCancel(true).build())
                    }
                }
            }
            val baseline = if (initialized) previous else JSONObject()
            current.forEach { (key, count) -> baseline.put(key, count) }
            prefs.edit().putString("message_notifications_last_counts_json", baseline.toString())
                .putString("message_notifications_user_uid", uid).putBoolean("message_notifications_initialized", true).apply()
            Result.success()
        } catch (e: kotlinx.coroutines.CancellationException) { throw e }
        catch (_: Exception) { if (runAttemptCount >= 3) Result.failure() else Result.retry() }
    }
}
