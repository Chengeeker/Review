package com.review.compose

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.android.asCoroutineDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.util.concurrent.atomic.AtomicInteger

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class ChatRenderingTest {
    @get:Rule val compose = createComposeRule()
    @Before fun attachMainDispatcher() {
        Dispatchers.setMain(android.os.Handler(android.os.Looper.getMainLooper()).asCoroutineDispatcher())
    }
    @After fun resetMainDispatcher() { Dispatchers.resetMain() }

    @Test fun ownTextAndLinksStayReadableAcrossThemeChanges() {
        val app = RuntimeEnvironment.getApplication()
        app.getSharedPreferences("preferences", 0).edit().clear().commit()
        runCatching { androidx.work.WorkManager.getInstance(app) }.onFailure { androidx.work.WorkManager.initialize(app, androidx.work.Configuration.Builder().build()) }
        val model = ReviewModel(app)
        val dark = mutableStateOf(false)
        var background = Color.Transparent
        val message = Message("1", "me", "", "", "发送内容 https://example.com", "", "{}")
        compose.setContent {
            CompositionLocalProvider(LocalReview provides model) {
                ReviewTheme(dark.value) {
                    background = MaterialTheme.colorScheme.primary
                    Column { ChatBubble(message, false, null) { _, _ -> }; Avatar("😀", modifier = androidx.compose.ui.Modifier) }
                }
            }
        }
        for (night in listOf(false, true)) {
            compose.runOnIdle { dark.value = night }
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(message.text, useUnmergedTree = true).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            val input = layouts.single().layoutInput
            fun contrast(a: Color) = (maxOf(a.luminance(), background.luminance()) + .05f) / (minOf(a.luminance(), background.luminance()) + .05f)
            assertTrue("Own bubble text in night=$night", contrast(input.style.color) >= 4.5f)
            val link = input.text.getLinkAnnotations(0, input.text.length).single().item
            assertTrue("Own link must not disappear into primary fill", contrast(link.styles!!.style!!.color) >= 4.5f)
        }
        compose.onNodeWithText("😀").assertExists()
    }

    @Test fun webChatKeepsQuoteLinesAndChoosesTheSharedPostCover() {
        assertEquals("「微博」\n-------------\n@群友 买亿点", chatMessageText("「微博」\r\n-------------\r\n@群友 买亿点"))
        assertEquals("首行\n第二行[笑]", chatMessageText("""首行<br>第二行<img alt="[笑]" src="https://example.invalid/a.png">"""))
        val share = JSONObject("""{"url_objects":[{"info":{"url_short":"http://t.cn/test"},
            "status":{"id":456,"user":{"screen_name":"作者"},"text":"正文","pics":[{"large":{"url":"https://example.invalid/cover.png"}}]}}]}""")
        assertEquals(ChatLink("https://weibo.com/detail/456", "作者", "正文", "https://example.invalid/cover.png"), chatLink(share))
        assertFalse(showChatTime("1700000300", "1700000000000"))
        assertTrue(showChatTime("1700000301000", "1700000000"))
        assertTrue(isChatNotice(JSONObject("""{"type":321,"sub_type":101}"""), "我发布了新微博，快来围观吧！", true))
        assertFalse(isChatNotice(JSONObject("""{"type":321,"sub_type":0}"""), "普通文字", true))
    }

    @Config(qualifiers = "zh-rCN-w412dp-h915dp-xxhdpi")
    @GraphicsMode(GraphicsMode.Mode.NATIVE)
    @Test fun groupStickerRetriesLookupAndOpensTheAnimatedImageInsteadOfItsShortLink() {
        val app = RuntimeEnvironment.getApplication()
        app.getSharedPreferences("preferences", 0).edit().clear().commit()
        runCatching { androidx.work.WorkManager.getInstance(app) }.onFailure { androidx.work.WorkManager.initialize(app, androidx.work.Configuration.Builder().build()) }
        val model = ReviewModel(app)
        val short = "http://t.cn/sticker"
        val message = parseMessage(JSONObject("""{"id":1,"type":321,"content":"$short","url_objects":[{"info":{"url_short":"https://t.cn/sticker"},
            "object":{"object":{"gif_name":"动图","pic_ids":["stickerFixture"],"url":"$short"}}}]}"""), group = true)
        assertEquals("附言 https://example.invalid", chatCaption("附言 https://example.invalid $short", true, false, "https://t.cn/sticker"))
        val lookups = AtomicInteger()
        val downloaded = AtomicInteger()
        val lastResult = java.util.concurrent.atomic.AtomicReference<coil.request.ImageResult>()
        val api = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            assertEquals("api.weibo.com", request.url.host)
            assertEquals("/webim/pic_infos.json", request.url.encodedPath)
            assertEquals("stickerFixture", request.url.queryParameter("pids"))
            assertEquals("https://api.weibo.com/chat/", request.header("Referer"))
            val url = if (lookups.incrementAndGet() == 1) "https://example.invalid/expired" else "https://example.invalid/animated"
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("""{"stickerFixture":"$url"}""".toResponseBody()).build()
        }.build()
        val field = ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }
        val previous = field.get(model.repository.api)
        field.set(model.repository.api, api)
        val originalLoader = coil.Coil.imageLoader(app)
        val gif = android.util.Base64.decode("R0lGODlhAQABAIAAAP8AAAAA/yH/C05FVFNDQVBFMi4wAwEAAAAh+QQACgAAACwAAAAAAQABAAACAkQBACH5BAAKAAAALAAAAAABAAEAAAICTAEAOw==", 0)
        val loader = coil.ImageLoader.Builder(app).diskCache(null).decoderDispatcher(Dispatchers.Unconfined)
            .components { add(coil.decode.ImageDecoderDecoder.Factory()) }
            .okHttpClient {
                OkHttpClient.Builder().addInterceptor { chain ->
                    val request = chain.request()
                    assertNull(request.header("Cookie"))
                    assertEquals("example.invalid", request.url.host)
                    downloaded.incrementAndGet()
                    val ready = request.url.encodedPath == "/animated"
                    Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(if (ready) 200 else 404).message("fixture")
                        .body((if (ready) gif else byteArrayOf()).toResponseBody()).build()
                }.build()
            }.eventListener(object : coil.EventListener {
                override fun onSuccess(request: coil.request.ImageRequest, result: coil.request.SuccessResult) { lastResult.set(result) }
                override fun onError(request: coil.request.ImageRequest, result: coil.request.ErrorResult) { lastResult.set(result) }
            }).build()
        coil.Coil.setImageLoader(loader)
        var opened: Media? = null
        try {
            compose.setContent {
                CompositionLocalProvider(LocalReview provides model) {
                    ReviewTheme(false) { ChatBubble(message, true, null) { media, index -> opened = media[index] } }
                }
            }
            val retry = "图片加载失败，点击重试"
            compose.waitUntil(15000) { compose.onAllNodesWithText(retry).fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText(short).assertDoesNotExist()
            lastResult.set(null)
            compose.onNodeWithText(retry).performClick()
            try {
                compose.waitUntil(10000) {
                    org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
                    lastResult.get() != null
                }
            } catch (e: androidx.compose.ui.test.ComposeTimeoutException) {
                throw AssertionError("Retry did not complete after ${lookups.get()} lookups and ${downloaded.get()} downloads", e)
            }
            val decoded = lastResult.get()
            if (decoded is coil.request.ErrorResult) throw AssertionError("Could not decode the retried GIF", decoded.throwable)
            assertTrue(decoded.drawable is android.graphics.drawable.Animatable)
            compose.onNodeWithText(retry).assertDoesNotExist()
            compose.onNodeWithContentDescription("查看聊天图片").performTouchInput { click() }
            compose.runOnIdle {
                assertEquals("https://example.invalid/animated", opened?.url)
                assertTrue(opened?.gif == true)
                assertEquals("root", model.screen)
            }
            assertEquals(2, lookups.get())
            assertEquals(2, downloaded.get())
        } finally {
            coil.Coil.setImageLoader(originalLoader)
            loader.shutdown()
            field.set(model.repository.api, previous)
        }
    }

    @Config(qualifiers = "zh-rCN-w412dp-h915dp-xxhdpi")
    @GraphicsMode(GraphicsMode.Mode.NATIVE)
    @Test fun returningFromSharedArticleKeepsMessagesAndResolvedAvatars() {
        val app = RuntimeEnvironment.getApplication()
        app.getSharedPreferences("preferences", 0).edit().clear().commit()
        runCatching { androidx.work.WorkManager.getInstance(app) }.onFailure { androidx.work.WorkManager.initialize(app, androidx.work.Configuration.Builder().build()) }
        val model = ReviewModel(app)
        compose.waitUntil(15000) {
            org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
            model.ready
        }
        ReviewModel::class.java.getDeclaredField("cookie").apply { isAccessible = true }.set(model, "SUB=fixture")
        val messages = AtomicInteger()
        val groups = AtomicInteger()
        val senders = AtomicInteger()
        val api = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            val body = when (request.url.encodedPath) {
                "/webim/groupchat/query_messages.json" -> {
                    messages.incrementAndGet()
                    """{"messages":[
                        {"id":1,"time":1700000000,"type":321,"from_uid":42,"content":"http://t.cn/test","from_user":{"screen_name":"群友"},
                         "url_objects":[{"info":{"url_short":"http://t.cn/test"},"object":{"object":{"display_name":"分享文章","url":"https://weibo.com/ttarticle/p/show?id=2309401234567890123456"}}}]},
                        {"id":2,"time":1700000030,"type":321,"from_uid":42,"content":"「微博」\n-------------\n@群友 买亿点"},
                        {"id":3,"time":1700000100,"type":321,"sub_type":101,"from_uid":44,"content":"我发布了新微博，快来围观吧！"}
                    ]}"""
                }
                "/webim/groupchat/query.json" -> {
                    groups.incrementAndGet()
                    """{"owner":42,"nick_infos":[{"uid":42,"nick":"群内昵称"}]}"""
                }
                "/webim/2/users/show.json" -> {
                    assertEquals("42", request.url.queryParameter("uid"))
                    senders.incrementAndGet()
                    """{"id":42,"screen_name":"群友","profile_image_url":"https://example.invalid/avatar.png"}"""
                }
                else -> error("Unexpected fixture request ${request.url.encodedPath}")
            }
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body(body.toResponseBody()).build()
        }.build()
        val apiField = ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }
        val previousApi = apiField.get(model.repository.api)
        apiField.set(model.repository.api, api)
        val originalLoader = coil.Coil.imageLoader(app)
        val imageRequests = AtomicInteger()
        val decodedAvatars = AtomicInteger()
        val loader = coil.ImageLoader.Builder(app).decoderDispatcher(kotlinx.coroutines.Dispatchers.Unconfined).okHttpClient {
            OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request()
                assertEquals("/avatar.png", request.url.encodedPath)
                imageRequests.incrementAndGet()
                Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                    .body(android.util.Base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAF0lEQVR4nGNQaHAgCTGMahjV4DBsNQAA9xrgAZ/ZK8UAAAAASUVORK5CYII=", 0).toResponseBody()).build()
            }.build()
        }.eventListener(object : coil.EventListener {
            override fun onSuccess(request: coil.request.ImageRequest, result: coil.request.SuccessResult) { decodedAvatars.incrementAndGet() }
        }).build()
        coil.Coil.setImageLoader(loader)
        try {
            model.navigate("chat:123:true")
            compose.setContent {
                CompositionLocalProvider(LocalReview provides model) {
                    ReviewTheme(false) {
                        PageStack(model.routeStack.toList()) { route ->
                            when {
                                route.name.startsWith("chat:") -> ConversationScreen("123", true) { _, _ -> }
                                route.name.startsWith("article:") -> Text("文章正文")
                            }
                        }
                    }
                }
            }
            compose.waitUntil(15000) {
                org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
                compose.onAllNodesWithText("分享文章").fetchSemanticsNodes().isNotEmpty() && decodedAvatars.get() >= 2
            }
            compose.onNodeWithText("「微博」\n-------------\n@群友 买亿点").assertIsDisplayed()
            compose.onAllNodesWithText("群主").onFirst().assertIsDisplayed()
            compose.onNodeWithText("我发布了新微博，快来围观吧！").assertIsDisplayed()
            compose.onAllNodesWithContentDescription("查看群内昵称的主页").assertCountEquals(2)
            val loadedImages = imageRequests.get()
            repeat(3) {
                compose.onNodeWithText("分享文章").performClick()
                compose.onNodeWithText("文章正文").assertIsDisplayed()
                compose.runOnIdle { model.back() }
                compose.onNodeWithText("分享文章").assertIsDisplayed()
                compose.onAllNodesWithContentDescription("查看群内昵称的主页").assertCountEquals(2)
            }
            assertEquals(1, messages.get())
            assertEquals(1, groups.get())
            assertEquals(1, senders.get())
            assertEquals(loadedImages, imageRequests.get())
        } finally {
            compose.runOnIdle { model.back() }
            coil.Coil.setImageLoader(originalLoader)
            loader.shutdown()
            apiField.set(model.repository.api, previousApi)
        }
    }
}
