package com.review.compose

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.graphics.luminance
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.Before
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import okhttp3.ResponseBody.Companion.toResponseBody
import okhttp3.MediaType.Companion.toMediaType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.android.asCoroutineDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "zh-rCN-w412dp-h915dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class NavigationTest {
    private val compose = createAndroidComposeRule<MainActivity>()
    @get:Rule val rules: RuleChain = RuleChain.outerRule(object : ExternalResource() {
        override fun before() {
            // Each Robolectric activity owns a new main looper; don't resume into a prior test's handler.
            Dispatchers.setMain(android.os.Handler(android.os.Looper.getMainLooper()).asCoroutineDispatcher())
            val context = RuntimeEnvironment.getApplication()
            runCatching { androidx.work.WorkManager.getInstance(context) }.onFailure {
                androidx.work.WorkManager.initialize(context, androidx.work.Configuration.Builder().build())
            }
            RuntimeEnvironment.getApplication().getSharedPreferences("preferences", 0).edit().clear().putBoolean("demo", true).commit()
        }
        override fun after() { Dispatchers.resetMain() }
    }).around(compose)

    @Before fun resetRenderedPreferences() {
        compose.waitUntil(15000) { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].ready }
        compose.runOnIdle {
            val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
            val ownedPreferences = ReviewModel::class.java.getDeclaredField("prefs").apply { isAccessible = true }.get(model) as android.content.SharedPreferences
            ownedPreferences.edit().clear().commit()
            kotlinx.coroutines.runBlocking { model.reloadPreferences() }
            model.changeMode(true)
            org.junit.Assert.assertEquals(0, model.theme)
            org.junit.Assert.assertFalse(model.bool("customWeight"))
        }
    }
    private fun ready() { compose.waitUntil(15000) { compose.onAllNodesWithText("山间来信").fetchSemanticsNodes().isNotEmpty() } }
    @Test fun credentialSheetCopiesSubAndFullCookieSeparately() {
        val cookie = "SUBP=other; sUb=fixture=tail; XSRF-TOKEN=test"
        val visible = androidx.compose.runtime.mutableStateOf(true)
        var notice = ""
        compose.activity.setContent {
            ReviewTheme(false) {
                if (visible.value) AccountCredentialsSheet("测试用户", "123", cookie, { notice = it }, { visible.value = false })
            }
        }
        val clipboard = compose.activity.getSystemService(android.content.ClipboardManager::class.java)
        compose.onNodeWithText("当前账号: 测试用户 (UID: 123)").assertIsDisplayed()
        compose.onNodeWithText("复制 SUB").performClick()
        compose.runOnIdle {
            assertEquals("fixture=tail", clipboard.primaryClip?.getItemAt(0)?.text.toString())
            assertTrue(clipboard.primaryClipDescription?.extras?.getBoolean("android.content.extra.IS_SENSITIVE") == true)
            assertEquals("已复制 SUB 凭据到剪贴板", notice)
            assertTrue(!visible.value)
            visible.value = true
        }
        compose.onNodeWithText("复制全部").performClick()
        compose.runOnIdle {
            assertEquals(cookie, clipboard.primaryClip?.getItemAt(0)?.text.toString())
            assertTrue(clipboard.primaryClipDescription?.extras?.getBoolean("android.content.extra.IS_SENSITIVE") == true)
            assertEquals("已复制完整 Cookie 字符串到剪贴板", notice)
            clipboard.clearPrimaryClip()
        }
    }
    private fun composeHost(): android.view.View {
        fun descendants(view: android.view.View): Sequence<android.view.View> = sequence {
            yield(view)
            if (view is android.view.ViewGroup) for (i in 0 until view.childCount) yieldAll(descendants(view.getChildAt(i)))
        }
        return descendants(compose.activity.window.decorView).first { it.javaClass.name == "androidx.compose.ui.platform.AndroidComposeView" }
    }
    private fun commentHost() =
        (compose.onNode(isDialog()).fetchSemanticsNode().root as androidx.compose.ui.platform.ViewRootForTest).view

    private fun focusCommentWindow() {
        val host = commentHost()
        compose.runOnUiThread {
            org.robolectric.util.ReflectionHelpers.callInstanceMethod<Unit>(
                host.viewTreeObserver, "dispatchOnWindowFocusChange",
                org.robolectric.util.ReflectionHelpers.ClassParameter.from(Boolean::class.javaPrimitiveType, true),
            )
        }
    }
    private fun injectStatusBarInset(): Int {
        val inset = (42 * compose.activity.resources.displayMetrics.density).toInt()
        compose.runOnUiThread {
            val statusBars = androidx.core.view.WindowInsetsCompat.Type.statusBars()
            androidx.core.view.ViewCompat.dispatchApplyWindowInsets(composeHost(), androidx.core.view.WindowInsetsCompat.Builder()
                .setInsets(statusBars, androidx.core.graphics.Insets.of(0, inset, 0, 0)).setVisible(statusBars, true).build())
        }
        return inset
    }
    private fun expectHaptic(feedback: Int = android.view.HapticFeedbackConstants.KEYBOARD_TAP) {
        compose.runOnIdle {
            val view = org.robolectric.Shadows.shadowOf(composeHost())
            assertEquals(feedback, view.lastHapticFeedbackPerformed())
            org.robolectric.util.ReflectionHelpers.setField(view, "hapticFeedbackPerformed", -1)
        }
    }
    private fun assertNightText(text: String, input: Boolean = false) {
        val results = mutableListOf<TextLayoutResult>()
        val node = if (input) compose.onNode(hasSetTextAction() and hasText(text, substring = true)) else compose.onAllNodesWithText(text, useUnmergedTree = true).onFirst()
        node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        assertTrue("Missing text layout for $text", results.isNotEmpty())
        assertTrue("Dark surface must not retain a light-theme foreground for $text", results.first().layoutInput.style.color.luminance() > .45f)
    }
    private fun captureBitmap(): Bitmap {
        compose.waitForIdle()
        val view = compose.activity.window.decorView
        val node = android.graphics.RenderNode("page-capture").apply { setPosition(0, 0, view.width, view.height) }
        compose.runOnUiThread { view.draw(node.beginRecording()); node.endRecording() }
        val hardware = android.graphics.HardwareRenderer::class.java.getDeclaredMethod("createHardwareBitmap", android.graphics.RenderNode::class.java, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType)
            .invoke(null, node, view.width, view.height) as Bitmap
        val bitmap = hardware.copy(Bitmap.Config.ARGB_8888, false)
        hardware.recycle(); node.discardDisplayList()
        return bitmap
    }
    private fun capture(name: String) {
        val bitmap = captureBitmap()
        val file = File("build/reports/screenshots/$name.png").apply { parentFile?.mkdirs() }
        file.outputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        }
        bitmap.recycle()
    }

    @Test fun decodedGalleryDoesNotPaintTheFullImageOrControlsBeforeItsFirstFlightFrame() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val bitmap = Bitmap.createBitmap(80, 80, Bitmap.Config.ARGB_8888).apply { eraseColor(android.graphics.Color.RED) }
        val origin = GalleryOrigin(0.dp).apply { this.bitmap = bitmap }
        val showing = androidx.compose.runtime.mutableStateOf(false)
        fun imageViews(view: android.view.View): Int {
            var count = if (view is android.widget.ImageView) 1 else 0
            if (view is android.view.ViewGroup) for (index in 0 until view.childCount) count += imageViews(view.getChildAt(index))
            return count
        }
        compose.runOnUiThread {
            compose.activity.setContent {
                CompositionLocalProvider(LocalReview provides model) {
                    ReviewTheme(false) {
                        Box(Modifier.fillMaxSize().background(Color.Blue)) {
                            Image(bitmap.asImageBitmap(), "来源图片", Modifier.padding(start = 32.dp, top = 100.dp).size(80.dp)
                                .onGloballyPositioned { origin.coordinates = it }.graphicsLayer { alpha = if (origin.covered) 0f else 1f })
                            if (showing.value) Gallery(listOf(Media()), 0, mapOf(0 to origin)) { showing.value = false }
                        }
                    }
                }
            }
        }
        compose.waitForIdle()
        compose.mainClock.autoAdvance = false
        try {
            repeat(3) {
                compose.runOnIdle { showing.value = true }
                compose.mainClock.advanceTimeByFrame()
                val first = captureBitmap()
                val color = first.getPixel(first.width / 2, first.height / 2)
                first.recycle()
                assertTrue("Opening frame exposed the full image: $color", android.graphics.Color.blue(color) > 150 && android.graphics.Color.red(color) < 40)
                compose.runOnIdle { assertEquals("Native image must wait until the flight ends", 0, imageViews(compose.activity.window.decorView)) }
                compose.onNodeWithContentDescription("返回").assertDoesNotExist()
                compose.mainClock.advanceTimeBy(80)
                compose.runOnIdle { assertEquals("Native image mounted during the flight", 0, imageViews(compose.activity.window.decorView)) }
                if (it == 1) {
                    var frames = 0
                    while (compose.onAllNodesWithContentDescription("返回").fetchSemanticsNodes().isEmpty()) {
                        check(frames++ < 30)
                        compose.mainClock.advanceTimeByFrame()
                    }
                } else compose.mainClock.advanceTimeBy(320)
                compose.onNodeWithContentDescription("返回").assertIsDisplayed()
                val opened = captureBitmap()
                assertTrue(android.graphics.Color.red(opened.getPixel(opened.width / 2, opened.height / 2)) > 200)
                opened.recycle()
                compose.runOnIdle { assertEquals(1, imageViews(compose.activity.window.decorView)) }
                compose.onNodeWithContentDescription("返回").performClick()
                compose.mainClock.advanceTimeByFrame()
                compose.runOnIdle { assertTrue("Opening cleanup must retain the returning source flight", origin.covered) }
                if (it == 2) {
                    var frames = 0
                    while (origin.covered) {
                        check(frames++ < 20)
                        compose.mainClock.advanceTimeByFrame()
                    }
                    val landing = compose.onNodeWithContentDescription("来源图片").fetchSemanticsNode().boundsInRoot.center
                    compose.onRoot().performTouchInput { down(landing) }
                    compose.mainClock.advanceTimeByFrame()
                    compose.runOnIdle { assertTrue("A touch on the landing frame must keep the gallery alive", showing.value) }
                    compose.onRoot().performTouchInput { up() }
                    compose.mainClock.advanceTimeBy(400)
                    compose.onNodeWithContentDescription("返回").assertIsDisplayed()
                    compose.onNodeWithContentDescription("返回").performClick()
                }
                compose.mainClock.advanceTimeBy(250)
                compose.waitForIdle()
                compose.runOnIdle { org.junit.Assert.assertFalse(showing.value); org.junit.Assert.assertFalse(origin.covered) }
            }
        } finally {
            compose.mainClock.autoAdvance = true
            compose.runOnIdle { showing.value = false }
        }
    }
    @Test fun lateBackCommitCannotPopTheReplacementRoute() {
        ready()
        compose.runOnIdle {
            val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
            model.navigate("history")
            val original = model.routeStack.last()
            model.back()
            model.navigate("history")
            val replacement = model.routeStack.last()
            model.backFrom(original)
            assertTrue(model.routeStack.last() === replacement)
            model.backFrom(replacement)
            assertEquals("root", model.screen)
        }
    }

    @Test fun drawerUsesOriginalGuestHeaderAndCompactRows() {
        org.junit.Assert.assertEquals(17, drawerUnreadTotal(org.json.JSONObject("""{"data":{"mention_status":2,"mention_cmt":3,"mention":99,"like":4,"cmt":1}}"""), 7))
        org.junit.Assert.assertEquals(3, drawerUnreadTotal(org.json.JSONObject("""{"mention":3,"likes":-2}"""), -1))
        org.junit.Assert.assertEquals(Int.MAX_VALUE, drawerUnreadTotal(org.json.JSONObject("""{"mention_status":2147483647,"mention_cmt":2147483647}"""), 1))
        ready()
        compose.onNodeWithContentDescription("打开侧栏").performClick()
        val width = compose.onNodeWithTag("review-drawer").fetchSemanticsNode().boundsInRoot.width
        assertTrue("Drawer should leave usable space beside it", width <= compose.activity.window.decorView.width * .63f)
        for (label in listOf("赞和收藏", "我的分组", "关注列表", "我的消息", "超话中心", "浏览记录")) compose.onNodeWithText(label).assertIsDisplayed()
        val likes = compose.onNodeWithText("赞和收藏").fetchSemanticsNode().boundsInRoot
        val groups = compose.onNodeWithText("我的分组").fetchSemanticsNode().boundsInRoot
        org.junit.Assert.assertEquals(48f * compose.activity.resources.displayMetrics.density, groups.top - likes.top, 2f)
        capture("drawer-light")
        compose.runOnIdle { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].updateTheme(2) }
        assertNightText("我的消息")
        capture("drawer-dark")
        compose.onNodeWithText("未登录 / 访客").performClick()
        compose.onNodeWithText("账号登录").assertExists()
    }

    @Test fun fullTextExpandsInTheFeedAndStaysOpenInDetail() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val preview = "正文预览"
        val full = "正文预览\n\n完整的后续段落"
        val post = Post("123", "长文作者", text = preview, demo = true, longText = true,
            raw = org.json.JSONObject().put("full_text_raw", full).toString())
        val detail = androidx.compose.runtime.mutableStateOf(false)
        compose.activity.setContent {
            CompositionLocalProvider(LocalReview provides model) {
                ReviewTheme(false) {
                    if (detail.value) DetailScreen(model, { _, _ -> }, post)
                    else PostCard(post, false, { detail.value = true }, {}, { _, _ -> }, {})
                }
            }
        }
        compose.onNodeWithText("展开全文").performClick()
        compose.onNodeWithText(full).assertIsDisplayed()
        compose.onNodeWithText("收起全文").performClick()
        compose.onNodeWithText(preview).assertIsDisplayed()
        compose.runOnIdle { detail.value = true }
        compose.onNodeWithText(full).assertIsDisplayed()
        compose.onNodeWithText("展开全文").assertDoesNotExist()
        compose.onNodeWithText("收起全文").assertDoesNotExist()
    }

    @Test fun quickCommentStaysAnchoredAndOpensTheFocusedEditor() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnIdle { model.openPost(model.feed.first()) }
        val quickComment = compose.onNodeWithText("发送一条友善的评论...")
        val start = quickComment.fetchSemanticsNode().boundsInRoot
        fun dispatchIme(bottom: Int) = compose.runOnUiThread {
            val ime = androidx.core.view.WindowInsetsCompat.Type.ime()
            val host = composeHost()
            val existing = androidx.core.view.ViewCompat.getRootWindowInsets(host) ?: androidx.core.view.WindowInsetsCompat.CONSUMED
            androidx.core.view.ViewCompat.dispatchApplyWindowInsets(host, androidx.core.view.WindowInsetsCompat.Builder(existing)
                .setInsets(ime, androidx.core.graphics.Insets.of(0, 0, 0, bottom)).setVisible(ime, bottom > 0).build())
        }
        dispatchIme(360)
        assertEquals(start, quickComment.fetchSemanticsNode().boundsInRoot)
        dispatchIme(0)
        quickComment.performClick()
        compose.onNodeWithText("写下你的友善评论...").assertIsDisplayed()
        compose.onNodeWithText("发送").assertIsDisplayed()
        compose.onNode(hasSetTextAction()).assertIsNotFocused()
        focusCommentWindow()
        compose.onNode(hasSetTextAction()).assertIsFocused()
        compose.onNodeWithContentDescription("关闭").performClick()
        quickComment.assertIsDisplayed()
        assertEquals(start, quickComment.fetchSemanticsNode().boundsInRoot)
    }

    @Test fun commentEditorClosesFromTheScrimAndFromTheEmojiPanel() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnIdle { model.openPost(model.feed.first()) }
        val entry = compose.onNodeWithText("发送一条友善的评论...")
        entry.performClick()
        focusCommentWindow()
        compose.onNode(hasSetTextAction()).assertIsFocused().performTextInput("测试草稿")
        compose.onNode(isDialog()).performTouchInput { click(androidx.compose.ui.geometry.Offset(width / 2f, 20f)) }
        compose.onNode(isDialog()).assertDoesNotExist()
        entry.assertIsDisplayed().performClick()
        focusCommentWindow()
        compose.onNodeWithContentDescription("插入表情").performClick()
        compose.onNodeWithText("常用").assertIsDisplayed()
        val close = compose.onNodeWithContentDescription("关闭").fetchSemanticsNode().config[SemanticsActions.OnClick].action!!
        val host = commentHost()
        compose.runOnUiThread {
            val feedback = org.robolectric.Shadows.shadowOf(host)
            org.robolectric.util.ReflectionHelpers.setField(feedback, "hapticFeedbackPerformed", -1)
            close()
            assertEquals(android.view.HapticFeedbackConstants.KEYBOARD_TAP, feedback.lastHapticFeedbackPerformed())
            org.robolectric.util.ReflectionHelpers.setField(feedback, "hapticFeedbackPerformed", -1)
            close()
            assertEquals(-1, feedback.lastHapticFeedbackPerformed())
        }
        compose.onNode(isDialog()).assertDoesNotExist()
        entry.assertIsDisplayed()
        compose.runOnIdle { assertEquals("detail", model.screen) }
    }

    @Test fun commentAndBothChatComposersHaveUsableOfflineEmoji() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnIdle { model.openPost(model.feed.first()) }
        compose.onNodeWithText("发送一条友善的评论...").performClick()
        compose.onNodeWithContentDescription("插入表情").performClick()
        compose.onNodeWithContentDescription("[微笑]").assertIsDisplayed()
        compose.onNodeWithText("热门").performClick()
        compose.onNodeWithContentDescription("[doge]").assertIsDisplayed()
        compose.onNodeWithText("符号").performClick()
        compose.onNodeWithContentDescription("[赞]").performClick()
        compose.onNode(hasSetTextAction() and hasText("[赞]")).assertExists()
        compose.onNodeWithContentDescription("关闭").performClick()
        compose.runOnIdle { model.back() }
        for (group in listOf(false, true)) {
            compose.runOnIdle { model.navigate("chat:123:$group") }
            val editor = compose.onNode(hasSetTextAction())
            editor.performClick()
            editor.performTextInput("前后")
            editor.performSemanticsAction(SemanticsActions.SetSelection) { action -> action(1, 1, false) }
            compose.onNodeWithContentDescription("插入表情").performClick()
            compose.onNodeWithContentDescription("[微笑]").performClick()
            compose.onNode(hasSetTextAction() and hasText("前[微笑]后")).assertExists()
            compose.onNodeWithContentDescription("删除").performClick()
            compose.onNode(hasSetTextAction() and hasText("前后")).assertExists()
            compose.onNodeWithContentDescription("切换键盘").performClick()
            compose.onNode(hasSetTextAction()).assertIsFocused().performTextClearance()
            compose.onNodeWithText("常用").assertDoesNotExist()
            compose.runOnIdle { model.back() }
        }
    }

    @Test fun quotedVideoKeepsTheSameTitleInTheFeedAndBothDetailPages() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val title = "原作者的微博视频"
        val short = "http://t.cn/video123"
        val url = "https://video.weibo.com/show?fid=1034:123&from=test"
        val quoteJson = org.json.JSONObject().put("mid", "102").put("text_raw", "原文 $short\u200B")
            .put("text", """原文 <a href="${url.replace("&", "&amp;")}"><img title="$short" src="icon.png">$title</a>""")
            .put("user", org.json.JSONObject().put("screen_name", "原作者"))
        val forwarded = parsePost(org.json.JSONObject().put("mid", "101").put("text_raw", "转发内容")
            .put("retweeted_status", quoteJson)).copy(demo = true)
        val originalJson = org.json.JSONObject(quoteJson.toString()).apply {
            remove("text")
            put("url_struct", org.json.JSONArray().put(org.json.JSONObject().put("short_url", short.replace("http:", "https:"))
                .put("url_title", title).put("long_url", url)))
        }
        val original = parsePost(originalJson).copy(demo = true)
        val page = androidx.compose.runtime.mutableStateOf(0)
        compose.activity.setContent {
            CompositionLocalProvider(LocalReview provides model) {
                ReviewTheme(false) {
                    when (page.value) {
                        0 -> PostCard(forwarded, false, { page.value = 1 }, {}, { _, _ -> }, {})
                        1 -> DetailScreen(model, { _, _ -> }, forwarded)
                        else -> DetailScreen(model, { _, _ -> }, original)
                    }
                }
            }
        }
        for (screen in 0..2) {
            compose.runOnIdle { page.value = screen }
            val node = compose.onNodeWithText(title, substring = true, useUnmergedTree = true).assertIsDisplayed()
            compose.onNodeWithText(short, substring = true, useUnmergedTree = true).assertDoesNotExist()
            val layouts = mutableListOf<TextLayoutResult>()
            node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            val text = layouts.single().layoutInput.text
            val link = text.getLinkAnnotations(0, text.length).last().item
            compose.runOnIdle {
                link.linkInteractionListener!!.onClick(link)
                assertEquals("video:${android.net.Uri.encode(url)}", model.screen)
                model.back()
            }
        }
    }

    @Test fun mentionTitleAndTabsMeetWithoutAnInternalDivider() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnIdle { model.updateTheme(2); model.navigate("messages") }
        compose.onNodeWithText("@我的").performClick()
        val tab = compose.onNodeWithText("@我的微博").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
        val edge = kotlin.math.round(tab.top).toInt()
        val bitmap = captureBitmap()
        try {
            val x = bitmap.width - 12
            val background = bitmap.getPixel(x, edge + 3)
            val channels = listOf(android.graphics.Color::red, android.graphics.Color::green, android.graphics.Color::blue)
            for (y in edge - 3..edge) {
                val pixel = bitmap.getPixel(x, y)
                assertTrue("Unexpected divider at y=$y: ${pixel.toUInt().toString(16)} vs ${background.toUInt().toString(16)}",
                    channels.all { kotlin.math.abs(it(pixel) - it(background)) <= 4 })
            }
        } finally { bitmap.recycle() }
    }

    @Test fun darkFavoritesTabsUseThePageBackground() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnIdle { model.changeMode(false); model.updateTheme(2); model.navigate("favorites") }
        val tabY = compose.onNodeWithText("我的赞").fetchSemanticsNode().boundsInRoot.center.y.toInt()
        val bodyY = tabY + with(compose.density) { 48.dp.roundToPx() }
        val bitmap = captureBitmap()
        try {
            val x = bitmap.width - 12
            assertEquals(bitmap.getPixel(x, bodyY), bitmap.getPixel(x, tabY))
        } finally { bitmap.recycle() }
    }
    @Test fun articleKeepsOriginalTypographyMetadataAndFailureRecovery() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        var fail = false
        var html = """<h1 node-type="articleTitle">把周末留给山野</h1><div class="authorinfo"><a href="/u/123"><em>山间来信</em></a><span class="time">2026年11月5日</span><span class="num">阅读 128</span></div><div node-type="contentBody"><p>走过薄雾与松林，慢一点也能看到很多。</p><h2>沿着山路继续走</h2><p>在没有信号的路上，听见风吹过树梢。</p><a href="https://example.com/story">阅读全文</a></div>"""
        val intercepted = okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            check(request.url.encodedPath == "/ttarticle/p/show")
            okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK").body((if (fail) "<title>Unavailable</title>" else html).toResponseBody("text/html".toMediaType())).build()
        }.build()
        val field = ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }
        val previous = field.get(model.repository.api)
        field.set(model.repository.api, intercepted)
        try {
            compose.runOnIdle { model.navigate("article:77881") }
            compose.waitUntil(15000) { compose.onAllNodesWithText("把周末留给山野").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText("文章详情").assertIsDisplayed()
            compose.onNodeWithContentDescription("在应用内浏览器打开").assertIsDisplayed()
            compose.onNodeWithText("山间来信  2026年11月5日  阅读 128").assertIsDisplayed()
            val heading = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText("沿着山路继续走").performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(heading) }
            org.junit.Assert.assertEquals(22f, heading.single().layoutInput.style.fontSize.value, .01f)
            org.junit.Assert.assertEquals(29.7f, heading.single().layoutInput.style.lineHeight.value, .01f)
            val density = compose.activity.resources.displayMetrics.density
            org.junit.Assert.assertEquals(129f * density, compose.onNodeWithText("山间来信  2026年11月5日  阅读 128").fetchSemanticsNode().boundsInRoot.center.y, 3f)
            org.junit.Assert.assertEquals(169f * density, compose.onNodeWithText("走过薄雾与松林，慢一点也能看到很多。").fetchSemanticsNode().boundsInRoot.top, 3f)
            capture("article-light")
            compose.runOnIdle { model.updateTheme(2) }
            assertNightText("把周末留给山野"); assertNightText("走过薄雾与松林，慢一点也能看到很多。")
            capture("article-dark")
            compose.runOnIdle { model.back(); fail = true; model.navigate("article:77882") }
            compose.waitUntil(15000) { compose.onAllNodesWithText("文章加载失败").fetchSemanticsNodes().isNotEmpty() }
            capture("article-error-dark")
            compose.runOnIdle { fail = false }
            compose.onNodeWithText("重新加载").performClick()
            compose.waitUntil(15000) { compose.onAllNodesWithText("把周末留给山野").fetchSemanticsNodes().isNotEmpty() }
            val longTitle = "把周末留给山野，沿着山路继续走，听见风吹过树梢。"
            compose.runOnIdle { model.back(); html = html.replace("把周末留给山野", longTitle); model.updateTextScale(1.4f); model.navigate("article:77883") }
            compose.waitUntil(15000) { compose.onAllNodesWithText(longTitle).fetchSemanticsNodes().isNotEmpty() }
            val longLayout = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(longTitle).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(longLayout) }
            assertTrue(longLayout.single().lineCount >= 2)
            val metadata = compose.onNodeWithText("山间来信  2026年11月5日  阅读 128").fetchSemanticsNode().boundsInRoot
            val title = compose.onNodeWithText(longTitle).fetchSemanticsNode().boundsInRoot
            assertTrue("Large multiline title must leave room for author metadata", metadata.top > title.bottom)
            capture("article-large-dark")
        } finally { field.set(model.repository.api, previous); intercepted.dispatcher.executorService.shutdown(); intercepted.connectionPool.evictAll() }
    }
    @Test fun profileSearchKeepsOriginalInitialEmptyCountAndClearStates() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val person = org.json.JSONObject("""{"idstr":"123","screen_name":"山间来信"}""")
        val post = org.json.JSONObject("""{"id":"991","text_raw":"山野里的光影","created_at":"12 分钟前"}""").put("user", person)
        val requests = java.util.concurrent.atomic.AtomicInteger()
        val intercepted = okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            check(request.url.encodedPath == "/ajax/statuses/search")
            check(request.url.queryParameter("uid") == "123")
            requests.incrementAndGet()
            val statuses = org.json.JSONArray().apply { if (request.url.queryParameter("q") == "山野" && request.url.queryParameter("page") == "1") put(post) }
            okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK").body(org.json.JSONObject().put("statuses", statuses).toString().toResponseBody("application/json".toMediaType())).build()
        }.build()
        val field = ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }
        val previous = field.get(model.repository.api); field.set(model.repository.api, intercepted)
        try {
            compose.runOnIdle { model.navigate("profileSearch:123"); model.routeStack.last().profile = parseUser(person) }
            compose.onNodeWithText("输入关键词，检索 @山间来信 的微博").assertIsDisplayed()
            compose.onNodeWithText("搜索", substring = false).assertIsNotEnabled()
            capture("profile-search-light")
            compose.runOnIdle { model.updateTheme(2) }
            assertNightText("输入关键词，检索 @山间来信 的微博")
            capture("profile-search-dark")
            compose.onNode(hasSetTextAction()).performTextInput("山野")
            compose.onNodeWithText("搜索", substring = false).performClick()
            compose.waitUntil(15000) { compose.onAllNodesWithText("包含 \"山野\" 的微博 (1+)").fetchSemanticsNodes().isNotEmpty() }
            org.junit.Assert.assertEquals(1, requests.get())
            capture("profile-search-results-dark")
            compose.onNodeWithText("搜索", substring = false).performClick()
            compose.waitForIdle()
            compose.waitUntil(15000) { requests.get() >= 2 }
            compose.waitUntil(15000) { compose.onAllNodesWithText("包含 \"山野\" 的微博 (1+)").fetchSemanticsNodes().isNotEmpty() }
            org.junit.Assert.assertEquals(2, requests.get())
            compose.onNodeWithContentDescription("清空").performClick()
            compose.onNodeWithText("输入关键词，检索 @山间来信 的微博").assertIsDisplayed()
            compose.onNodeWithText("山野里的光影").assertDoesNotExist()
            compose.onNode(hasSetTextAction()).performTextInput("空")
            compose.onNodeWithText("搜索", substring = false).performClick()
            compose.waitUntil(15000) { compose.onAllNodesWithText("未找到与 \"空\" 相关的微博").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText("请尝试更换关键词搜索").assertIsDisplayed()
            compose.onNodeWithText("暂无内容").assertDoesNotExist()
            capture("profile-search-empty-dark")
        } finally { field.set(model.repository.api, previous); intercepted.dispatcher.executorService.shutdown(); intercepted.connectionPool.evictAll() }
    }
    @Test fun profileKeepsOriginalCountsFiltersAndVideoNavigation() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val person = org.json.JSONObject("""{"idstr":"123","screen_name":"山间来信","description":"记录身边的光影","gender":"f","ip_location":"北京","friends_count":128,"followers_count":32000,"statuses_count":48,"verified":true,"verified_type":0}""")
        val post = org.json.JSONObject("""{"id":"234","text_raw":"把周末留给山野。","created_at":"12 分钟前","attitudes_count":128,"page_info":{"type":"video","media_info":{"stream_url":"https://example.com/movie.mp4","duration":125,"play_count":32000}}}""").put("user", person)
        val intercepted = okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            val value = when (request.url.encodedPath) {
                "/ajax/profile/info" -> org.json.JSONObject().put("data", org.json.JSONObject().put("user", person))
                "/ajax/statuses/mymblog" -> org.json.JSONObject().put("data", org.json.JSONObject().put("list", org.json.JSONArray().apply { if (request.url.queryParameter("page") == "1") put(post) }))
                else -> error("Unexpected profile request: ${request.url.encodedPath}")
            }
            okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK").body(value.toString().toResponseBody("application/json".toMediaType())).build()
        }.build()
        val field = ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }
        val previous = field.get(model.repository.api)
        field.set(model.repository.api, intercepted)
        try {
            compose.runOnIdle { model.navigate("profile:123") }
            compose.waitUntil(15000) { compose.onAllNodesWithText("UID: 123").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText("3.2万").assertIsDisplayed()
            compose.onNodeWithText("暂无内容").assertDoesNotExist()
            capture("profile-light")
            compose.onAllNodesWithText("相册").onFirst().performClick()
            compose.onNodeWithText("相册暂无图片").assertIsDisplayed()
            compose.onAllNodesWithText("视频").onFirst().performClick()
            compose.onNodeWithText("02:05").assertIsDisplayed()
            capture("profile-video-light")
            compose.runOnIdle { model.updateTheme(2) }
            assertNightText("记录身边的光影")
            capture("profile-video-dark")
            compose.onNode(hasText("微博") and isSelectable()).performClick()
            capture("profile-dark")
            compose.onNodeWithText("日期筛选").performClick()
            compose.onNodeWithText("2025年").performClick()
            compose.onNodeWithText("12月").performScrollTo().performClick()
            compose.onNodeWithText("确定筛选").performClick()
            val selectedDate = compose.onNodeWithText("2025年12月", useUnmergedTree = true).assertIsDisplayed()
            val layout = mutableListOf<TextLayoutResult>()
            selectedDate.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layout) }
            assertEquals(1, layout.single().lineCount)
            compose.onNodeWithText("2025年12月").performClick()
            compose.onNodeWithText("重置筛选").performClick()
            compose.waitUntil(15000) { compose.onAllNodesWithText("02:05").fetchSemanticsNodes().isNotEmpty() }
            compose.onAllNodesWithText("视频").onFirst().performClick()
            compose.onNodeWithText("02:05").performClick()
            compose.runOnIdle { assertTrue(model.screen.startsWith("video:")); org.junit.Assert.assertEquals("02:05", model.routeStack.last().media?.duration) }
        } finally { field.set(model.repository.api, previous); intercepted.dispatcher.executorService.shutdown(); intercepted.connectionPool.evictAll() }
    }
    @Test fun feedOpensGalleryAndDetailWithoutChangingTheRootPosition() {
        ready()
        compose.onNodeWithText("最新微博").assertIsDisplayed()
        capture("feed-light")
        compose.onNodeWithContentDescription("山间来信的第 1 张图片").performClick()
        compose.onNodeWithText("1 / 3", substring = true).assertExists()
        compose.onNode(isDialog()).assertDoesNotExist()
        capture("gallery-plain")
        compose.runOnUiThread { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].setOption("liquidGlass", true) }
        compose.onNodeWithContentDescription("返回").performTouchInput { down(center) }
        compose.mainClock.advanceTimeBy(600)
        compose.onNodeWithContentDescription("返回").performTouchInput { advanceEventTime(600); up() }
        compose.onNodeWithText("1 / 3", substring = true).assertExists()
        capture("gallery-glass")
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithText(PreviewContent.posts[0].text, useUnmergedTree = true).performTouchInput { click() }
        compose.onNodeWithText("文章详情").assertIsDisplayed()
        capture("detail-light")
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithText("最新微博").assertIsDisplayed()
    }
    @Test fun postMoreMenuUsesFlutterActionsWithoutAnAuthorHeader() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val post = model.feed.first().copy(author = "菜单专用测试作者")
        compose.runOnIdle { model.actionPost = post }
        compose.onNodeWithText(post.author).assertDoesNotExist()
        listOf("查看编辑记录", "复制微博正文", "收藏微博", "复制微博链接", "查看 @${post.author} 的主页", "屏蔽该博主")
            .forEach { compose.onNodeWithText(it).assertExists() }
        capture("post-more-light")
        compose.onNodeWithText("复制微博链接").performClick()
        compose.onNodeWithText("查看编辑记录").assertDoesNotExist()
    }
    @Test fun liveGalleryUsesPlaybackLabelAndTracksSelectedThumbnail() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnIdle {
            model.updateTextScale(.95f)
            val post = model.feed.first()
            val live = post.images[1].copy(live = true, video = "https://example.invalid/live.mp4")
            model.updatePost(post.copy(images = listOf(post.images[0], live, post.images[2])))
        }
        compose.onNodeWithContentDescription("山间来信的第 2 张图片").performClick()
        val play = compose.onNodeWithText("播放 Live 图").assertIsDisplayed().assertHasClickAction()
        val capsule = play.getUnclippedBoundsInRoot()
        val label = compose.onNodeWithText("播放 Live 图", useUnmergedTree = true).getUnclippedBoundsInRoot()
        val capsuleHeight = capsule.bottom - capsule.top
        assertEquals(51f, (capsule.right - capsule.left - (label.right - label.left)).value, 1f) // Padding, icon and gap.
        assertTrue("Expected Flutter's reference capsule height at 95%, got $capsuleHeight", capsuleHeight in 30.5.dp..32.dp)
        compose.onNodeWithText("2 / 3").assertDoesNotExist()
        compose.onNodeWithContentDescription("第 2 张图片").assertIsSelected()
        play.performClick()
        compose.onNodeWithText("暂停 Live 图").assertIsDisplayed().assertHeightIsEqualTo(capsuleHeight)
        val galleryRoot = compose.onNode(isRoot())
        galleryRoot.performTouchInput {
            swipe(center, center + androidx.compose.ui.geometry.Offset(width * .08f, 0f), 800)
        }
        compose.onNodeWithText("播放 Live 图").assertIsDisplayed()
        compose.onNodeWithContentDescription("第 2 张图片").assertIsSelected()
        compose.onNodeWithContentDescription("下载").performClick()
        compose.onNodeWithText("保存实况照片").assertIsDisplayed()
        compose.onNodeWithText("保存静态高清大图").assertIsDisplayed()
        compose.onNodeWithText("保存 Live 动图 / 视频").assertIsDisplayed()
        compose.onNodeWithText("全部保存 (高清大图 + Live 视频)").assertIsDisplayed()
        val sheet = compose.onNodeWithText("保存实况照片").fetchSemanticsNode().boundsInRoot
        assertTrue(sheet.top > compose.activity.window.decorView.height / 2f)
        compose.onNode(isDialog()).performTouchInput { click(androidx.compose.ui.geometry.Offset(width / 2f, 10f)) }
        compose.onNodeWithText("保存实况照片").assertDoesNotExist()
        compose.onNodeWithContentDescription("第 1 张图片").assertIsNotSelected().performClick()
        compose.onNodeWithText("1 / 3").assertIsDisplayed()
        compose.onNodeWithContentDescription("第 1 张图片").assertIsSelected()
    }

    @Test fun galleryThumbnailBadgesUseSharedHintsWithoutPagingToTheOriginals() {
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val images = List(9) { Media(url = "https://example.invalid/hdr-strip-$it.jpg", artwork = 1) }
        lateinit var pager: androidx.compose.foundation.pager.PagerState
        compose.runOnIdle {
            images.take(8).forEach { MediaFiles.recordHdrProbe(it.url, true) }
            assertTrue(images.none { MediaFiles.hdr.containsKey(it.url) })
        }
        compose.activity.setContent {
            CompositionLocalProvider(LocalReview provides model) {
                ReviewTheme(false) {
                    pager = androidx.compose.foundation.pager.rememberPagerState { images.size }
                    GalleryThumbnails(images, pager, Modifier.fillMaxWidth(), {}, {})
                }
            }
        }
        val strip = compose.onNode(hasScrollToIndexAction())
        for (index in 0 until 8) {
            strip.performScrollToIndex(index)
            compose.onNodeWithContentDescription("第 ${index + 1} 张 HDR 图片", useUnmergedTree = true).assertIsDisplayed()
        }
        strip.performScrollToIndex(8)
        val last = compose.onNodeWithContentDescription("第 9 张 HDR 图片", useUnmergedTree = true)
        last.assertDoesNotExist()
        compose.runOnIdle { MediaFiles.recordHdrProbe(images.last().url, true) }
        last.assertIsDisplayed()
        val layout = mutableListOf<TextLayoutResult>()
        last.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layout) }
        assertEquals(androidx.compose.ui.text.font.FontWeight.Normal, layout.single().layoutInput.style.fontWeight)
        compose.runOnIdle {
            assertEquals(0, pager.currentPage)
            assertTrue(images.none { MediaFiles.hdr.containsKey(it.url) })
            assertTrue(!MediaFiles.hasHdrBadge(images.first().copy(video = "video")))
        }
    }

    @Test fun profileKeepsTheTimelineAvatarWhileProfileDataLoads() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val profileGate = java.util.concurrent.CountDownLatch(1)
        val avatar = "https://example.invalid/timeline-avatar.png"
        val client = okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            val body = if (request.url.encodedPath == "/ajax/profile/info") {
                check(profileGate.await(25, java.util.concurrent.TimeUnit.SECONDS))
                """{"ok":1,"data":{"user":{"idstr":"42","screen_name":"主页资料已加载","avatar_hd":"https://example.invalid/large.png"}}}"""
            } else """{"ok":1,"data":{"list":[]}}"""
            okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                .body(body.toResponseBody()).build()
        }.build()
        val field = ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }
        val previous = field.get(model.repository.api)
        field.set(model.repository.api, client)
        try {
            compose.runOnIdle {
                val post = model.feed.first()
                model.updatePost(post.copy(uid = "42", avatar = avatar, demo = false))
            }
            compose.onNodeWithText("山间来信").performClick()
            compose.onNodeWithText("UID: 42").assertIsDisplayed()
            compose.runOnIdle { assertEquals(avatar, model.routeStack.last().profilePreview?.avatar) }
            profileGate.countDown()
            compose.waitUntil(15000) { compose.onAllNodesWithText("主页资料已加载").fetchSemanticsNodes().isNotEmpty() }
        } finally {
            profileGate.countDown()
            field.set(model.repository.api, previous)
        }
    }

    @Test fun knownUserAndCommentKeepTheirProfilePreview() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val person = User("42", "搜索用户", "https://example.invalid/avatar.png", verified = "已认证")
        compose.runOnIdle {
            model.openProfile(person)
            assertEquals(person, model.routeStack.last().profilePreview)
            model.back()
            model.openProfile(Comment(id = "9", uid = "43", author = "评论作者", avatar = "https://example.invalid/comment.png", text = "正文", raw = """{"user":{"idstr":"43","verified":true,"verified_type":0}}"""))
            assertEquals("43", model.routeStack.last().profilePreview?.id)
            assertEquals("评论作者", model.routeStack.last().profilePreview?.name)
            assertEquals("https://example.invalid/comment.png", model.routeStack.last().profilePreview?.avatar)
            assertTrue(model.routeStack.last().profilePreview?.isVerified == true)
            model.back()
            val count = model.routeStack.size
            model.openProfile(User("", "无标识", ""))
            assertEquals(count, model.routeStack.size)
        }
    }
    @Test fun safePreferenceReloadKeepsTheCurrentPage() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnIdle {
            model.navigate("backup")
            val route = model.routeStack.last()
            val owner = model.uid
            model.updateTheme(2)
            val preferences = ReviewModel::class.java.getDeclaredField("prefs").apply { isAccessible = true }.get(model) as android.content.SharedPreferences
            preferences.edit().putInt("theme", 1).commit()
            kotlinx.coroutines.runBlocking { model.reloadPreferences(reloadAccount = false) }
            assertEquals(1, model.theme)
            assertEquals(owner, model.uid)
            assertEquals(route, model.routeStack.last())
            assertEquals("backup", model.screen)
        }
        compose.onNodeWithText("WebDAV 云端备份与恢复").assertIsDisplayed()
    }
    @Test fun standaloneVideoCoversTheNavigationSafeArea() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnUiThread {
            val statusBars = androidx.core.view.WindowInsetsCompat.Type.statusBars()
            val navigationBars = androidx.core.view.WindowInsetsCompat.Type.navigationBars()
            val density = compose.activity.resources.displayMetrics.density
            androidx.core.view.ViewCompat.dispatchApplyWindowInsets(composeHost(), androidx.core.view.WindowInsetsCompat.Builder()
                .setInsets(statusBars, androidx.core.graphics.Insets.of(0, (42 * density).toInt(), 0, 0)).setVisible(statusBars, true)
                .setInsets(navigationBars, androidx.core.graphics.Insets.of(0, 0, 0, (24 * density).toInt())).setVisible(navigationBars, true).build())
        }
        compose.runOnIdle {
            model.navigate("video:https://example.invalid/movie.mp4")
            model.routeStack.last().media = Media(video = "https://example.invalid/movie.mp4")
        }
        val bounds = compose.onNodeWithTag("standalone-video").fetchSemanticsNode().boundsInRoot
        assertEquals(0f, bounds.top, 1f)
        assertEquals(compose.activity.window.decorView.height.toFloat(), bounds.bottom, 1f)
        val image = captureBitmap()
        assertEquals(android.graphics.Color.BLACK, image.getPixel(2, image.height - 2))
        image.recycle()
    }
    @Test fun editingUsesMidAndRetainsOriginalVisibility() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val writes = java.util.concurrent.atomic.AtomicInteger()
        val field = ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }
        val previous = field.get(model.repository.api)
        field.set(model.repository.api, okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            if (request.method == "POST") {
                assertEquals("/ajax/statuses/modify", request.url.encodedPath)
                val form = request.body as okhttp3.FormBody
                val fields = (0 until form.size).associate { form.name(it) to form.value(it) }
                assertEquals("12345", fields["mid"])
                assertEquals("1", fields["visible"])
                assertEquals("修改后正文", fields["content"])
                org.junit.Assert.assertFalse(fields.containsKey("id"))
                writes.incrementAndGet()
            }
            okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                .body("""{"ok":1}""".toResponseBody()).build()
        }.build())
        try {
            compose.runOnIdle {
                model.changeMode(false)
                @Suppress("UNCHECKED_CAST")
                val owner = ReviewModel::class.java.getDeclaredField("uid\$delegate").apply { isAccessible = true }.get(model) as androidx.compose.runtime.MutableState<String>
                owner.value = "42"
                ReviewModel::class.java.getDeclaredField("cookie").apply { isAccessible = true }.set(model, "SUB=fixture; XSRF-TOKEN=fixture")
                model.saveDraft("修改后正文")
                model.navigate("edit:12345", Post("12345", "本人", text = "原文", raw = """{"visible":{"type":1}}"""))
            }
            compose.onNodeWithText("私密").assertIsDisplayed()
            compose.runOnIdle { assertEquals("42", model.uid); org.junit.Assert.assertFalse(model.demo) }
            compose.onNodeWithText("保存修改").performClick()
            compose.waitUntil(15000) {
                compose.onAllNodesWithText("保存修改").fetchSemanticsNodes().isEmpty() || model.actionError != null
            }
            compose.runOnIdle {
                assertEquals("Edit failed: screen=${model.screen}, error=${model.actionError}", 1, writes.get())
                assertEquals("root", model.screen)
            }
            assertEquals("", model.draft)
        } finally { field.set(model.repository.api, previous) }
    }
    @Test fun publisherKeepsCompactSettingsAndSelectedVisibility() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val field = ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }
        val previous = field.get(model.repository.api)
        field.set(model.repository.api, okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            okhttp3.Response.Builder().request(chain.request()).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                .body("""{"ok":1,"data":{"mblog_statement_list":[{"type":1,"name":"含人工智能生成内容"}]}}""".toResponseBody()).build()
        }.build())
        try {
            compose.runOnIdle { model.navigate("draft") }
            capture("publish-default-light")
            compose.onNodeWithText("发送").assertIsEnabled().performClick()
            compose.runOnIdle { assertEquals("请输入微博内容或添加图片/视频", model.notice) }
            compose.onNodeWithContentDescription("定时微博").assertIsDisplayed().performClick()
            compose.onNodeWithText("定时微博").assertIsDisplayed()
            compose.onNodeWithText("知道了").performClick()
            compose.onNodeWithContentDescription("可见范围").performClick()
            compose.onNodeWithText("仅自己可见").performClick()
            compose.onNodeWithText("私密").assertIsDisplayed()
            compose.onNodeWithContentDescription("内容声明").performClick()
            compose.onNodeWithText("含人工智能生成内容").performClick()
            compose.onNodeWithText("AI").assertIsDisplayed()
            compose.onNodeWithText("你在哪里").assertIsDisplayed()
            compose.onNodeWithContentDescription("媒体").assertIsDisplayed()
            capture("publish-light")
            compose.runOnIdle { model.updateTheme(2) }
            capture("publish-dark")
            compose.onNodeWithContentDescription("可见范围").performClick()
            compose.onNodeWithText("仅自己可见").assertIsDisplayed()
            capture("publish-visibility-dark")
        } finally { field.set(model.repository.api, previous) }
    }
    @Test fun editedBadgeOpensOriginalSheetAndNativeVideoShowsItsMetadata() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnIdle {
            val post = model.feed.first()
            val raw = org.json.JSONObject().put("edit_count", 2).put("page_info", org.json.JSONObject().put("media_info", org.json.JSONObject().put("stream_url", "https://example.com/movie.mp4").put("duration", 125).put("play_count", 32000)))
            model.updatePost(post.copy(raw = raw.toString(), images = listOf(videoMedia(raw.getJSONObject("page_info"))!!)))
        }
        compose.onNodeWithText("3.2万次播放").assertIsDisplayed()
        compose.onNodeWithText("02:05").assertIsDisplayed()
        capture("native-video-card-light")
        compose.onNodeWithText("已编辑").performClick()
        compose.onNodeWithText("微博编辑记录").assertIsDisplayed()
        compose.onNodeWithText("未获取到编辑记录或该微博无需编辑历史").assertIsDisplayed()
        val contentBottom = compose.onNodeWithTag("edit-history-content").fetchSemanticsNode().boundsInRoot.bottom
        val screenBottom = compose.activity.window.decorView.height
        assertTrue("Edit history must be bottom anchored: $contentBottom vs $screenBottom", screenBottom - contentBottom <= 24 * compose.activity.resources.displayMetrics.density)
        compose.onNodeWithContentDescription("关闭编辑记录").performClick()
        compose.onNodeWithText("微博编辑记录").assertDoesNotExist()
    }
    @Test fun postMenuLoadsActualRevisionTextAndOlderPages() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val pages = java.util.concurrent.CopyOnWriteArrayList<String>()
        val client = okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            check(request.url.encodedPath == "/ajax/statuses/editHistory")
            check(request.url.queryParameter("mid") == "12345")
            check(request.header("Referer") == "https://weibo.com/")
            val page = checkNotNull(request.url.queryParameter("page"))
            pages += page
            val body = when (page) {
                "1" -> """{"ok":1,"total":"3","statuses":[{"mid":"12345","text_raw":"当前摘要","full_text_raw":"当前完整修订内容"},{"id":"12345_1","text_raw":"中间版本正文","retweeted_status":{"text_raw":"历史快照不含完整原帖"}}]}"""
                "2" -> """{"ok":1,"data":{"total":3,"statuses":[{"mid":"-","text_raw":"最初发布正文"}]}}"""
                else -> error("Unexpected revision page: $page")
            }
            okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                .body(body.toResponseBody()).build()
        }.build()
        val field = ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }
        val previous = field.get(model.repository.api)
        field.set(model.repository.api, client)
        try {
            compose.runOnIdle {
                model.changeMode(false)
                model.actionPost = Post("12345", "测试作者", text = "", raw = """{"edit_count":2}""")
            }
            compose.onNodeWithText("查看编辑记录").performClick()
            compose.onNodeWithText("微博编辑记录").assertIsDisplayed()
            try {
                compose.waitUntil(15000) {
                    compose.mainClock.advanceTimeByFrame()
                    org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
                    compose.onAllNodesWithText("当前完整修订内容").fetchSemanticsNodes().isNotEmpty()
                }
            } catch (failure: androidx.compose.ui.test.ComposeTimeoutException) {
                val roots = compose.onAllNodes(isRoot()).fetchSemanticsNodes().indices.joinToString("\n") { compose.onAllNodes(isRoot())[it].printToString() }
                throw AssertionError("Revision pages=$pages, demo=${model.demo}\n$roots", failure)
            }
            compose.onNodeWithText("共 3 个修订版本").assertIsDisplayed()
            compose.onNodeWithText("当前完整修订内容").assertIsDisplayed()
            // Older revisions load at the list end; visit it instead of assuming all cards fit.
            compose.onNodeWithTag("edit-history-list").performScrollToIndex(1)
            compose.onNodeWithText("中间版本正文").assertIsDisplayed()
            compose.onNodeWithTag("edit-history-list").performTouchInput { swipeUp() }
            compose.waitUntil(15000) {
                compose.mainClock.advanceTimeByFrame()
                org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
                compose.onAllNodesWithText("最初发布正文").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("最初发布正文").performScrollTo().assertIsDisplayed()
            compose.onNodeWithText("首次发布", substring = true).assertIsDisplayed()
            compose.onNodeWithText("当前摘要").assertDoesNotExist()
            assertEquals(listOf("1", "2"), pages.toList())
        } finally {
            field.set(model.repository.api, previous)
        }
    }
    @Test @GraphicsMode(GraphicsMode.Mode.LEGACY)
    fun browserKeepsOriginalToolbarAndNativeNavigation() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnIdle { model.openLink("https://example.com/reading") }
        compose.onNodeWithText("网页浏览").assertIsDisplayed()
        compose.onNodeWithText("https://example.com/reading").assertIsDisplayed()
        fun findWeb(view: android.view.View): android.webkit.WebView? {
            if (view is android.webkit.WebView) return view
            if (view is android.view.ViewGroup) for (i in 0 until view.childCount) findWeb(view.getChildAt(i))?.let { return it }
            return null
        }
        val web = findWeb(compose.activity.window.decorView)!!
        compose.runOnIdle {
            org.junit.Assert.assertFalse(web.settings.allowFileAccess)
            org.junit.Assert.assertFalse(web.settings.allowContentAccess)
            web.webChromeClient!!.onReceivedTitle(web, "阅读页面")
            web.webViewClient.onPageFinished(web, "https://example.com/reading")
        }
        compose.onNodeWithText("阅读页面").assertIsDisplayed()
        compose.onNodeWithContentDescription("更多").performClick()
        compose.onNodeWithText("在外部浏览器打开").assertIsDisplayed()
        compose.onNodeWithText("复制链接").performClick()
        val clipboard = compose.activity.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        org.junit.Assert.assertEquals("https://example.com/reading", clipboard.primaryClip!!.getItemAt(0).text.toString())
        compose.runOnIdle { assertTrue(model.openNativeLink("https://m.weibo.cn/profile/1234567890")) }
        org.junit.Assert.assertEquals("profile:1234567890", model.screen)
        compose.runOnIdle { model.back() }
        compose.onNodeWithText("阅读页面").assertIsDisplayed()
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithText("最新微博").assertIsDisplayed()
    }
    @Test fun loginKeepsOriginalFieldsInBothThemes() {
        ready()
        val inset = injectStatusBarInset()
        val density = compose.activity.resources.displayMetrics.density
        compose.runOnIdle { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].navigate("account") }
        compose.onNodeWithText("账号登录").assertIsDisplayed()
        assertEquals(inset + 28 * density, compose.onNodeWithContentDescription("返回").fetchSemanticsNode().boundsInRoot.center.y, 2f)
        assertEquals(inset + 92 * density, compose.onNodeWithTag("login-form").fetchSemanticsNode().boundsInRoot.top, 2f)
        compose.runOnIdle { assertEquals(0, compose.activity.window.attributes.flags and android.view.WindowManager.LayoutParams.FLAG_SECURE) }
        capture("login-sms-light")
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText("输入手机号", useUnmergedTree = true).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        org.junit.Assert.assertEquals(androidx.compose.ui.unit.TextUnit(16f, androidx.compose.ui.unit.TextUnitType.Sp), layouts.single().layoutInput.style.fontSize)
        compose.onNodeWithText("用账号密码登录").performClick()
        assertEquals(inset + 92 * density, compose.onNodeWithTag("login-form").fetchSemanticsNode().boundsInRoot.top, 2f)
        capture("login-password-light")
        compose.onNode(hasSetTextAction() and hasText("登录密码", substring = true)).performTextInput("private-test")
        compose.onNodeWithContentDescription("显示密码").performClick()
        compose.onNodeWithText("private-test").assertExists()
        compose.runOnIdle { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].updateTheme(2) }
        assertNightText("private-test", input = true)
        capture("login-password-dark")
        compose.onNodeWithText("用验证码登录").performClick()
        capture("login-sms-dark")
        compose.onNodeWithText("Cookie 导入").performClick()
        compose.onNodeWithText("导入 Cookie").assertIsDisplayed()
        compose.onNodeWithText("取消").performClick()
        compose.onNodeWithText("导入 Cookie").assertDoesNotExist()
    }
    @Test fun resendingSmsClearsTheCodeEvenWhenTheServerReusesTheChallenge() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        @Suppress("UNCHECKED_CAST")
        fun <T> setSmsState(name: String, value: T) {
            val field = ReviewModel::class.java.getDeclaredField("$name${'$'}delegate").apply { isAccessible = true }
            (field.get(model) as androidx.compose.runtime.MutableState<T>).value = value
        }
        compose.runOnIdle { model.navigate("account") }
        compose.onNode(hasSetTextAction() and hasText("输入手机号")).performTextInput("13800000000")
        compose.runOnIdle {
            setSmsState("smsPhone", "13800000000")
            setSmsState("smsArea", "86")
            setSmsState("smsChallenge", "test-challenge")
            setSmsState("smsAvailableAt", 1L)
        }
        compose.onNode(hasSetTextAction() and hasText("输入短信验证码")).performTextInput("012345")
        compose.onNode(hasSetTextAction() and hasText("012345")).assertExists()
        compose.runOnIdle { setSmsState("smsAvailableAt", 2L) }
        compose.onNode(hasSetTextAction() and hasText("012345")).assertDoesNotExist()
        compose.onNode(hasSetTextAction() and hasText("输入短信验证码")).assertIsDisplayed()
    }
    @Test fun ownToolbarsReserveTheStatusInsetOnce() {
        ready()
        val inset = injectStatusBarInset()
        val density = compose.activity.resources.displayMetrics.density
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        for (route in listOf("draft", "edit:999", "groups", "browser:", "profileSearch:123",
            "topicSearch:100808aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:摄影", "topics", "search", "searchResults:山野", "trends")) {
            compose.runOnIdle { model.navigate(route) }
            val y = compose.onNodeWithContentDescription("返回").fetchSemanticsNode().boundsInRoot.center.y
            assertEquals(route, inset + 28 * density, y, 2f)
            compose.runOnIdle { model.back() }
            compose.onNodeWithText("最新微博").assertIsDisplayed()
        }
        compose.runOnIdle { model.navigate("webLogin") }
        assertEquals(inset + 24 * density, compose.onNodeWithContentDescription("返回账号").fetchSemanticsNode().boundsInRoot.center.y, 2f)
        compose.runOnIdle { assertEquals(0, compose.activity.window.attributes.flags and android.view.WindowManager.LayoutParams.FLAG_SECURE) }
    }
    @Test fun trendsTabWidthFollowsLabelInsteadOfMaterialMinimum() {
        ready()
        compose.runOnIdle { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].navigate("trends") }
        val tab = compose.onNodeWithText("文娱")
        tab.assertIsDisplayed()
        val density = compose.activity.resources.displayMetrics.density
        val widthDp = tab.fetchSemanticsNode().boundsInRoot.width / density
        assertTrue("Expected label plus 28dp, found ${widthDp}dp", widthDp in 50f..64f)
    }

    @Test fun trendsLoadsSilentlyUntilAnActualPull() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val count = java.util.concurrent.atomic.AtomicInteger()
        val gates = List(3) { java.util.concurrent.CountDownLatch(1) }
        val searchStarted = java.util.concurrent.atomic.AtomicBoolean()
        val searchGate = java.util.concurrent.CountDownLatch(1)
        val client = okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            if (request.url.host == "s.weibo.com" && request.url.encodedPath == "/weibo") {
                searchStarted.set(true)
                check(searchGate.await(25, java.util.concurrent.TimeUnit.SECONDS))
                return@addInterceptor okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                    .body("<div class='card-no-result'></div>".toResponseBody("text/html".toMediaType())).build()
            }
            val primary = request.url.encodedPath == "/ajax/side/hotSearch"
            val attempt = if (primary) count.getAndIncrement() else -1
            gates.getOrNull(attempt)?.let { check(it.await(25, java.util.concurrent.TimeUnit.SECONDS)) }
            val rows = org.json.JSONArray()
            if (primary && attempt == 2) rows.put(org.json.JSONObject().put("word", "下拉新增首条"))
            repeat(30) {
                val label = when {
                    !primary -> "分类热榜 $it"
                    attempt == 1 && it == 1 -> "受控热榜 已更新"
                    else -> "受控热榜 $it"
                }
                rows.put(org.json.JSONObject().put("word", label))
            }
            val body = org.json.JSONObject().put("data", org.json.JSONObject().put("realtime", rows)).toString()
            okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                .body(body.toResponseBody("application/json".toMediaType())).build()
        }.build()
        val field = ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }
        val previous = field.get(model.repository.api)
        field.set(model.repository.api, client)
        try {
            compose.runOnIdle { model.changeMode(false); model.tapTab(1) }
            compose.onNodeWithText("微博热搜").assertIsDisplayed()
            compose.waitUntil(15000) { count.get() >= 1 }
            assertEquals(1, count.get())
            compose.onNodeWithText("正在刷新...", useUnmergedTree = true).assertDoesNotExist()
            gates[0].countDown()
            val firstRow = compose.onNodeWithText("受控热榜 0")
            compose.waitUntil(15000) { compose.onAllNodesWithText("受控热榜 0").fetchSemanticsNodes().isNotEmpty() }
            val rowTop = firstRow.fetchSemanticsNode().boundsInRoot.top
            compose.onNodeWithText("刷新成功", useUnmergedTree = true).assertDoesNotExist()

            compose.runOnIdle { model.tapTab(1); model.tapTab(1) }
            compose.waitForIdle()
            compose.waitUntil(15000) { count.get() >= 2 }
            assertEquals(2, count.get())
            compose.onNodeWithText("正在刷新...", useUnmergedTree = true).assertDoesNotExist()
            assertEquals(rowTop, firstRow.fetchSemanticsNode().boundsInRoot.top, 1f)
            gates[1].countDown()
            compose.waitUntil(15000) { compose.onAllNodesWithText("受控热榜 已更新").fetchSemanticsNodes().isNotEmpty() }
            compose.runOnIdle { model.tapTab(0) }
            compose.onNodeWithText("最新微博").assertIsDisplayed()
            compose.runOnIdle { model.tapTab(1) }
            firstRow.assertIsDisplayed()
            assertEquals(2, count.get())

            val verticalList = SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange)
            compose.onNode(verticalList and hasAnyDescendant(hasText("受控热榜 0"))).performTouchInput {
                swipeDown(startY = height * .25f, endY = height * .8f, durationMillis = 320)
            }
            compose.waitForIdle()
            compose.waitUntil(15000) { count.get() >= 3 }
            assertEquals(3, count.get())
            compose.onNodeWithText("正在刷新...", useUnmergedTree = true).assertExists()
            gates[2].countDown()
            compose.waitUntil(15000) { compose.onAllNodesWithText("正在刷新...", useUnmergedTree = true).fetchSemanticsNodes().isEmpty() }
            compose.mainClock.advanceTimeBy(1500)
            compose.waitForIdle()
            val newFirst = compose.onNodeWithText("下拉新增首条").assertIsDisplayed()
            assertEquals(rowTop, newFirst.fetchSemanticsNode().boundsInRoot.top, 1f)

            firstRow.performClick()
            compose.onNodeWithContentDescription("返回").assertIsDisplayed()
            compose.waitUntil(15000) { searchStarted.get() }
            compose.onNodeWithText("正在刷新...", useUnmergedTree = true).assertDoesNotExist()
            searchGate.countDown()
            compose.waitUntil(15000) { compose.onAllNodesWithText("暂无\"综合\"相关内容").fetchSemanticsNodes().isNotEmpty() }
        } finally {
            gates.forEach { it.countDown() }
            searchGate.countDown()
            field.set(model.repository.api, previous)
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
        }
    }
    @Test fun backupExplainsCredentialModesAndMakesTheWholeRowSelectable() {
        ready()
        compose.runOnIdle { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].navigate("backup") }
        compose.onNodeWithText("备份设置、搜索和浏览历史，不含图片和视频缓存。").assertIsDisplayed()
        val safe = compose.onNodeWithText("全量安全备份")
        val full = compose.onNodeWithText("全量备份")
        for ((include, row) in listOf(false to safe, true to full)) {
            val rowCenter = row.fetchSemanticsNode().boundsInRoot.center.y
            val radioCenter = compose.onNodeWithTag("backup-mode-radio-$include", useUnmergedTree = true)
                .fetchSemanticsNode().boundsInRoot.center.y
            assertEquals(rowCenter, radioCenter, 1f)
        }
        safe.assertIsSelected()
        compose.onNodeWithText("不含登录凭据及 WebDAV 密码").assertIsDisplayed()
        compose.onNodeWithText("含明文凭据，请妥善保管").assertIsDisplayed()
        full.performClick().assertIsSelected()
        safe.assertIsNotSelected()
        compose.onNodeWithText("从云端恢复备份").performScrollTo().performClick()
        compose.onNodeWithText("全量备份会替换登录凭据和 WebDAV 密码。", substring = true).assertIsDisplayed()
        compose.onNodeWithText("取消").performClick()
    }
    @Test fun settingsKeepsTheOriginalGroupsAndDarkMode() {
        ready()
        compose.onNodeWithText("设置").performClick()
        val inset = injectStatusBarInset()
        compose.runOnUiThread {
            val window = compose.activity.window
            assertTrue(androidx.core.view.WindowCompat.getInsetsController(window, window.decorView).isAppearanceLightStatusBars)
        }
        compose.onNodeWithText("偏好与功能").assertIsDisplayed()
        assertTrue(compose.onNodeWithText("偏好与功能").fetchSemanticsNode().boundsInRoot.top >= inset)
        compose.onNodeWithText("存储与备份").assertIsDisplayed()
        capture("settings-light")
        fun assertStatusBackground(capture: String, expected: Int) {
            val bitmap = android.graphics.BitmapFactory.decodeFile("build/reports/screenshots/$capture.png")
            try { assertEquals(expected, bitmap.getPixel(8, inset / 2)) } finally { bitmap.recycle() }
        }
        assertStatusBackground("settings-light", 0xFFFFF8F7.toInt())
        compose.onNodeWithText("个性化").performClick()
        capture("theme-light")
        compose.onNodeWithTag("font-size-label").performScrollTo().assertTextEquals("100%")
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnIdle {
            assertEquals(1f, model.textScale, 0f)
            model.updateTextScale(.95f)
            kotlinx.coroutines.runBlocking { model.reloadPreferences(reloadAccount = false) }
            assertEquals(.95f, model.textScale, 0f)
            model.updateTextScale(1f)
        }
        compose.onNodeWithText("深色模式").performScrollTo()
        compose.onNodeWithText("深色模式").performClick()
        assertNightText("纯黑深色模式")
        compose.onNodeWithContentDescription("返回").performClick()
        capture("settings-dark-status")
        assertStatusBackground("settings-dark-status", 0xFF111215.toInt())
        compose.onNodeWithText("个性化").performClick()
        compose.onNodeWithText("纯黑深色模式").performClick()
        assertNightText("纯黑深色模式")
        compose.runOnUiThread {
            val window = compose.activity.window
            val controller = androidx.core.view.WindowCompat.getInsetsController(window, window.decorView)
            assertTrue(!window.isStatusBarContrastEnforced)
            assertTrue(!controller.isAppearanceLightStatusBars)
            assertTrue(!controller.isAppearanceLightNavigationBars)
        }
        capture("theme-dark")
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithText("时间线").performClick()
        assertNightText("山间来信")
        capture("feed-dark")
        compose.onNodeWithContentDescription("发微博").performClick()
        compose.onNode(hasSetTextAction()).performTextInput("深色输入检查")
        assertNightText("深色输入检查", input = true)
    }
    @Test
    fun settingsFeedbackFiresOnceForRowsAndSwitchesAndRespectsThePreference() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.onNodeWithText("设置").performClick()
        expectHaptic()
        val theme = compose.onNodeWithText("个性化")
        theme.performTouchInput { down(center) }
        expectHaptic(-1)
        theme.performTouchInput { up() }
        expectHaptic()

        val switch = compose.onNodeWithText("纯黑深色模式")
        switch.performTouchInput { click(androidx.compose.ui.geometry.Offset(width - 20f, center.y)) }
        expectHaptic()
        compose.runOnIdle { assertTrue(model.bool("pureBlack")) }
        switch.performClick()
        expectHaptic()
        compose.runOnIdle { assertTrue(!model.bool("pureBlack")) }
        compose.onNodeWithText("深色模式").performClick()
        expectHaptic()
        compose.runOnIdle { model.setOption("haptics", false) }
        compose.onNodeWithText("浅色模式").performClick()
        compose.onNodeWithContentDescription("返回").performClick()
        expectHaptic(-1)
        compose.onNodeWithText("偏好与功能").assertIsDisplayed()
    }
    @Test fun groupPanelHasOriginalSectionsAndEditor() {
        ready()
        compose.onNodeWithContentDescription("切换分组").performClick()
        compose.onNodeWithText("默认分组").assertIsDisplayed()
        capture("group-panel")
        compose.onNodeWithText("编辑").performClick()
        compose.onNodeWithText("分组管理").assertIsDisplayed()
        compose.onNodeWithText("热门分组").performClick()
        compose.onNodeWithText("保存").assertIsDisplayed()
        capture("group-management")
    }
    @Test fun groupEditorKeepsSwipeSelectionAndLocalEditsUntilSaved() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnIdle {
            model.updateTextScale(.95f)
            model.setOption("groupsOwner", model.uid)
            model.setOption("saved_personal_groups_json", """[{"id":"11","name":"同事"},{"id":"12","name":"同学"}]""")
            model.navigate("groups")
        }
        val tabBottom = compose.onNodeWithText("个人分组").fetchSemanticsNode().boundsInRoot.bottom
        val firstRow = compose.onNodeWithText("同事").fetchSemanticsNode().boundsInRoot.top
        assertTrue("First group should sit directly below the tabs",
            (firstRow - tabBottom) / compose.activity.resources.displayMetrics.density in 0f..58f)
        compose.onAllNodesWithContentDescription("重命名").onFirst().performClick()
        compose.onNode(hasSetTextAction()).assertIsFocused().performTextClearance()
        compose.onNode(hasSetTextAction()).performTextInput("工作伙伴")
        compose.onNodeWithText("确定").performClick()
        compose.onNodeWithText("工作伙伴").assertIsDisplayed()
        compose.onNodeWithTag("groups-pager").performTouchInput { swipeLeft() }
        compose.onNodeWithText("我的分类 (仅调整本地显示，点击每项移除)").assertIsDisplayed()
        compose.onNodeWithText("全部关注").performClick()
        compose.onNodeWithText("已添加全部默认分类").assertDoesNotExist()
        compose.onNodeWithTag("groups-pager").performTouchInput { swipeLeft() }
        val density = compose.activity.resources.displayMetrics.density
        val chip = compose.onNodeWithText("热门").fetchSemanticsNode().boundsInRoot
        assertEquals(60.6f, chip.width / density, 1f)
        assertEquals(37f, chip.height / density, 1f)
        val recommendedTitle = compose.onNodeWithText("推荐分类 (点击添加到我的分类)").fetchSemanticsNode().boundsInRoot
        assertEquals(210f, recommendedTitle.top / density, 2f)
        capture("group-hot-reference-light")
        compose.onNodeWithText("热门").performClick()
        compose.onNodeWithText("暂未添加任何热门频道（可从下方推荐分类点击添加）").assertDoesNotExist()
        compose.onNodeWithTag("groups-pager").performTouchInput { swipeRight() }
        compose.onNodeWithText("全部关注").assertIsDisplayed()
        compose.onNodeWithTag("groups-pager").performTouchInput { swipeRight() }
        compose.onNodeWithText("工作伙伴").assertIsDisplayed()
        compose.onNodeWithText("保存").performClick()
        compose.runOnIdle {
            assertEquals("工作伙伴", decodeGroups(model.option("saved_personal_groups_json"), "我的分组").first().title)
            assertTrue(decodeGroups(model.option("saved_default_groups_json"), "默认分组").none { it.id == "all_follow" })
            assertEquals(listOf("热门"), decodeGroups(model.option("saved_hot_groups_json"), "热门分组").map { it.title })
            model.navigate("groups")
        }
        compose.onAllNodesWithContentDescription("删除").onFirst().performClick()
        compose.onNodeWithContentDescription("返回").performClick()
        compose.runOnIdle { model.navigate("groups") }
        compose.onNodeWithText("工作伙伴").assertIsDisplayed()
    }
    @Test fun feedReselectDistinguishesSwitchSingleDoubleAndRestoresPosition() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.onNodeWithTag("feed-list").performScrollToNode(hasText("城市漫游者"))
        val before = compose.onNodeWithText("城市漫游者").fetchSemanticsNode().boundsInRoot.top
        fun settleTap() {
            compose.runOnIdle { org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(350)) }
            compose.mainClock.advanceTimeBy(600)
            compose.waitForIdle()
        }
        compose.onNodeWithText("时间线").performClick()
        settleTap()
        compose.onNodeWithText("山间来信").assertIsDisplayed()
        compose.onNodeWithText("时间线").performClick()
        settleTap()
        org.junit.Assert.assertEquals(before, compose.onNodeWithText("城市漫游者").fetchSemanticsNode().boundsInRoot.top, 2f)
        compose.runOnIdle {
            val toggles = model.feedToggleRequest
            val tops = model.feedTopRequest
            model.tapTab(0); model.tapTab(0)
            org.junit.Assert.assertEquals(toggles, model.feedToggleRequest)
            org.junit.Assert.assertEquals(tops + 1, model.feedTopRequest)
        }
        settleTap()
        compose.onNodeWithText("山间来信").assertIsDisplayed()
        compose.runOnIdle {
            val toggles = model.feedToggleRequest
            model.tapTab(0); model.tapTab(2)
            org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(350))
            org.junit.Assert.assertEquals(toggles, model.feedToggleRequest)
            model.tapTab(0)
            org.junit.Assert.assertEquals(toggles, model.feedToggleRequest)
        }
    }
    @Test fun guestFeedUsesOriginalLoginCardAndLeavesComposerReachable() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnIdle { model.changeMode(false) }
        compose.onNodeWithText("关注流需要登录").assertIsDisplayed()
        compose.onNodeWithText("登录或导入微博账号凭据后，即可同步查看你关注的好友与特别关注动态").assertIsDisplayed()
        capture("feed-guest-light")
        compose.runOnIdle { model.updateTheme(2) }
        assertNightText("关注流需要登录")
        capture("feed-guest-dark")
        compose.onNodeWithContentDescription("发微博").performClick()
        compose.onNode(hasSetTextAction()).assertExists()
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithText("去登录 / 导入凭据").performClick()
        compose.onNodeWithText("账号登录").assertIsDisplayed()
    }
    @Test fun draftAndFeedPositionSurviveNavigation() {
        ready()
        compose.onNodeWithContentDescription("发微博").performClick()
        compose.onNode(hasSetTextAction()).performTextInput("留住今天的灵感")
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithContentDescription("发微博").performClick()
        compose.onNode(hasSetTextAction()).assertTextContains("留住今天的灵感")
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithTag("feed-list").performScrollToNode(hasText("城市漫游者"))
        compose.onNodeWithText("城市漫游者").assertIsDisplayed()
        compose.onNodeWithText("设置").performClick()
        compose.onNodeWithText("时间线").performClick()
        compose.onNodeWithText("城市漫游者").assertIsDisplayed()
    }
    @Test fun pullingTheFeedShowsNewPostsBeforeThePreviousFirstPost() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        @Suppress("UNCHECKED_CAST")
        val rows = ReviewModel::class.java.getDeclaredField("feed${'$'}delegate").apply { isAccessible = true }
            .get(model) as androidx.compose.runtime.MutableState<List<Post>>
        compose.runOnIdle { rows.value = PreviewContent.posts.drop(1) }
        val list = compose.onNodeWithTag("feed-list")
        list.performTouchInput {
            swipeDown(startY = height * .25f, endY = height * .8f, durationMillis = 320)
        }
        compose.waitForIdle()
        assertEquals(PreviewContent.posts.first().id, model.feed.first().id)
        val scroll = list.fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange]
        assertEquals(0f, scroll.value(), .001f)
        compose.onNodeWithText(PreviewContent.posts.first().author).assertIsDisplayed()
    }
    @Test fun searchResultsShowCardsAboveTabsWhenFirstPageArrives() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val headerGate = java.util.concurrent.CountDownLatch(1)
        val headerRequests = java.util.concurrent.atomic.AtomicInteger()
        val client = okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            val body = when (request.url.encodedPath) {
                "/ajax/statuses/search" -> {
                    check(headerGate.await(25, java.util.concurrent.TimeUnit.SECONDS))
                    if (headerRequests.incrementAndGet() == 2) """{"ok":1}"""
                    else """{"ok":1,"topicHeads":{"topic_ori":"首屏话题卡片"}}"""
                }
                "/ajax/stopic/list" -> """{"ok":1,"data":[]}"""
                "/user" -> """<div id="pl_user_feedList"><div class="card-user-b"><a class="name" href="/u/42">首屏用户卡片</a></div></div>"""
                "/weibo" -> """<div class="card-no-result"></div>"""
                else -> error("Unexpected search request: ${request.url.encodedPath}")
            }
            okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                .body(body.toResponseBody()).build()
        }.build()
        val field = ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }
        val previous = field.get(model.repository.api)
        field.set(model.repository.api, client)
        try {
            compose.runOnIdle { model.changeMode(false); model.navigate("searchResults:test") }
            val tabs = compose.onNodeWithText("综合").assertIsDisplayed()
            compose.onNodeWithText("首屏话题卡片").assertDoesNotExist()
            headerGate.countDown()
            val header = compose.onNodeWithText("首屏话题卡片", substring = true)
            compose.waitUntil(15000) { header.isDisplayed() }
            val user = compose.onNodeWithText("首屏用户卡片").assertIsDisplayed()
            assertTrue(header.fetchSemanticsNode().boundsInRoot.top < user.fetchSemanticsNode().boundsInRoot.top)
            assertTrue(user.fetchSemanticsNode().boundsInRoot.top < tabs.fetchSemanticsNode().boundsInRoot.top)
            val list = compose.onNode(hasScrollToIndexAction() and hasAnyDescendant(hasText("首屏用户卡片")))
            repeat(2) { round ->
                list.performTouchInput {
                    swipeDown(startY = height * .25f, endY = height * .8f, durationMillis = 320)
                }
                compose.waitUntil(15000) { headerRequests.get() >= round + 2 && header.isDisplayed() == (round == 1) }
                compose.mainClock.advanceTimeBy(1500)
                compose.waitForIdle()
                val scroll = list.fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange]
                assertEquals(0f, scroll.value(), .001f)
                user.assertIsDisplayed()
            }
            assertTrue(header.fetchSemanticsNode().boundsInRoot.top < user.fetchSemanticsNode().boundsInRoot.top)
        } finally {
            headerGate.countDown()
            field.set(model.repository.api, previous)
        }
    }

    @Test fun searchInputResultsAndHistoryRemainSeparatePages() {
        ready()
        compose.onNodeWithText("热搜").performClick()
        compose.onNodeWithContentDescription("搜索").performClick()
        compose.onNodeWithText("搜索历史").assertIsDisplayed()
        compose.onNodeWithText("热门搜索").assertIsDisplayed()
        capture("search-input")
        compose.onNode(hasSetTextAction()).performTextInput("今天")
        compose.onNodeWithText("搜索", substring = false).performClick()
        compose.onNodeWithText("综合").assertIsDisplayed()
        val tab = compose.onNodeWithText("实时").assertIsDisplayed()
        val width = tab.fetchSemanticsNode().boundsInRoot.width / compose.activity.resources.displayMetrics.density
        assertTrue("Search tab width must follow label plus 28dp, got $width dp", width in 50f..64f)
        capture("search-results")
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNode(hasSetTextAction()).assertTextContains("今天")
        compose.onNodeWithContentDescription("清空").performClick()
        compose.onNodeWithText("今天").assertIsDisplayed()
        compose.onNodeWithContentDescription("清空历史").performClick()
        compose.onNodeWithText("确定要清空全部搜索历史记录吗？").assertIsDisplayed()
        compose.onNodeWithText("取消").performClick()
        compose.onNodeWithText("今天").assertIsDisplayed()
    }

    @Test fun searchResultsReceiveConfirmedPostUpdatesAndRemoveDeletedRows() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnIdle { model.navigate("searchResults:周末") }
        compose.onNodeWithText("山间来信").assertIsDisplayed()
        val post = model.feed.first().copy(author = "搜索卡片已同步")
        compose.runOnIdle { model.updatePost(post) }
        compose.onNodeWithText("搜索卡片已同步").assertIsDisplayed()
        compose.runOnIdle { model.postObservers.toList().forEach { it(post.id, null) } }
        compose.onNodeWithText("搜索卡片已同步").assertDoesNotExist()
    }

    @Test fun openingASentCommentShowsItsPreviewBeforeScanningTheThread() {
        ready()
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        compose.runOnIdle {
            model.openComment(model.feed.first(), Comment("target", "目标作者", "目标评论正文"))
        }
        compose.onNode(hasScrollToIndexAction() and hasAnyDescendant(hasContentDescription("排序方式")))
            .performScrollToNode(hasText("目标评论正文"))
        compose.onNodeWithText("目标评论正文").assertIsDisplayed()
    }
    @Test
    fun liquidGlassKeepsAccessibleNavigationAndReleaseSelection() {
        ready()
        compose.runOnUiThread { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].setOption("liquidGlass", true) }
        compose.onNodeWithText("设置").performClick()
        compose.runOnIdle { org.junit.Assert.assertEquals(2, androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].tab) }
        compose.mainClock.advanceTimeBy(350)
        compose.waitForIdle()
        capture("settings-glass-check")
        compose.onNodeWithText("偏好与功能").assertIsDisplayed()
        compose.onNodeWithText("时间线").performClick()
        compose.onNodeWithText("最新微博").assertIsDisplayed()
        capture("feed-glass")
        expectHaptic()
        compose.mainClock.autoAdvance = false
        compose.onNodeWithText("时间线").performTouchInput { down(center) }
        repeat(30) { compose.mainClock.advanceTimeByFrame(); compose.waitForIdle() }
        capture("feed-glass-pressed")
        expectHaptic()
        compose.onNodeWithText("时间线").performTouchInput {
            moveTo(center + androidx.compose.ui.geometry.Offset(width * 2f, 0f), delayMillis = 200)
        }
        compose.onNodeWithText("时间线").performTouchInput { up() }
        repeat(24) { compose.mainClock.advanceTimeByFrame(); compose.waitForIdle() }
        compose.mainClock.autoAdvance = true
        expectHaptic(-1)
        compose.onNodeWithText("偏好与功能").assertIsDisplayed()
        compose.onNodeWithText("时间线").performClick()
        expectHaptic()
        compose.mainClock.autoAdvance = false
        compose.onNodeWithText("时间线").performTouchInput {
            down(center)
            moveTo(center + androidx.compose.ui.geometry.Offset(width * 2f, 0f), delayMillis = 120)
        }
        repeat(24) { compose.mainClock.advanceTimeByFrame(); compose.waitForIdle() }
        compose.runOnIdle { org.junit.Assert.assertEquals(0, androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].tab) }
        expectHaptic(-1)
        capture("feed-glass-direct-drag")
        compose.onNodeWithText("时间线").performTouchInput { up() }
        repeat(24) { compose.mainClock.advanceTimeByFrame(); compose.waitForIdle() }
        compose.mainClock.autoAdvance = true
        expectHaptic()
        compose.runOnIdle { org.junit.Assert.assertEquals(2, androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].tab) }
        compose.onNodeWithText("偏好与功能").assertIsDisplayed()
        compose.onNodeWithText("时间线").performClick()
        compose.onNodeWithText("最新微博").assertIsDisplayed()
        compose.runOnUiThread { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].updateTheme(2) }
        capture("feed-glass-dark")
    }
    @Test fun stylePreviewStaysFixedAndWeightChangeKeepsCurrentRoute() {
        ready()
        compose.onNodeWithText("设置").performClick()
        compose.onNodeWithText("微博样式").performClick()
        compose.onNodeWithText("Caij").assertIsDisplayed()
        capture("style-preview")
        compose.onNodeWithText("正文字体大小").performScrollTo().performClick()
        compose.onNodeWithText("20 pt").performClick()
        compose.onNodeWithText("Caij").assertIsDisplayed()
        compose.onNodeWithText("确定").performClick()
        compose.onNodeWithText("个性化").performClick()
        compose.onNodeWithContentDescription("字体粗细").performScrollTo()
            .performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.SetProgress) { it(200f) }
        compose.onNodeWithText("个性化", substring = false).assertIsDisplayed()
        compose.onNodeWithTag("font-weight-label").assertTextEquals("偏粗")
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithText("关于 Review").performScrollTo().performClick()
        compose.onNodeWithText("GitHub 开源地址").assertIsDisplayed()
        capture("about")
        compose.onNodeWithText("我知道了").performClick()
    }
    @Test fun iconChoiceKeepsPreviewAndRequiresConfirmationBeforeExit() {
        ready()
        compose.runOnUiThread { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].navigate("icons") }
        compose.onNodeWithText("可选预设图标").assertIsDisplayed()
        compose.onNodeWithText("使用中").assertIsDisplayed()
        capture("icons-light")
        compose.onNodeWithText("质感经典").performClick()
        compose.onNodeWithText("应用并退出").assertIsDisplayed()
        compose.onNodeWithText("取消").performClick()
        compose.onNodeWithText("使用中").assertIsDisplayed()
        compose.onNodeWithContentDescription("返回").performClick()
        compose.runOnUiThread { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].navigate("refreshRate") }
        compose.onNodeWithText("屏幕帧率设置").assertIsDisplayed()
        compose.onNodeWithText("自动").assertIsDisplayed()
        capture("refresh-light")
        compose.onNodeWithContentDescription("返回").performClick()
        compose.runOnUiThread { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].navigate("notifications") }
        compose.onNodeWithText("私信通知").assertIsDisplayed()
        capture("notifications-light")
    }
    @Test
    fun messagesKeepFourShortcutsAndConversationTitle() {
        ready()
        compose.runOnUiThread { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].navigate("messages") }
        listOf("@我的", "收到的赞", "发出的评论", "收到的评论", "私信与群聊").forEach { compose.onNodeWithText(it).assertIsDisplayed() }
        compose.onNodeWithContentDescription("清除未读消息").assertExists()
        capture("messages-light")
        compose.runOnUiThread { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].openConversation(Contact("123", "摄影交流群", "", "", "", true, 0)) }
        compose.onNodeWithText("摄影交流群").assertIsDisplayed()
        compose.onNodeWithText("群聊会话").assertIsDisplayed()
        compose.onNodeWithText("暂无聊天消息，打个招呼吧").assertIsDisplayed()
        compose.onNodeWithContentDescription("群信息").assertExists()
        capture("chat-light")
        compose.onNode(hasSetTextAction()).performTextInput("保存聊天草稿")
        compose.onNodeWithContentDescription("返回").performClick()
        compose.runOnUiThread { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].openConversation(Contact("123", "摄影交流群", "", "", "", true, 0)) }
        compose.onNode(hasSetTextAction()).assertTextContains("保存聊天草稿")
    }
    @Test
    fun groupInfoKeepsQrBulletinAndMemberNavigation() {
        ready()
        compose.runOnUiThread {
            val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
            model.navigate("groupInfo:123456789")
            model.routeStack.last().group = org.json.JSONObject().put("name", "摄影交流群").put("summary", "记录身边的光影").put("member_count", 12).put("notice", "欢迎分享摄影作品")
        }
        compose.onNodeWithText("群成员(12/3000)").assertIsDisplayed()
        capture("group-info-light")
        compose.onNodeWithText("群二维码").performClick()
        compose.onNodeWithContentDescription("群聊二维码").assertIsDisplayed()
        capture("group-qr-light")
        compose.onNodeWithText("关闭").performClick()
        compose.onNodeWithText("群公告").performClick()
        compose.onNodeWithText("复制公告").assertIsDisplayed()
        compose.onNodeWithText("确定").performClick()
        compose.runOnUiThread { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].updateTheme(2) }
        assertNightText("欢迎分享摄影作品")
        capture("group-info-dark")
        compose.onNodeWithText("消息免打扰").performClick()
        compose.runOnIdle { assertTrue(androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].bool("mute::123456789")) }
        compose.onNodeWithText("群成员(12/3000)").performClick()
        compose.onNodeWithText("摄影交流群 (共 12 人)").assertIsDisplayed()
        compose.onNodeWithText("搜索群成员昵称或 UID...").assertIsDisplayed()
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithText("退出群聊").performClick()
        compose.onNodeWithText("确定要退出群聊 “摄影交流群” 吗？").assertIsDisplayed()
        compose.onNodeWithText("取消").performClick()
        compose.onNodeWithText("群二维码").assertIsDisplayed()
    }
    @Test
    fun topicHeaderAndScopedSearchKeepTheOriginalNavigation() {
        ready()
        compose.runOnUiThread { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].navigate("topics") }
        compose.onNodeWithText("搜索感兴趣的超话社区...").assertIsDisplayed()
        capture("topics-light")
        compose.onNodeWithText("游戏").performClick()
        compose.onNode(hasSetTextAction()).performTextInput("摄影")
        compose.onNode(hasSetTextAction()).performImeAction()
        compose.onNodeWithText("暂未找到相关超话").assertExists()
        compose.runOnUiThread {
            androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].openTopic(org.json.JSONObject().put("page_id", "100808" + "a".repeat(32)).put("title", "摄影").put("description", "记录身边的光影"))
        }
        compose.onNodeWithText("发帖").assertIsDisplayed()
        compose.onNodeWithText("签到").assertIsDisplayed()
        compose.onNodeWithText("记录身边的光影").assertIsDisplayed()
        capture("topic-detail-light")
        compose.onNodeWithContentDescription("搜索本超话").performClick()
        compose.onNodeWithText("仅搜索「摄影」内的帖子").assertIsDisplayed()
        compose.onNode(hasSetTextAction()).performTextInput("风景")
        compose.onNode(hasSetTextAction()).performImeAction()
        compose.onNodeWithText("暂无匹配帖子").assertExists()
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithText("记录身边的光影").assertIsDisplayed()
    }
    @Test
    @Config(sdk = [35], qualifiers = "zh-rCN-w840dp-h1000dp-xhdpi")
    fun wideWindowPreservesTheOriginalThreeDestinations() {
        ready()
        compose.onNodeWithText("时间线").assertIsDisplayed()
        compose.onNodeWithText("设置").performClick()
        compose.onNodeWithText("个性化").performClick()
        compose.onNodeWithText("浅色模式").performClick()
        capture("theme-wide")
    }
}
