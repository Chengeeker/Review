package com.review

import android.content.Context
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.util.Log
import android.view.View
import android.widget.ImageView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.sqrt

internal class HdrImageSupport(
    private val activity: FlutterActivity,
    engine: FlutterEngine,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.review/hdr_image")
    private val loader = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var closed = false
    private var previousColorMode: Int? = null
    private val cacheBudget = minOf(64L * 1024 * 1024, Runtime.getRuntime().maxMemory() / 8).toInt()
    private val bitmaps = object : LruCache<String, Bitmap>(cacheBudget) {
        override fun sizeOf(key: String, value: Bitmap): Int =
            value.allocationByteCount + if (Build.VERSION.SDK_INT >= 34 && value.hasGainmap()) {
                value.gainmap?.gainmapContents?.allocationByteCount ?: 0
            } else 0
    }

    init {
        engine.platformViewsController.registry.registerViewFactory("com.review/hdrImage", this)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isHdrDisplaySupported" -> {
                    result.success(displaySupported())
                }
                "decode" -> {
                    val path = call.argument<String>("path")
                    if (Build.VERSION.SDK_INT < 34 || path == null || closed) {
                        result.success(null)
                    } else loader.execute {
                        val response = try {
                            val file = File(path).canonicalFile
                            // Only the existing image cache is readable through this channel.
                            require(file.parentFile == File(activity.cacheDir, "cacheimage").canonicalFile)
                            require(file.name.matches(Regex("[a-fA-F0-9]{32}")))
                            require(file.length() in 1..64L * 1024 * 1024)
                            val bitmap = bitmaps.get(path) ?: decodeBitmapFromFile(file)
                            val hasGainMap = bitmap.hasGainmap()
                            Log.i("ReviewHDR", "decoded gainMap=$hasGainMap size=${bitmap.width}x${bitmap.height} hdrDisplay=${displaySupported()}")
                            if (hasGainMap && !closed) bitmaps.put(path, bitmap)
                            mapOf(
                                "hasGainMap" to hasGainMap,
                                "displaySupported" to (displaySupported() && bitmaps.get(path) != null),
                            )
                        } catch (error: Exception) {
                            Log.w("ReviewHDR", "decode failed: ${error.javaClass.simpleName}")
                            null
                        } catch (_: OutOfMemoryError) {
                            null
                        }
                        main.post { if (!closed) result.success(response) }
                    }
                }
                "setWindowHdr" -> {
                    if (Build.VERSION.SDK_INT >= 34) {
                        val enabled = call.argument<Boolean>("enabled") == true
                        if (enabled && displaySupported()) {
                            if (previousColorMode == null) previousColorMode = activity.window.colorMode
                            activity.window.colorMode = ActivityInfo.COLOR_MODE_HDR
                            if (Build.VERSION.SDK_INT >= 35) activity.window.setDesiredHdrHeadroom(0.0f)
                        } else {
                            previousColorMode?.let { activity.window.colorMode = it }
                            previousColorMode = null
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun displaySupported(): Boolean = Build.VERSION.SDK_INT >= 34 &&
        activity.windowManager.defaultDisplay.isHdr

    private fun decodeBitmapFromFile(file: File): Bitmap {
        return ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_HARDWARE
            val pixels = info.size.width.toDouble() * info.size.height
            val budget = cacheBudget / 16.0
            if (pixels > budget) {
                val scale = sqrt(budget / pixels)
                decoder.setTargetSize(
                    maxOf(1, (info.size.width * scale).toInt()),
                    maxOf(1, (info.size.height * scale).toInt()),
                )
            }
        }
    }

    private fun md5Hex(input: String): String {
        val md = MessageDigest.getInstance("MD5")
        val digest = md.digest(input.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<Any, Any>()
        val path = params["path"] as? String
        val url = params["url"] as? String ?: ""
        val headers = (params["headers"] as? Map<*, *>)
            ?.mapNotNull { (key, value) ->
                if (key is String && value is String) key to value else null
            }
            ?.toMap()
            .orEmpty()

        val image = object : ImageView(context) {
            private var reported = false
            override fun onDraw(canvas: Canvas) {
                super.onDraw(canvas)
                if (!reported && Build.VERSION.SDK_INT >= 34 &&
                    (drawable as? BitmapDrawable)?.bitmap?.hasGainmap() == true) {
                    reported = true
                    val currentDisplay = display
                    val ratio = if (currentDisplay?.isHdrSdrRatioAvailable == true) currentDisplay.hdrSdrRatio else 1.0f
                    Log.i("ReviewHDR", "draw hardware=${canvas.isHardwareAccelerated} hdrSdrRatio=$ratio windowMode=${activity.window.colorMode}")
                }
            }
        }.apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setBackgroundColor(android.graphics.Color.TRANSPARENT)
        }

        val disposed = AtomicBoolean(false)
        val activeConnection = AtomicReference<HttpURLConnection?>(null)

        fun showBitmap(bitmap: Bitmap) {
            val hasGainMap = Build.VERSION.SDK_INT >= 34 && bitmap.hasGainmap()
            main.post {
                if (disposed.get() || closed) return@post
                image.setImageBitmap(bitmap)
                channel.invokeMethod(
                    "hdrImageDecoded",
                    mapOf("url" to (if (url.isNotEmpty()) url else path ?: ""), "hasGainMap" to hasGainMap),
                )
            }
        }

        val loadTask = loader.submit {
            try {
                if (disposed.get() || closed) return@submit

                // 1. Check memory cache (by path or url)
                if (path != null) {
                    bitmaps.get(path)?.let {
                        showBitmap(it)
                        return@submit
                    }
                }
                if (url.isNotEmpty()) {
                    bitmaps.get(url)?.let {
                        showBitmap(it)
                        return@submit
                    }
                }

                // 2. Check disk cache
                var targetFile: File? = null
                if (path != null) {
                    val f = File(path)
                    if (f.exists() && f.length() in 1..64L * 1024 * 1024) {
                        targetFile = f
                    }
                }
                if (targetFile == null && url.isNotEmpty()) {
                    val md5 = md5Hex(url)
                    val cacheFile = File(activity.cacheDir, "cacheimage/$md5")
                    if (cacheFile.exists() && cacheFile.length() in 1..64L * 1024 * 1024) {
                        targetFile = cacheFile
                    }
                }

                if (targetFile != null) {
                    val bitmap = decodeBitmapFromFile(targetFile)
                    if (disposed.get() || closed) return@submit
                    if (path != null) bitmaps.put(path, bitmap)
                    if (url.isNotEmpty()) bitmaps.put(url, bitmap)
                    showBitmap(bitmap)
                    return@submit
                }

                // 3. Fallback: Network fetch via HttpURLConnection if URL is available
                if (url.isNotEmpty() && Build.VERSION.SDK_INT >= 34) {
                    val uri = Uri.parse(url)
                    require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null)
                    val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                        activeConnection.set(this)
                        connectTimeout = 15_000
                        readTimeout = 25_000
                        instanceFollowRedirects = true
                        setRequestProperty("Accept", "image/jpeg,image/*;q=0.8,*/*;q=0.5")
                        headers.forEach { (k, v) ->
                            if ('\r' !in k && '\n' !in k && '\r' !in v && '\n' !in v) {
                                setRequestProperty(k, v)
                            }
                        }
                    }
                    if (disposed.get() || closed) return@submit
                    connection.connect()
                    check(connection.responseCode in 200..299) { "Image request failed: ${connection.responseCode}" }
                    val maxBytes = 64L * 1024 * 1024
                    val bytes = connection.inputStream.use { input ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(16 * 1024)
                        var total = 0L
                        while (true) {
                            if (disposed.get() || closed || Thread.currentThread().isInterrupted) return@submit
                            val count = input.read(buffer)
                            if (count < 0) break
                            total += count
                            check(total <= maxBytes) { "Image too large" }
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    }
                    if (disposed.get() || closed) return@submit

                    // Cache to disk for future opens
                    try {
                        val cacheDir = File(activity.cacheDir, "cacheimage").apply { if (!exists()) mkdirs() }
                        val md5 = md5Hex(url)
                        val cacheFile = File(cacheDir, md5)
                        if (!cacheFile.exists()) {
                            val tempFile = File(cacheDir, "$md5.tmp")
                            tempFile.writeBytes(bytes)
                            tempFile.renameTo(cacheFile)
                        }
                    } catch (_: Exception) {}

                    val source = ImageDecoder.createSource(java.nio.ByteBuffer.wrap(bytes))
                    val bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                        decoder.allocator = ImageDecoder.ALLOCATOR_HARDWARE
                        val pixels = info.size.width.toDouble() * info.size.height
                        val budget = cacheBudget / 16.0
                        if (pixels > budget) {
                            val scale = sqrt(budget / pixels)
                            decoder.setTargetSize(
                                maxOf(1, (info.size.width * scale).toInt()),
                                maxOf(1, (info.size.height * scale).toInt()),
                            )
                        }
                    }
                    if (disposed.get() || closed) return@submit
                    if (path != null) bitmaps.put(path, bitmap)
                    bitmaps.put(url, bitmap)
                    showBitmap(bitmap)
                }
            } catch (e: Exception) {
                Log.w("ReviewHDR", "PlatformView load failed: ${e.message}")
                main.post {
                    if (!disposed.get() && !closed) {
                        channel.invokeMethod("hdrImageDecodeFailed", mapOf("url" to (if (url.isNotEmpty()) url else path ?: "")))
                    }
                }
            } finally {
                activeConnection.getAndSet(null)?.disconnect()
            }
        }

        return object : PlatformView {
            override fun getView(): View = image
            override fun dispose() {
                disposed.set(true)
                loadTask.cancel(true)
                activeConnection.getAndSet(null)?.disconnect()
                image.setImageDrawable(null)
            }
        }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        loader.shutdownNow()
        bitmaps.evictAll()
        if (Build.VERSION.SDK_INT >= 34) {
            previousColorMode?.let { activity.window.colorMode = it }
        }
    }
}
