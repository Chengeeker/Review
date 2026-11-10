package com.review.compose

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.lang.reflect.Proxy
import okhttp3.ResponseBody.Companion.toResponseBody

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "zh-rCN-w412dp-h915dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class VideoPlayerTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var model: ReviewModel
    private val backend = ControlledPlayer()
    private val media = Media(video = "https://example.com/hd.mp4", title = "视频标题", qualities = linkedMapOf("1080P" to "https://example.com/hd.mp4", "720P" to "https://example.com/sd.mp4"))
    private var active by mutableStateOf(true)
    private var mounted by mutableStateOf(true)
    private var closed = 0
    private var chromeTaps = 0
    private var fullscreen = false
    private var dark by mutableStateOf(false)
    private var downloaded: Media? = null
    @Before fun setup() {
        val context = org.robolectric.RuntimeEnvironment.getApplication()
        runCatching { androidx.work.WorkManager.getInstance(context) }.onFailure { androidx.work.WorkManager.initialize(context, androidx.work.Configuration.Builder().build()) }
        model = ReviewModel(context)
    }
    private fun show(embedded: Boolean = false, media: Media = this.media, controlsEnabled: Boolean = true) {
        compose.setContent { CompositionLocalProvider(LocalReview provides model) { ReviewTheme(dark, scale = .95f) {
            Box(Modifier.fillMaxSize().background(if (media.live) Color.Blue else Color.Transparent)) {
            if (mounted) VideoPlayerContent(backend.player, media, active, { closed++ }, { downloaded = it }, embedded = embedded,
                controlsEnabled = controlsEnabled,
                onToggleChrome = { chromeTaps++ }, onFullscreenChanged = { fullscreen = it }, post = Post("12345", "作者", text = "")) {
                Box(Modifier.fillMaxSize().background(if (media.live) Color.Transparent else Color.Black), contentAlignment = Alignment.Center) {
                    Box(Modifier.aspectRatio(16f / 9f).background(if (media.live) Color.Green else Color(0xFF182430)))
                }
            }
            }
        } } }
        compose.waitForIdle()
    }
    private fun capture(name: String) {
        compose.waitForIdle()
        val roots = android.view.inspector.WindowInspector.getGlobalWindowViews().filter { it.isShown && it.width > 0 }
        if (name.endsWith("sheet")) assertTrue("Sheet capture must include the dialog window", roots.size > 1)
        val root = compose.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)
        val method = android.graphics.HardwareRenderer::class.java.getDeclaredMethod("createHardwareBitmap", android.graphics.RenderNode::class.java, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType).apply { isAccessible = true }
        roots.forEach { layer ->
            val node = android.graphics.RenderNode("video-capture").apply { setPosition(0, 0, layer.width, layer.height) }
            compose.runOnUiThread { layer.draw(node.beginRecording()); node.endRecording() }
            val hardware = method.invoke(null, node, layer.width, layer.height) as Bitmap
            val pixels = hardware.copy(Bitmap.Config.ARGB_8888, false)
            canvas.drawBitmap(pixels, layer.left.toFloat(), layer.top.toFloat(), null)
            hardware.recycle(); pixels.recycle(); node.discardDisplayList()
        }
        val path = File("build/reports/video-parity/$name.png").apply { parentFile.mkdirs() }
        path.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }
    @Test fun controlsUseTheOriginalThinProgressAndCompactBottomRow() {
        show()
        compose.onNodeWithText("视频标题").assertIsDisplayed()
        compose.onNodeWithText("@作者").assertIsDisplayed()
        compose.onNodeWithText("00:00 / 02:05").assertIsDisplayed()
        compose.onNodeWithContentDescription("下载视频").assertIsDisplayed()
        compose.onNodeWithContentDescription("分享视频").assertIsDisplayed()
        compose.onNodeWithContentDescription("暂停").assertIsDisplayed()
        val density = compose.activity.resources.displayMetrics.density
        assertEquals(16f, compose.onNodeWithTag("video-progress").fetchSemanticsNode().boundsInRoot.height / density, .5f)
        assertTrue(compose.onNodeWithTag("video-bottom-controls").fetchSemanticsNode().boundsInRoot.height / density <= 110f)
        capture("portrait-controls")
    }
    @Test fun livePhotoStaysVisibleUntilTheRenderedFrameAndPlayerSurvivesPause() {
        active = false
        backend.state = Player.STATE_BUFFERING
        show(media = media.copy(live = true), controlsEnabled = false)
        fun pixels(name: String, center: Int) {
            capture("live-$name")
            val bitmap = android.graphics.BitmapFactory.decodeFile("build/reports/video-parity/live-$name.png")
            assertEquals(name, center, bitmap.getPixel(bitmap.width / 2, bitmap.height / 2))
            assertEquals("Live letterbox must retain the photo", android.graphics.Color.BLUE, bitmap.getPixel(bitmap.width / 2, bitmap.height / 4))
            bitmap.recycle()
        }
        pixels("prepared-inactive", android.graphics.Color.BLUE)
        assertEquals(1, backend.sources)
        assertFalse(backend.playing)
        compose.runOnIdle { active = true }
        pixels("buffering", android.graphics.Color.BLUE)
        compose.runOnIdle { backend.state = Player.STATE_READY; backend.listeners.toList().forEach { it.onPlaybackStateChanged(Player.STATE_READY) } }
        pixels("ready-without-frame", android.graphics.Color.BLUE)
        compose.runOnIdle { backend.listeners.toList().forEach { it.onRenderedFirstFrame() } }
        pixels("first-frame", android.graphics.Color.GREEN)
        compose.runOnIdle { backend.listeners.toList().forEach { it.onPlaybackStateChanged(Player.STATE_BUFFERING) } }
        pixels("rebuffering", android.graphics.Color.GREEN)
        compose.runOnIdle { active = false }
        pixels("paused", android.graphics.Color.BLUE)
        compose.runOnIdle { active = true }
        pixels("resumed", android.graphics.Color.GREEN)
        assertEquals("Toggling Live must not prepare a new source", 1, backend.sources)
    }
    @Test
    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    fun liveSurfaceKeepsOriginalAudioAndPreloadsWithoutPlaying() {
        compose.setContent {
            CompositionLocalProvider(LocalReview provides model) {
                ReviewTheme(false) {
                    if (mounted) VideoSurface(media.copy(live = true), false, {}, {}, controlsEnabled = false)
                }
            }
        }
        compose.waitForIdle()
        fun playerView(view: android.view.View): androidx.media3.ui.PlayerView? {
            if (view is androidx.media3.ui.PlayerView) return view
            if (view is android.view.ViewGroup) for (index in 0 until view.childCount) playerView(view.getChildAt(index))?.let { return it }
            return null
        }
        compose.runOnIdle {
            val view = checkNotNull(playerView(compose.activity.window.decorView))
            val actual = checkNotNull(view.player)
            assertEquals("Live audio must not be forced to mute", 1f, actual.volume, 0f)
            assertEquals(androidx.media3.common.C.USAGE_MEDIA, actual.audioAttributes.usage)
            assertEquals(androidx.media3.common.C.AUDIO_CONTENT_TYPE_MOVIE, actual.audioAttributes.contentType)
            assertFalse("Preparing a Live photo must not start its audio", actual.playWhenReady)
            assertTrue(view.videoSurfaceView is android.view.TextureView)
            mounted = false
        }
        compose.waitForIdle()
    }
    @Test fun livePreloadFailureStaysQuietUntilPlayAndRetryWaitsForANewFrame() {
        active = false
        show(media = media.copy(live = true), controlsEnabled = false)
        compose.runOnIdle { backend.listeners.toList().forEach { it.onPlayerError(androidx.media3.common.PlaybackException("fixture", null, androidx.media3.common.PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS)) } }
        compose.onNodeWithText("视频加载失败或链接已失效").assertDoesNotExist()
        compose.runOnIdle { active = true }
        compose.onNodeWithText("视频加载失败或链接已失效").assertIsDisplayed()
        compose.onNodeWithText("重试").performClick()
        compose.waitForIdle()
        assertEquals(2, backend.sources)
        capture("live-retry-no-frame")
        val bitmap = android.graphics.BitmapFactory.decodeFile("build/reports/video-parity/live-retry-no-frame.png")
        assertEquals(android.graphics.Color.BLUE, bitmap.getPixel(bitmap.width / 2, bitmap.height / 2))
        bitmap.recycle()
        compose.runOnIdle { mounted = false }
        compose.runOnIdle { assertTrue(backend.listeners.isEmpty()); assertFalse(backend.playing) }
    }
    @Test fun speedAndQualitySheetsKeepPositionPauseStateAndTheDownloadedStream() {
        show()
        compose.onNodeWithContentDescription("暂停").performClick()
        compose.runOnIdle { backend.position = 42000 }
        compose.mainClock.advanceTimeBy(260)
        compose.onNodeWithText("倍速").performClick()
        compose.onNodeWithText("播放倍速").assertIsDisplayed()
        compose.onNodeWithText("3.0X").assertIsDisplayed()
        val density = compose.activity.resources.displayMetrics.density
        assertEquals(495f, compose.onNodeWithText("播放倍速", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.top / density, 2f)
        assertEquals(538.5f, compose.onNodeWithText("3.0X", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.top / density, 2f)
        capture("speed-sheet")
        compose.onNodeWithText("3.0X").performClick()
        compose.waitForIdle()
        assertEquals(3f, backend.speed, 0f)
        compose.onNodeWithText("1080P").performClick()
        compose.onNodeWithText("清晰度选择").assertIsDisplayed()
        compose.onNodeWithText("720P").performClick()
        compose.waitForIdle()
        assertEquals("https://example.com/sd.mp4", backend.address)
        assertEquals(42000L, backend.position)
        assertFalse(backend.playing)
        compose.onNodeWithContentDescription("下载视频").performClick()
        assertEquals("https://example.com/sd.mp4", downloaded?.video)
        compose.runOnIdle { active = false }
        compose.runOnIdle { active = true }
        assertFalse(backend.playing)
    }
    @Test fun controlsHideAfterFourSecondsAndRemainVisibleWhilePaused() {
        show()
        compose.mainClock.advanceTimeBy(3100)
        compose.onNodeWithTag("video-bottom-controls").assertExists()
        compose.mainClock.advanceTimeBy(1200)
        compose.onNodeWithTag("video-bottom-controls").assertDoesNotExist()
        compose.onNodeWithTag("video-gestures").performTouchInput { click(center) }
        compose.mainClock.advanceTimeBy(350)
        compose.onNodeWithContentDescription("暂停").performClick()
        compose.mainClock.advanceTimeBy(6000)
        compose.onNodeWithTag("video-bottom-controls").assertExists()
        assertFalse(backend.playing)
    }
    @Test fun expiredVideoRefreshesOnceAndRetainsPausedPosition() {
        val requests = java.util.concurrent.atomic.AtomicInteger()
        val client = okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            assertEquals("h5.video.weibo.com", request.url.host)
            assertEquals("/api/component", request.url.encodedPath)
            assertEquals("/show/1034:fixture", request.url.queryParameter("page"))
            requests.incrementAndGet()
            okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                .body("""{"ok":1,"data":{"Component_Play_Playinfo":{"urls":{"720P":"https://example.com/refreshed.mp4"}}}}""".toResponseBody()).build()
        }.build()
        val field = ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }
        val old = field.get(model.repository.api)
        field.set(model.repository.api, client)
        try {
            show(media = media.copy(videoId = "1034:fixture"))
            compose.onNodeWithContentDescription("暂停").performClick()
            compose.runOnIdle {
                backend.position = 42000
                backend.listeners.toList().forEach { it.onPlayerError(androidx.media3.common.PlaybackException("expired", null, androidx.media3.common.PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS)) }
            }
            compose.waitUntil(15000) {
                org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
                compose.runOnIdle { backend.address == "https://example.com/refreshed.mp4" }
            }
            compose.onNodeWithContentDescription("清晰度选择").assertDoesNotExist()
            compose.runOnIdle {
                assertEquals("https://example.com/refreshed.mp4", backend.address)
                assertEquals(42000L, backend.position)
                assertFalse(backend.playing)
                assertEquals(1, requests.get())
                backend.listeners.toList().forEach { it.onPlayerError(androidx.media3.common.PlaybackException("still unavailable", null, androidx.media3.common.PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS)) }
            }
            compose.onNodeWithText("视频加载失败或链接已失效").assertIsDisplayed()
            assertEquals(1, requests.get())
            compose.onNodeWithText("重试").performClick()
            compose.waitUntil(15000) {
                org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
                compose.onAllNodesWithText("重试").fetchSemanticsNodes().isEmpty() && backend.sources == 3
            }
            compose.runOnIdle { assertEquals(2, requests.get()); assertEquals(42000L, backend.position); assertFalse(backend.playing) }
        } finally { field.set(model.repository.api, old); client.dispatcher.executorService.shutdown() }
    }
    @Test fun gesturesSeekByTenSecondsAndRestoreTheSelectedSpeedAfterLongPress() {
        show()
        compose.onNodeWithText("倍速").performClick()
        compose.onNodeWithText("3.0X").performClick()
        val surface = compose.onNodeWithTag("video-gestures")
        surface.performTouchInput { down(androidx.compose.ui.geometry.Offset(width * .15f, height * .5f)) }
        compose.mainClock.advanceTimeBy(650)
        assertEquals("Speeds: ${backend.speeds}", 2f, backend.speed, 0f)
        compose.onNodeWithText("2.0X 倍速快进中").assertIsDisplayed()
        assertEquals(2f, backend.speed, 0f)
        surface.performTouchInput { advanceEventTime(650); up() }
        assertEquals(3f, backend.speed, 0f)
        surface.performTouchInput { doubleClick(androidx.compose.ui.geometry.Offset(width * .8f, height * .5f)) }
        assertEquals(10000L, backend.position)
        compose.onNodeWithText("+10s").assertIsDisplayed()
        compose.mainClock.advanceTimeBy(900)
        val before = backend.position
        surface.performTouchInput { advanceEventTime(900); swipeLeft() }
        assertEquals(before, backend.position)
        surface.performTouchInput { doubleClick(center) }
        compose.waitForIdle()
        assertFalse(backend.playing)
    }
    @Test fun embeddedFullscreenAndBrightnessRestoreWithoutReplacingThePlayer() {
        show(embedded = true)
        compose.onNodeWithTag("video-top-controls").assertDoesNotExist()
        val surface = compose.onNodeWithTag("video-gestures")
        surface.performTouchInput { click(center) }
        compose.mainClock.advanceTimeBy(350)
        surface.performTouchInput { click(center) }
        compose.mainClock.advanceTimeBy(350)
        assertEquals(2, chromeTaps)
        val previous = compose.activity.window.attributes.screenBrightness
        surface.performTouchInput { swipe(androidx.compose.ui.geometry.Offset(width * .2f, height * .6f), androidx.compose.ui.geometry.Offset(width * .2f, height * .25f), 500) }
        assertTrue(compose.activity.window.attributes.screenBrightness > 0f)
        compose.onNodeWithContentDescription("全屏").performClick()
        compose.waitForIdle()
        assertTrue(fullscreen)
        assertEquals(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE, compose.activity.requestedOrientation)
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.waitForIdle()
        assertFalse(fullscreen)
        assertEquals(0, closed)
        assertEquals(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, compose.activity.requestedOrientation)
        assertEquals(1, backend.sources)
        compose.runOnIdle { mounted = false }
        compose.waitForIdle()
        assertEquals(previous, compose.activity.window.attributes.screenBrightness, 0f)
        assertFalse(backend.playing)
    }
    @Test fun longPreviewKeepsRealHorizontalDetailWithinTheDecodeBudget() {
        val source = File(compose.activity.cacheDir, "sharp-preview.png")
        val bitmap = Bitmap.createBitmap(1000, 5000, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.CYAN)
        source.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }; bitmap.recycle()
        var decoded: Bitmap? = null
        var failure: Throwable? = null
        assertTrue(source.length() > 0)
        val originalLoader = coil.Coil.imageLoader(compose.activity)
        val loader = coil.ImageLoader.Builder(compose.activity).crossfade(false).allowHardware(false)
            .decoderDispatcher(kotlinx.coroutines.Dispatchers.Unconfined)
            .eventListener(object : coil.EventListener {
                override fun onError(request: coil.request.ImageRequest, result: coil.request.ErrorResult) { failure = result.throwable }
            }).build()
        coil.Coil.setImageLoader(loader)
        try {
        compose.setContent { CompositionLocalProvider(LocalReview provides model) { ReviewTheme(false, scale = .95f) {
            MediaImage(Media(source.toURI().toString(), width = 1000, height = 5000, long = true), "长图预览", Modifier.size(200.dp), onBitmap = { decoded = it })
        } } }
        compose.waitUntil(15000) {
            org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
            decoded != null || failure != null
        }
        if (failure != null) throw AssertionError("Preview decode failed", failure)
        assertTrue("The old 720px-long-edge request only retained 144 horizontal pixels", decoded!!.width >= 600)
        assertTrue(decoded!!.width.toLong() * decoded!!.height <= 3_000_000)
        source.delete()
        } finally { coil.Coil.setImageLoader(originalLoader); loader.shutdown() }
    }
    @Test fun videoPosterLetterboxStaysBlackInLightAndDarkThemes() {
        backend.state = Player.STATE_BUFFERING
        show(media = media.copy(url = "https://example.invalid/loading-cover.png"))
        for (night in listOf(false, true)) {
            compose.runOnIdle { dark = night }
            val name = "video-poster-${if (night) "dark" else "light"}"
            capture(name)
            val bitmap = android.graphics.BitmapFactory.decodeFile("build/reports/video-parity/$name.png")
            assertEquals(android.graphics.Color.BLACK, bitmap.getPixel(bitmap.width / 2, bitmap.height / 4))
            assertEquals(android.graphics.Color.BLACK, bitmap.getPixel(bitmap.width / 2, bitmap.height * 3 / 4))
            bitmap.recycle()
        }
    }

    @Test
    @Config(sdk = [35], qualifiers = "zh-rCN-w915dp-h412dp-land-xxhdpi")
    fun landscapeControlsUseOriginalInsetsAndScrubbingKeepsPlaybackIntent() {
        show()
        compose.onNodeWithContentDescription("全屏").performClick()
        compose.waitForIdle()
        val progress = compose.onNodeWithTag("video-progress")
        val density = compose.activity.resources.displayMetrics.density
        assertEquals(28f, progress.fetchSemanticsNode().boundsInRoot.left / density, .5f)
        capture("landscape-controls")
        progress.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.SetProgress) { it(70000f) }
        compose.waitForIdle()
        assertEquals(70000L, backend.position)
        assertTrue(backend.playing)
        compose.onNodeWithContentDescription("暂停").performClick()
        compose.waitForIdle()
        progress.performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.SetProgress) { it(80000f) }
        compose.waitForIdle()
        assertFalse(backend.playing)
    }

    @Test fun singleSourceKeepsSpeedButHidesQuality() {
        show(media = media.copy(qualities = mapOf("1080P" to media.video)))
        compose.onNodeWithContentDescription("清晰度选择").assertDoesNotExist()
        compose.onNodeWithText("倍速").assertIsDisplayed().performClick()
        compose.onNodeWithText("0.5X").assertExists()
    }

    private class ControlledPlayer {
        val listeners = mutableListOf<Player.Listener>()
        var position = 0L
        var playing = false
        var speed = 1f
        val speeds = mutableListOf<Float>()
        var sources = 0
        var address = ""
        var state = Player.STATE_READY
        var selection = androidx.media3.common.TrackSelectionParameters.DEFAULT
        val player = Proxy.newProxyInstance(Player::class.java.classLoader, arrayOf(Player::class.java)) { proxy, method, args ->
            when (method.name) {
                "getCurrentTracks" -> androidx.media3.common.Tracks.EMPTY
                "getTrackSelectionParameters" -> selection
                "setTrackSelectionParameters" -> { selection = args!![0] as androidx.media3.common.TrackSelectionParameters; null }
                "getCurrentPosition" -> position
                "getDuration" -> 125000L
                "getBufferedPosition" -> 80000L
                "getPlaybackState" -> state
                "isPlaying", "getPlayWhenReady" -> playing
                "addListener" -> { listeners += args!![0] as Player.Listener; null }
                "removeListener" -> { listeners -= args!![0] as Player.Listener; null }
                "setMediaItem" -> {
                    sources++
                    address = (args!![0] as MediaItem).localConfiguration!!.uri.toString()
                    (args.getOrNull(1) as? Long)?.let { position = it }
                    null
                }
                "setPlayWhenReady" -> { playing = args!![0] as Boolean; listeners.toList().forEach { it.onIsPlayingChanged(playing) }; null }
                "pause" -> { playing = false; listeners.toList().forEach { it.onIsPlayingChanged(false) }; null }
                "seekTo" -> { position = args!!.last() as Long; null }
                "setPlaybackSpeed" -> { speed = args!![0] as Float; speeds += speed; null }
                "prepare" -> { listeners.toList().forEach { it.onPlaybackStateChanged(state) }; null }
                "setVolume" -> null
                "hashCode" -> System.identityHashCode(proxy)
                "equals" -> args?.firstOrNull() === proxy
                "toString" -> "ControlledPlayer"
                else -> error("Unexpected player call: ${method.name}")
            }
        } as Player
    }
}
