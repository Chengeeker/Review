package com.review

import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.Manifest
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.media.AudioManager
import android.provider.Settings
import android.view.View
import android.view.WindowInsets
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit
import java.util.concurrent.Executors
import com.review.weiboauth.WeiboAuthManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.sharelite/cookies"
    private val WEIBO_AUTH_CHANNEL = "com.review/weibo_auth"
    private val MESSAGE_NOTIFICATIONS_CHANNEL = "com.review/message_notifications"
    private val MESSAGE_NOTIFICATION_WORK = "review_message_notifications"
    private var methodChannel: MethodChannel? = null
    private val weiboAuthExecutor = Executors.newSingleThreadExecutor()
    @Volatile private var weiboAuthManager: WeiboAuthManager? = null
    private var initialUrl: String? = null
    private var notificationPermissionResult: MethodChannel.Result? = null

    private fun getWeiboAuthManager(): WeiboAuthManager {
        weiboAuthManager?.let { return it }
        return synchronized(this) {
            weiboAuthManager ?: WeiboAuthManager(applicationContext).also { weiboAuthManager = it }
        }
    }

    private fun submitWeiboAuth(
        result: MethodChannel.Result,
        operation: (WeiboAuthManager) -> Any?,
    ) {
        weiboAuthExecutor.execute {
            try {
                val value = operation(getWeiboAuthManager())
                runOnUiThread {
                    try {
                        result.success(value)
                    } catch (_: Throwable) {}
                }
            } catch (error: Throwable) {
                completeWeiboAuthError(result, error)
            }
        }
    }

    private fun completeWeiboAuthError(result: MethodChannel.Result, error: Throwable) {
        val serverMsg = generateSequence(error) { it.cause }
            .mapNotNull { (it as? com.review.weiboauth.WeiboApi.ApiFailure)?.serverMsg?.takeIf { msg -> msg.isNotBlank() } }
            .firstOrNull()

        val causes = generateSequence(error) { it.cause }.take(3).toList()
        val errorTypes = causes.joinToString(" → ") { it.javaClass.simpleName }
        val category = generateSequence(error) { it.cause }
            .mapNotNull { (it as? com.review.weiboauth.WeiboApi.ApiFailure)?.category }
            .firstOrNull()
            ?: error.message?.takeIf {
                it in setOf(
                    "sms_send_rejected",
                    "sms_challenge_missing",
                    "captcha_required",
                    "session_fields_missing",
                    "http_or_response_error",
                )
            } ?: "native_auth_failed"

        val message = when {
            !serverMsg.isNullOrBlank() -> serverMsg
            category == "sms_send_rejected" -> "微博未能发送验证码，请检查手机号或稍后重试"
            category == "sms_challenge_missing" -> "微博没有返回验证码校验信息，请稍后重试"
            category == "captcha_required" -> "微博要求额外安全验证，请稍后重试或先使用官方客户端验证"
            category == "session_fields_missing" -> "微博未返回完整登录会话，请重试"
            category == "http_or_response_error" -> "微博服务暂时不可用，请检查网络后重试"
            else -> when {
                causes.any { it is LinkageError } ->
                    "微博 Android 登录组件加载失败（$errorTypes），请截图反馈"
                causes.any { it is java.io.IOException } ->
                    "连接微博验证码服务失败（$errorTypes），请确认该服务可访问"
                else -> "微博登录初始化或请求失败（$errorTypes），请截图反馈"
            }
        }
        runOnUiThread {
            try {
                result.error("WEIBO_AUTH_$category", message, null)
            } catch (_: Throwable) {}
        }
    }

    private fun loginInputError(result: MethodChannel.Result, message: String) {
        result.error("INVALID_ARGUMENT", message, null)
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
                try {
                    val crashFile = java.io.File(filesDir, "latest_crash.txt")
                    val sw = java.io.StringWriter()
                    val pw = java.io.PrintWriter(sw)
                    throwable.printStackTrace(pw)
                    crashFile.writeText("Time: ${java.util.Date()}\nThread: ${thread.name}\n$sw")
                } catch (_: Throwable) {}
                defaultHandler?.uncaughtException(thread, throwable)
            }
        } catch (_: Throwable) {}
        handleIntent(intent)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: android.content.Intent?) {
        val data = intent?.dataString
        if (!data.isNullOrEmpty()) {
            initialUrl = data
            try {
                methodChannel?.invokeMethod("onDeepLinkOpened", data)
            } catch (_: Exception) {}
        }
    }

    private fun getSystemFontWeightAdjustment(): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val adj = resources.configuration.fontWeightAdjustment
            if (adj != Configuration.FONT_WEIGHT_ADJUSTMENT_UNDEFINED) {
                return adj
            }
        }
        try {
            val isBold = Settings.Secure.getInt(contentResolver, "accessibility_display_bold_text_enabled", 0) == 1
            if (isBold) return 300
        } catch (_: Exception) {}
        return 0
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        try {
            val adj = getSystemFontWeightAdjustment()
            methodChannel?.invokeMethod("onFontWeightAdjustmentChanged", adj)
        } catch (_: Exception) {}
    }

    private fun setScreenRefreshRateMode(modeIndex: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        runOnUiThread {
            try {
                val win = window ?: return@runOnUiThread
                val params = win.attributes

                if (modeIndex == 0) {
                    params.preferredDisplayModeId = 0
                    params.preferredRefreshRate = 0f
                    win.attributes = params
                    return@runOnUiThread
                }

                val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay
                val supportedModes = currentDisplay?.supportedModes

                var targetFps = 0f
                var is1080p = false

                when (modeIndex) {
                    1 -> { targetFps = 120f; is1080p = false }
                    2 -> { targetFps = 90f;  is1080p = false }
                    3 -> { targetFps = 72f;  is1080p = false }
                    4 -> { targetFps = 60f;  is1080p = false }
                    5 -> { targetFps = 120f; is1080p = true }
                    6 -> { targetFps = 90f;  is1080p = true }
                    7 -> { targetFps = 72f;  is1080p = true }
                    8 -> { targetFps = 60f;  is1080p = true }
                }

                if (supportedModes != null && supportedModes.isNotEmpty()) {
                    val maxNativeWidth = supportedModes.maxOf { Math.min(it.physicalWidth, it.physicalHeight) }
                    val targetWidth = if (is1080p) 1080 else maxNativeWidth

                    var matchedMode = supportedModes.find { mode ->
                        val w = Math.min(mode.physicalWidth, mode.physicalHeight)
                        val isW = if (is1080p) w == 1080 else w == maxNativeWidth
                        val isF = Math.abs(mode.refreshRate - targetFps) < 2.0f
                        isW && isF
                    }

                    if (matchedMode == null) {
                        matchedMode = supportedModes.find { mode ->
                            Math.abs(mode.refreshRate - targetFps) < 2.0f
                        }
                    }

                    if (matchedMode != null) {
                        params.preferredDisplayModeId = matchedMode.modeId
                    }
                }

                params.preferredRefreshRate = targetFps
                win.attributes = params
            } catch (_: Exception) {}
        }
    }

    private fun setImageGalleryStatusBarVisible(visible: Boolean) {
        runOnUiThread {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val controller = window.insetsController ?: return@runOnUiThread
                    controller.systemBarsBehavior =
                        android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                    if (visible) {
                        controller.show(WindowInsets.Type.statusBars())
                    } else {
                        controller.hide(WindowInsets.Type.statusBars())
                    }
                } else {
                    val decorView = window.decorView
                    val currentFlags = decorView.systemUiVisibility
                    decorView.systemUiVisibility = if (visible) {
                        currentFlags and View.SYSTEM_UI_FLAG_FULLSCREEN.inv()
                    } else {
                        currentFlags or View.SYSTEM_UI_FLAG_FULLSCREEN
                    }
                }
            } catch (_: Exception) {}
        }
    }

    private fun canPostNotifications(): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) return false
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        return Build.VERSION.SDK_INT < 24 || manager.areNotificationsEnabled()
    }

    private fun syncMessageNotificationWork() {
        val preferences = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val enabled = preferences.getBoolean("flutter.message_notifications_enabled", false)
        val workManager = WorkManager.getInstance(applicationContext)
        if (!enabled || !canPostNotifications()) {
            workManager.cancelUniqueWork(MESSAGE_NOTIFICATION_WORK)
            return
        }

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
        val request = PeriodicWorkRequestBuilder<MessageNotificationWorker>(
            15,
            TimeUnit.MINUTES,
        ).setConstraints(constraints).build()
        workManager.enqueueUniquePeriodicWork(
            MESSAGE_NOTIFICATION_WORK,
            ExistingPeriodicWorkPolicy.REPLACE,
            request,
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val mChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = mChannel
        mChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setScreenRefreshRateMode" -> {
                    val mode = call.argument<Int>("mode") ?: 0
                    setScreenRefreshRateMode(mode)
                    result.success(true)
                }
                "setImageGalleryStatusBarVisible" -> {
                    setImageGalleryStatusBarVisible(call.argument<Boolean>("visible") ?: true)
                    result.success(true)
                }
                "getSupportedDisplayModes" -> {
                    try {
                        val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay
                        val modes = currentDisplay?.supportedModes
                        val list = modes?.map { mode ->
                            mapOf(
                                "modeId" to mode.modeId,
                                "width" to Math.min(mode.physicalWidth, mode.physicalHeight),
                                "height" to Math.max(mode.physicalWidth, mode.physicalHeight),
                                "refreshRate" to mode.refreshRate.toDouble()
                            )
                        } ?: emptyList<Map<String, Any>>()
                        result.success(list)
                    } catch (e: Exception) {
                        result.success(emptyList<Map<String, Any>>())
                    }
                }
                "getInitialUrl" -> {
                    val url = initialUrl
                    initialUrl = null
                    result.success(url)
                }
                "getFontWeightAdjustment" -> {
                    try {
                        val adj = getSystemFontWeightAdjustment()
                        result.success(adj)
                    } catch (e: Exception) {
                        result.success(0)
                    }
                }
                "getNativeCookies" -> {
                    result.success("")
                }
                "getNativeCookiesByDomain" -> {
                    result.success(emptyMap<String, String>())
                }
                "clearNativeCookies" -> {
                    result.success(true)
                }
                "getLatestCrashLog" -> {
                    try {
                        val crashFile = java.io.File(filesDir, "latest_crash.txt")
                        if (crashFile.exists()) {
                            result.success(crashFile.readText())
                        } else {
                            result.success(null)
                        }
                    } catch (_: Throwable) {
                        result.success(null)
                    }
                }
                "getSystemLocation" -> {
                    try {
                        val hasFine = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                        val hasCoarse = checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
                        if (!hasFine && !hasCoarse) {
                            requestPermissions(arrayOf(
                                android.Manifest.permission.ACCESS_FINE_LOCATION,
                                android.Manifest.permission.ACCESS_COARSE_LOCATION
                            ), 1001)
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
                        var bestLocation: Location? = null
                        for (provider in lm.getProviders(true)) {
                            val location = lm.getLastKnownLocation(provider) ?: continue
                            if (bestLocation == null || location.accuracy < bestLocation.accuracy) {
                                bestLocation = location
                            }
                        }

                        if (bestLocation == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        // The official web picker opens with an empty q and
                        // lets /ajax/statuses/place return nearby POIs. Do not
                        // turn Android reverse-geocoding into a city-name
                        // search; that was the source of the old prefecture
                        // prefill. Coordinates are returned only for local
                        // distance sorting after the official response.
                        result.success(mapOf(
                            "latitude" to bestLocation.latitude,
                            "longitude" to bestLocation.longitude,
                            "accuracy" to bestLocation.accuracy,
                        ))
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "setBrightness" -> {
                    try {
                        val brightness = call.argument<Double>("brightness")?.toFloat() ?: 0.5f
                        val clamped = brightness.coerceIn(0.01f, 1.0f)
                        runOnUiThread {
                            val lp = window.attributes
                            lp.screenBrightness = clamped
                            window.attributes = lp
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getBrightness" -> {
                    try {
                        var b = window.attributes.screenBrightness
                        if (b < 0) {
                            try {
                                val sysB = Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS)
                                b = sysB / 255.0f
                            } catch (_: Exception) {
                                b = 0.5f
                            }
                        }
                        result.success(b.toDouble())
                    } catch (e: Exception) {
                        result.success(0.5)
                    }
                }
                "setVolume" -> {
                    try {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val vol = call.argument<Double>("volume") ?: 0.5
                        val target = (vol * maxVol).toInt().coerceIn(0, maxVol)
                        am.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getVolume" -> {
                    try {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val curVol = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                        val ratio = if (maxVol > 0) curVol.toDouble() / maxVol.toDouble() else 0.5
                        result.success(ratio)
                    } catch (e: Exception) {
                        result.success(0.5)
                    }
                }
                "shareText" -> {
                    try {
                        val text = call.argument<String>("text") ?: ""
                        val title = call.argument<String>("title") ?: "分享"
                        val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(android.content.Intent.EXTRA_TEXT, text)
                        }
                        startActivity(android.content.Intent.createChooser(intent, title))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "saveMediaToGallery" -> {
                    try {
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName") ?: "wb_${System.currentTimeMillis()}.jpg"
                        val relativeSubDir = call.argument<String>("relativeSubDir") ?: ""
                        val isVideo = call.argument<Boolean>("isVideo") ?: false
                        val mimeType = call.argument<String>("mimeType") ?: if (isVideo) "video/mp4" else "image/jpeg"

                        if (bytes == null) {
                            result.error("INVALID_ARGS", "Bytes is null", null)
                            return@setMethodCallHandler
                        }

                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                            val collection = if (isVideo) {
                                android.provider.MediaStore.Video.Media.getContentUri(android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
                            } else {
                                android.provider.MediaStore.Images.Media.getContentUri(android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
                            }

                            val baseDir = if (isVideo) android.os.Environment.DIRECTORY_MOVIES else android.os.Environment.DIRECTORY_PICTURES
                            val targetRelativePath = if (relativeSubDir.isNotEmpty()) "$baseDir/$relativeSubDir" else baseDir

                            val contentValues = android.content.ContentValues().apply {
                                put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                                put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mimeType)
                                put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, targetRelativePath)
                                put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1)
                            }

                            val uri = contentResolver.insert(collection, contentValues)
                            if (uri != null) {
                                contentResolver.openOutputStream(uri)?.use { os ->
                                    os.write(bytes)
                                    os.flush()
                                }
                                contentValues.clear()
                                contentValues.put(android.provider.MediaStore.MediaColumns.IS_PENDING, 0)
                                contentResolver.update(uri, contentValues, null, null)
                                result.success("$targetRelativePath/$fileName")
                            } else {
                                result.error("SAVE_FAILED", "Failed to create MediaStore entry", null)
                            }
                        } else {
                            val hasWrite = checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
                            if (!hasWrite) {
                                requestPermissions(arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE), 1002)
                                result.error("PERMISSION_DENIED", "Storage permission requested", null)
                                return@setMethodCallHandler
                            }

                            val baseDir = if (isVideo) {
                                android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_MOVIES)
                            } else {
                                android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_PICTURES)
                            }
                            val targetDir = if (relativeSubDir.isNotEmpty()) java.io.File(baseDir, relativeSubDir) else baseDir
                            if (!targetDir.exists()) targetDir.mkdirs()

                            val file = java.io.File(targetDir, fileName)
                            java.io.FileOutputStream(file).use { fos ->
                                fos.write(bytes)
                                fos.flush()
                            }

                            android.media.MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf(mimeType), null)
                            result.success(file.absolutePath)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "getCurrentAppIcon" -> {
                    try {
                        val pm = packageManager
                        val pkg = packageName
                        val alias1State = pm.getComponentEnabledSetting(android.content.ComponentName(pkg, "com.review.MainActivityAlias1"))
                        val alias2State = pm.getComponentEnabledSetting(android.content.ComponentName(pkg, "com.review.MainActivityAlias2"))
                        val currentAlias = when {
                            alias1State == android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> "alias1"
                            alias2State == android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> "alias2"
                            else -> "default"
                        }
                        result.success(currentAlias)
                    } catch (e: Exception) {
                        result.success("default")
                    }
                }
                "switchAppIcon" -> {
                    val alias = call.argument<String>("alias") ?: "default"
                    val pm = packageManager
                    val pkg = packageName

                    val aliasMap = mapOf(
                        "default" to "com.review.MainActivity",
                        "alias1" to "com.review.MainActivityAlias1",
                        "alias2" to "com.review.MainActivityAlias2"
                    )

                    val targetClass = aliasMap[alias] ?: "com.review.MainActivity"

                    // Use background thread with SYNCHRONOUS flag to write directly to flash storage,
                    // and disable old components FIRST so the launcher never picks an old alias by mistake.
                    kotlin.concurrent.thread {
                        try {
                            val flags = android.content.pm.PackageManager.DONT_KILL_APP or 0x00000002 // SYNCHRONOUS

                            // 1. Disable all other components FIRST
                            for ((_, comp) in aliasMap) {
                                if (comp != targetClass) {
                                    pm.setComponentEnabledSetting(
                                        android.content.ComponentName(pkg, comp),
                                        android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                        flags
                                    )
                                }
                            }

                            // 2. Enable target component LAST
                            pm.setComponentEnabledSetting(
                                android.content.ComponentName(pkg, targetClass),
                                android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                                flags
                            )

                            runOnUiThread {
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("SWITCH_ICON_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "killProcess" -> {
                    result.success(true)
                    // Allow 1200ms for system PackageManagerService and Launcher background threads
                    // to completely write state, dispatch ACTION_PACKAGE_CHANGED, and refresh app drawer SQLite cache
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        android.os.Process.killProcess(android.os.Process.myPid())
                        System.exit(0)
                    }, 1200)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WEIBO_AUTH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestSmsCode" -> {
                        val phone = call.argument<String>("phone")?.filter { it.isDigit() }.orEmpty()
                        val area = call.argument<String>("area")?.filter { it.isDigit() }.orEmpty()
                        if (phone.length !in 5..20 || area.length !in 1..6) {
                            loginInputError(result, "请输入有效的国家区号和手机号")
                        } else {
                            submitWeiboAuth(result) { it.requestSmsCode(phone, area) }
                        }
                    }
                    "loginWithSms" -> {
                        val phone = call.argument<String>("phone")?.filter { it.isDigit() }.orEmpty()
                        val area = call.argument<String>("area")?.filter { it.isDigit() }.orEmpty()
                        val number = call.argument<String>("number").orEmpty()
                        val smsCode = call.argument<String>("smsCode")?.filter { it.isDigit() }.orEmpty()
                        if (phone.length !in 5..20 || area.length !in 1..6 || number.isBlank() || number.length > 256 || smsCode.length !in 4..12) {
                            loginInputError(result, "手机号、验证码或登录校验信息无效")
                        } else {
                            submitWeiboAuth(result) { it.loginWithSms(phone, area, number, smsCode) }
                        }
                    }
                    "loginWithPassword" -> {
                        val account = call.argument<String>("account")?.trim().orEmpty()
                        val password = call.argument<String>("password").orEmpty()
                        if (account.isEmpty() || account.length > 128 ||
                            account.any { it.isISOControl() } ||
                            password.isEmpty() || password.length > 256 ||
                            password.any { it.isISOControl() }
                        ) {
                            loginInputError(result, "请输入有效的微博账号和密码")
                        } else {
                            submitWeiboAuth(result) { it.loginWithPassword(account, password) }
                        }
                    }
                    "acceptSession" -> submitWeiboAuth(result) { it.acceptPendingSession() }
                    "discardPendingSession" -> submitWeiboAuth(result) {
                        it.discardPendingSession()
                        true
                    }
                    "restoreSession" -> submitWeiboAuth(result) { it.restoreSession() }
                    "logout" -> submitWeiboAuth(result) {
                        it.logout()
                        true
                    }
                    else -> result.notImplemented()
                }
            }

        val notificationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MESSAGE_NOTIFICATIONS_CHANNEL,
        )
        notificationChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT < 33) {
                        result.success(canPostNotifications())
                    } else if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(canPostNotifications())
                    } else if (notificationPermissionResult != null) {
                        result.error("PERMISSION_REQUEST_IN_PROGRESS", "通知权限请求正在处理中", null)
                    } else {
                        notificationPermissionResult = result
                        requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            4903,
                        )
                    }
                }
                "syncBackgroundNotifications" -> {
                    try {
                        syncMessageNotificationWork()
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("WORK_SCHEDULING_FAILED", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Android API")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 4903) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        val notificationsEnabled = canPostNotifications()
        notificationPermissionResult?.success(granted && notificationsEnabled)
        notificationPermissionResult = null
    }
}
