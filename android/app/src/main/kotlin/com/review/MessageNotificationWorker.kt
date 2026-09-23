package com.review

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class MessageNotificationWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {
    private val preferences =
        appContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    override fun doWork(): Result {
        if (!preferences.getBoolean("flutter.message_notifications_enabled", false)) {
            return Result.success()
        }
        if (!canPostNotifications()) return Result.success()

        val cookie = readCookie()
        if (cookie.isBlank()) return Result.success()

        return try {
            val reminder = requestJson("https://weibo.com/ajax/remind/unread", cookie)
                ?: return Result.retry()
            val contacts = requestJson(
                "https://api.weibo.com/webim/2/direct_messages/contacts.json",
                cookie,
            ) ?: return Result.retry()

            val mentionStatus = findCount(reminder, listOf("mention_status", "mentionStatus"))
            val mentionComments = findCount(
                reminder,
                listOf("mention_cmt", "mention_comment", "mentionComment"),
            )
            val mentions = if (mentionStatus != null || mentionComments != null) {
                (mentionStatus ?: 0) + (mentionComments ?: 0)
            } else {
                findCount(reminder, listOf("mention", "mentions", "at_me")) ?: 0
            }
            val likes = findCount(reminder, listOf("like", "likes", "attitude", "attitudes")) ?: 0
            val comments = findCount(reminder, listOf("cmt", "comment", "comments")) ?: 0
            val directMessages = unreadDirectMessages(contacts)
            val current = mapOf(
                "mentions" to mentions,
                "likes" to likes,
                "comments" to comments,
                "directMessages" to directMessages,
            )

            val currentUid = preferences.getString("flutter.user_uid", "").orEmpty()
            val previousUid = preferences.getString(
                "flutter.message_notifications_user_uid",
                "",
            ).orEmpty()
            val initialized = currentUid.isNotBlank() &&
                currentUid == previousUid &&
                preferences.getBoolean("flutter.message_notifications_initialized", false)
            val previous = readCountMap("flutter.message_notifications_last_counts_json")
            if (initialized) {
                notifyIfIncreased(
                    "mentions",
                    current.getValue("mentions"),
                    previous["mentions"] ?: 0,
                    preferences.getBoolean("flutter.message_notification_mentions", true),
                    "@通知",
                )
                notifyIfIncreased(
                    "likes",
                    current.getValue("likes"),
                    previous["likes"] ?: 0,
                    preferences.getBoolean("flutter.message_notification_likes", true),
                    "点赞通知",
                )
                notifyIfIncreased(
                    "comments",
                    current.getValue("comments"),
                    previous["comments"] ?: 0,
                    preferences.getBoolean("flutter.message_notification_comments", true),
                    "回复通知",
                )
                notifyIfIncreased(
                    "directMessages",
                    current.getValue("directMessages"),
                    previous["directMessages"] ?: 0,
                    preferences.getBoolean(
                        "flutter.message_notification_direct_messages",
                        true,
                    ),
                    "私信通知",
                )
            }

            preferences.edit()
                .putString("flutter.message_notifications_last_counts_json", JSONObject(current).toString())
                .putBoolean("flutter.message_notifications_initialized", true)
                .putString("flutter.message_notifications_user_uid", currentUid)
                .apply()
            Result.success()
        } catch (_: Exception) {
            Result.retry()
        }
    }

    private fun canPostNotifications(): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(
                applicationContext,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) return false
        val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return Build.VERSION.SDK_INT < 24 || manager.areNotificationsEnabled()
    }

    private fun readCookie(): String {
        val full = preferences.getString("flutter.weibo_full_cookie", "").orEmpty()
        if (full.isNotBlank()) return full

        val merged = linkedMapOf<String, String>()
        listOf(
            "flutter.weibo_desktop_cookie",
            "flutter.weibo_mobile_cookie",
            "flutter.weibo_sub_cookie",
            "flutter.weibo_subp_cookie",
        ).forEach { key ->
            preferences.getString(key, "").orEmpty()
                .split(';')
                .map(String::trim)
                .filter(String::isNotEmpty)
                .forEach { token ->
                    val separator = token.indexOf('=')
                    if (separator > 0) {
                        merged.putIfAbsent(token.substring(0, separator).trim(), token)
                    }
                }
        }
        return merged.values.joinToString("; ")
    }

    private fun requestJson(url: String, cookie: String): JSONObject? {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "GET"
            connection.connectTimeout = 15_000
            connection.readTimeout = 15_000
            connection.setRequestProperty("Cookie", cookie)
            connection.setRequestProperty("Accept", "application/json, text/plain, */*")
            connection.setRequestProperty("X-Requested-With", "XMLHttpRequest")
            connection.setRequestProperty("Referer", "https://weibo.com/")
            connection.setRequestProperty(
                "User-Agent",
                "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 " +
                    "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
            )
            val code = connection.responseCode
            if (code !in 200..299) return null
            val body = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            return JSONObject(body)
        } finally {
            connection.disconnect()
        }
    }

    private fun unreadDirectMessages(response: JSONObject): Int {
        val contacts = response.optJSONArray("contacts")
            ?: response.optJSONObject("data")?.optJSONArray("contacts")
            ?: JSONArray()
        val encodedMutedIds = preferences.getString("flutter.muted_message_group_ids", "").orEmpty()
        val muted = try {
            val prefix = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu!"
            val json = if (encodedMutedIds.startsWith(prefix)) {
                encodedMutedIds.removePrefix(prefix)
            } else {
                "[]"
            }
            val ids = JSONArray(json)
            (0 until ids.length())
                .mapNotNull { ids.optString(it).takeIf(String::isNotBlank) }
                .toSet()
        } catch (_: Exception) {
            emptySet()
        }

        var total = 0
        for (index in 0 until contacts.length()) {
            val contact = contacts.optJSONObject(index) ?: continue
            val user = contact.optJSONObject("user") ?: JSONObject()
            val id = user.optString(
                "id",
                user.optString("idstr", contact.optString("id", contact.optString("user_id"))),
            ).orEmpty()
            val name = user.optString("name", user.optString("screen_name")).orEmpty()
            val groupFlag = contact.opt("is_group")
            val isGroup = groupFlag == true || groupFlag?.toString() == "1" ||
                id.length > 12 || name.contains("群") || name.contains("交流")
            if (isGroup && id in muted) continue
            total += parseCount(contact.opt("unread_count"))
        }
        return total
    }

    private fun notifyIfIncreased(
        category: String,
        current: Int,
        previous: Int,
        enabled: Boolean,
        title: String,
    ) {
        val delta = current - previous
        if (!enabled || delta <= 0) return
        val context = applicationContext
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "weibo_message_updates"
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(channelId) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "微博消息提醒",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                context,
                category.hashCode(),
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder.setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Review · $title")
            .setContentText("有 $delta 条新消息")
            .setAutoCancel(true)
        if (pendingIntent != null) builder.setContentIntent(pendingIntent)
        manager.notify(category.hashCode(), builder.build())
    }

    private fun readCountMap(key: String): Map<String, Int> {
        val json = preferences.getString(key, null) ?: return emptyMap()
        return try {
            val objectValue = JSONObject(json)
            objectValue.keys().asSequence().associateWith { parseCount(objectValue.opt(it)) }
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun findCount(root: JSONObject, keys: List<String>): Int? {
        keys.forEach { key ->
            if (root.has(key)) return parseOptionalCount(root.opt(key))
        }
        val iterator = root.keys()
        while (iterator.hasNext()) {
            val nested = root.optJSONObject(iterator.next()) ?: continue
            val value = findCount(nested, keys)
            if (value != null) return value
        }
        return null
    }

    private fun parseOptionalCount(value: Any?): Int? {
        if (value is Number) return value.toInt().coerceAtLeast(0)
        if (value is String) return value.toIntOrNull()?.coerceAtLeast(0)
        if (value is JSONObject) {
            listOf("unread_count", "count", "unread", "num").forEach { key ->
                if (value.has(key)) return parseOptionalCount(value.opt(key))
            }
        }
        return null
    }

    private fun parseCount(value: Any?): Int = parseOptionalCount(value) ?: 0
}
