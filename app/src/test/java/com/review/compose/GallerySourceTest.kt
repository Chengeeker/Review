package com.review.compose

import android.graphics.Bitmap
import android.graphics.Color
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import coil.request.ImageRequest
import coil.request.SuccessResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.android.asCoroutineDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.util.concurrent.atomic.AtomicInteger

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "zh-rCN-w412dp-h915dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class GallerySourceTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private lateinit var model: ReviewModel
    private lateinit var oldLoader: coil.ImageLoader
    private lateinit var loader: coil.ImageLoader
    private val loaded = AtomicInteger()
    private var opened: GalleryOrigin? = null
    private fun png(color: Int): ByteArray {
        val bitmap = Bitmap.createBitmap(100, 60, Bitmap.Config.ARGB_8888).apply {
            eraseColor(color)
            if (color == Color.TRANSPARENT) android.graphics.Canvas(this).drawRect(30f, 15f, 70f, 45f, android.graphics.Paint().apply { this.color = Color.GREEN })
        }
        return java.io.ByteArrayOutputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it); bitmap.recycle(); it.toByteArray() }
    }
    @Before fun setup() {
        Dispatchers.setMain(android.os.Handler(android.os.Looper.getMainLooper()).asCoroutineDispatcher())
        val context = org.robolectric.RuntimeEnvironment.getApplication()
        context.getSharedPreferences("preferences", 0).edit().clear().commit()
        runCatching { androidx.work.WorkManager.getInstance(context) }.onFailure { androidx.work.WorkManager.initialize(context, androidx.work.Configuration.Builder().build()) }
        model = ReviewModel(context)
        oldLoader = coil.Coil.imageLoader(context)
        val pictures = mapOf("/background.png" to png(Color.RED), "/front.png" to png(Color.TRANSPARENT), "/photo.png" to png(Color.BLUE), "/article.png" to png(Color.BLUE))
        loader = coil.ImageLoader.Builder(context).crossfade(true).allowHardware(false)
            .decoderDispatcher(Dispatchers.Unconfined).okHttpClient {
                okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
                    val request = chain.request()
                    check(request.url.host == "example.invalid")
                    okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                        .body(checkNotNull(pictures[request.url.encodedPath]).toResponseBody()).build()
                }.build()
            }.eventListener(object : coil.EventListener {
                override fun onSuccess(request: ImageRequest, result: SuccessResult) { loaded.incrementAndGet() }
            }).build()
        coil.Coil.setImageLoader(loader)
    }
    @After fun cleanup() { coil.Coil.setImageLoader(oldLoader); loader.shutdown(); Dispatchers.resetMain() }
    private fun show(content: @Composable () -> Unit) {
        compose.activity.setContent {
            CompositionLocalProvider(LocalReview provides model, LocalGalleryOpenFrom provides { _, index, sources -> opened = sources[index] }) {
                ReviewTheme(false) { content() }
            }
        }
    }
    private fun awaitImages(count: Int, description: String) {
        compose.waitUntil(15000) {
            org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
            compose.onAllNodesWithContentDescription(description).fetchSemanticsNodes().isNotEmpty() && loaded.get() >= count
        }
        compose.waitForIdle()
    }
    private fun draw() {
        val view = compose.activity.window.decorView
        val node = android.graphics.RenderNode("gallery-source").apply { setPosition(0, 0, view.width, view.height) }
        compose.runOnUiThread { view.draw(node.beginRecording()); node.endRecording() }
        val bitmap = android.graphics.HardwareRenderer::class.java.getDeclaredMethod("createHardwareBitmap", android.graphics.RenderNode::class.java, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType)
            .invoke(null, node, view.width, view.height) as Bitmap
        bitmap.recycle(); node.discardDisplayList()
    }
    @Test fun detailMetadataRefreshKeepsTheDecodedGalleryOrigin() {
        var post by mutableStateOf(Post("991", "详情作者", text = "", images = listOf(Media("https://example.invalid/photo.png", width = 100, height = 60))))
        show { MediaGrid(post, true) { _, _ -> error("Expected shared transition source") } }
        awaitImages(1, "详情作者的第 1 张图片")
        compose.onNodeWithContentDescription("详情作者的第 1 张图片").performClick()
        val first = checkNotNull(opened)
        assertNotNull(first.bitmap)
        compose.runOnIdle { post = post.copy(images = post.images.map { it.copy(title = "服务端补全资料") }) }
        compose.onNodeWithContentDescription("详情作者的第 1 张图片").performClick()
        assertSame(first, opened)
        assertNotNull(opened?.bitmap)
    }
    @Test fun webpageCardSourceIncludesBothRenderedLayers() {
        val media = Media("https://example.invalid/front.png", background = "https://example.invalid/background.png", card = true, width = 100, height = 60)
        show { MediaGrid(Post("992", "卡片作者", text = "", images = listOf(media)), true) { _, _ -> error("Expected shared transition source") } }
        awaitImages(2, "卡片作者的第 1 张图片")
        repeat(3) { draw(); compose.mainClock.advanceTimeBy(32); compose.waitForIdle() }
        compose.onNodeWithContentDescription("卡片作者的第 1 张图片").performClick()
        val bitmap = checkNotNull(opened?.bitmap).copy(Bitmap.Config.ARGB_8888, false)
        assertEquals(Color.RED, bitmap.getPixel(bitmap.width / 8, bitmap.height / 2))
        assertEquals(Color.GREEN, bitmap.getPixel(bitmap.width / 2, bitmap.height / 2))
        bitmap.recycle()
    }
    @Test fun birthdayCaptionRemainsOnTheCardAfterOpeningTheGallery() {
        val caption = "今天是我的生日09月29日，来祝福我吧~"
        val card = Media("https://example.invalid/front.png", background = "https://example.invalid/background.png",
            width = 854, height = 480, card = true, title = caption, cardLink = "https://t.cn/birthday")
        val post = Post("994", "生日作者", text = "今天是我的生日 09月29日，来祝福我吧~ http://t.cn/birthday", images = listOf(card))
        var viewing by mutableStateOf(false)
        show {
            if (viewing) Gallery(post.images, 0) { viewing = false }
            else CompositionLocalProvider(LocalGalleryOpenFrom provides null) {
                Column { PostBody(post, false, { _, _ -> viewing = true }) }
            }
        }
        awaitImages(2, "生日作者的第 1 张图片")
        compose.onAllNodesWithText(caption).assertCountEquals(1)
        compose.onNodeWithText("http://t.cn/birthday", substring = true).assertDoesNotExist()
        val beforeOpening = loaded.get()
        compose.onNodeWithContentDescription("生日作者的第 1 张图片").performClick()
        awaitImages(beforeOpening + 2, "网页卡片")
        compose.onNodeWithContentDescription("网页卡片").assertIsDisplayed()
        compose.onNodeWithText(caption).assertIsDisplayed()
    }
    @Test fun articleBodyImageSuppliesItsOwnSourceOutsideBottomPadding() {
        val client = okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            check(request.url.encodedPath == "/ttarticle/p/show")
            okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                .body("""<h1 node-type="articleTitle">正文图片过渡</h1><div node-type="contentBody"><p>正文</p><img src="https://example.invalid/article.png" width="100" height="60"></div>""".toResponseBody()).build()
        }.build()
        val field = ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }
        val previous = field.get(model.repository.api)
        field.set(model.repository.api, client)
        try {
            show { ArticleScreen("990001") { _, _ -> error("Expected shared transition source") } }
            awaitImages(1, "文章图片")
            compose.onNodeWithContentDescription("文章图片").performClick()
            val origin = checkNotNull(opened)
            assertNotNull(origin.bitmap)
            assertFalse(origin.crop)
            val bounds = checkNotNull(origin.anchor()).bounds
            assertEquals(bounds.width / 1.5f, bounds.height, 1f)
        } finally { field.set(model.repository.api, previous); client.dispatcher.executorService.shutdown() }
    }
}
