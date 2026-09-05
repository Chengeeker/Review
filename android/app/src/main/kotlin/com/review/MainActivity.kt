package com.review

import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.media.AudioManager
import android.provider.Settings
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.sharelite/cookies"
    private var methodChannel: MethodChannel? = null
    private var initialUrl: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val pm = packageManager
            val components = listOf(
                "com.review.MainActivity",
                "com.review.MainActivityAlias1",
                "com.review.MainActivityAlias2"
            )
            var hasEnabled = false
            for (comp in components) {
                val state = pm.getComponentEnabledSetting(android.content.ComponentName(packageName, comp))
                if (state == android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                    hasEnabled = true
                    break
                }
            }
            if (!hasEnabled) {
                pm.setComponentEnabledSetting(
                    android.content.ComponentName(packageName, "com.review.MainActivity"),
                    android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    android.content.pm.PackageManager.DONT_KILL_APP
                )
            }
        } catch (_: Exception) {}
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
                    try {
                        val cookieManager = CookieManager.getInstance()
                        cookieManager.flush()
                        val cookieList = mutableListOf<String>()
                        val domains = listOf(
                            "https://m.weibo.cn",
                            "https://weibo.com",
                            "https://passport.weibo.com",
                            "https://sina.cn",
                            "https://weibo.cn",
                            "https://m.weibo.com",
                            "https://login.sina.com.cn",
                            "m.weibo.cn",
                            "weibo.com",
                            ".weibo.com",
                            "weibo.cn",
                            ".weibo.cn",
                            ".sina.com.cn",
                            "sina.cn",
                            ".sina.cn"
                        )
                        for (domain in domains) {
                            val c = cookieManager.getCookie(domain)
                            if (!c.isNullOrEmpty()) {
                                cookieList.add(c)
                            }
                        }
                        val combined = cookieList.distinct().joinToString("; ")
                        result.success(combined)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "clearNativeCookies" -> {
                    try {
                        val cookieManager = CookieManager.getInstance()
                        cookieManager.removeAllCookies {
                            cookieManager.flush()
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "getSystemLocationCity" -> {
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
                        val providers = lm.getProviders(true)
                        for (provider in providers) {
                            val l = lm.getLastKnownLocation(provider) ?: continue
                            if (bestLocation == null || l.accuracy < bestLocation.accuracy) {
                                bestLocation = l
                            }
                        }

                        if (bestLocation != null) {
                            val geocoder = Geocoder(this, Locale.CHINA)
                            @Suppress("DEPRECATION")
                            val addresses = geocoder.getFromLocation(bestLocation.latitude, bestLocation.longitude, 1)
                            if (!addresses.isNullOrEmpty()) {
                                val addr = addresses[0]
                                var city = addr.locality ?: addr.subAdminArea ?: addr.adminArea ?: ""
                                city = city.replace("市", "").replace("省", "").trim()
                                if (city.isNotEmpty()) {
                                    result.success(city)
                                    return@setMethodCallHandler
                                }
                            }
                        }
                        result.success(null)
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
    }
}
