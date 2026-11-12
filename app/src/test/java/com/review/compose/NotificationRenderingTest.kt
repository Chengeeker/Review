package com.review.compose

import android.graphics.Bitmap
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.unit.dp
import org.json.JSONObject
import org.json.JSONArray
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "zh-rCN-w412dp-h915dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class NotificationRenderingTest {
    private val compose = createAndroidComposeRule<MainActivity>()
    @get:Rule val rules: RuleChain = RuleChain.outerRule(object : ExternalResource() {
        override fun before() {
            val context = RuntimeEnvironment.getApplication()
            runCatching { androidx.work.WorkManager.getInstance(context) }.onFailure {
                androidx.work.WorkManager.initialize(context, androidx.work.Configuration.Builder().build())
            }
            context.getSharedPreferences("preferences", 0).edit().clear().putBoolean("demo", true).commit()
        }
    }).around(compose)
    private fun fixture() = JSONObject("""{"idstr":"781","user":{"idstr":"123","screen_name":"山间来信"},"text_raw":"谢谢分享，周末也想去看看。","created_at":"12 分钟前","status":{"idstr":"234","text_raw":"把周末留给山野。","user":{"idstr":"123","screen_name":"山间来信"}},"reply_comment":{"idstr":"780","text_raw":"一起沿着山路走走。","user":{"screen_name":"林间微风"}}}""")

    @Test fun notificationTargetsKeepAliasesAndIdOnlyRecords() {
        for (key in listOf("status", "root_status", "rootStatus", "mblog", "weibo")) {
            assertEquals("234", notificationPost(JSONObject().put(key, fixture().getJSONObject("status")))?.id)
        }
        assertEquals("234", notificationPost(JSONObject().put("status_id", "234"))?.id)
        assertNull(notificationPost(JSONObject().put("status_id", JSONObject.NULL)))
        assertNull(notificationPost(JSONObject()))
    }

    @Test fun notificationsRenderCompactQuotesAndRequireDeleteConfirmation() {
        compose.waitUntil(15000) { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].ready }
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val row = fixture()
        val dark = mutableStateOf(false)
        val large = mutableStateOf(false)
        var removed = false
        compose.runOnUiThread {
            compose.activity.setContent {
                CompositionLocalProvider(LocalReview provides model) {
                    ReviewTheme(dark.value, scale = if (large.value) 1.4f else .95f) {
                        Surface { Column(Modifier.width(if (large.value) 320.dp else 412.dp).fillMaxHeight()) {
                            NotificationRow(row, "sentComments") { removed = true }
                        } }
                    }
                }
            }
        }
        compose.onNodeWithText("原微博：把周末留给山野。").assertIsDisplayed()
        compose.onNodeWithText("回复 @林间微风：一起沿着山路走走。").assertIsDisplayed()
        compose.onNodeWithContentDescription("更多").assertDoesNotExist()
        compose.onNodeWithText("删除").performClick()
        compose.onNodeWithText("确定要删除这条评论吗？删除后不可恢复。").assertIsDisplayed()
        assertFalse(removed)
        compose.onNodeWithText("取消").performClick()
        assertFalse(removed)
        for (night in listOf(false, true)) for (big in listOf(false, true)) {
            compose.runOnIdle { dark.value = night; large.value = big }
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText("谢谢分享，周末也想去看看。", useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertEquals(14f, layouts.single().layoutInput.style.fontSize.value, 0f)
            if (!big) {
                for ((label, top) in listOf("山间来信" to 11f, "谢谢分享，周末也想去看看。" to 51f,
                    "回复 @林间微风：一起沿着山路走走。" to 82f, "原微博：把周末留给山野。" to 117f)) {
                    // Flutter and Android round each line to physical pixels differently.
                    assertEquals(label, top, compose.onNodeWithText(label, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.top / compose.activity.resources.displayMetrics.density, 3f)
                }
            }
            compose.onNodeWithText("删除").assertIsDisplayed()
            capture("sent-${if (night) "dark" else "light"}-${if (big) "large" else "default"}").recycle()
        }
        compose.onNodeWithText("谢谢分享，周末也想去看看。").performClick()
        compose.runOnIdle { assertEquals("234", model.routeStack.last().post?.id); assertEquals("781", model.routeStack.last().initialComment?.id) }
    }

    @Test fun mentionTabsSwipeAndKeepTheirOwnRowsAndScrollPositions() {
        compose.waitUntil(15000) { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].ready }
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        (ReviewModel::class.java.getDeclaredField("cookie\$delegate").apply { isAccessible = true }.get(model) as androidx.compose.runtime.MutableState<String>).value = "SUB=fixture"
        val firstPages = java.util.concurrent.ConcurrentHashMap<String, Int>()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            val comments = request.url.encodedPath == "/ajax/comments/mentions"
            val page = request.url.queryParameter("page")
            if (page == "1") firstPages.merge(if (comments) "comments" else "statuses", 1, Int::plus)
            val rows = JSONArray()
            if (page == "1") repeat(30) { index ->
                rows.put(fixture().put("idstr", "${1000 + index}").put("text_raw", "${if (comments) "评论" else "动态"} $index"))
            }
            val body = JSONObject().put("ok", 1).put(if (comments) "comments" else "statuses", rows)
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body(body.toString().toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(model.repository.api, client)
        compose.runOnUiThread { compose.activity.setContent {
            CompositionLocalProvider(LocalReview provides model) { ReviewTheme(false) { Surface { NotificationList("mentions") { _, _ -> } } } }
        } }
        // Finish the initial page before testing a cached return; leaving sooner can cancel its load.
        compose.waitUntil(15000) { compose.onAllNodesWithText("动态 0").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("@我的评论").performClick()
        compose.waitUntil(15000) { compose.onAllNodesWithText("评论 0").fetchSemanticsNodes().isNotEmpty() }
        val vertical = hasScrollToIndexAction() and SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.VerticalScrollAxisRange)
        compose.onNode(vertical).performScrollToIndex(14)
        val before = compose.onNodeWithText("评论 14").fetchSemanticsNode().boundsInRoot.top
        compose.onNode(vertical).performTouchInput { swipeRight() }
        compose.onNodeWithText("@我的微博").assertIsSelected()
        compose.onNodeWithText("@我的评论").performClick()
        compose.onNodeWithText("评论 14").assertIsDisplayed()
        assertEquals(before, compose.onNodeWithText("评论 14").fetchSemanticsNode().boundsInRoot.top, 1f)
        assertEquals(1, firstPages["comments"])
        assertEquals(1, firstPages["statuses"])
    }

    @Test fun searchCardsKeepShadowUnderTheTranslucentFill() {
        compose.waitUntil(15000) { androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java].ready }
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val night = mutableStateOf(false)
        compose.runOnUiThread { compose.activity.setContent {
            CompositionLocalProvider(LocalReview provides model) { ReviewTheme(night.value, scale = .95f) {
                Surface { Box(Modifier.fillMaxSize()) { Box(Modifier.padding(start = 14.dp, top = 10.dp, end = 14.dp)) {
                    DirectSearchUser(User("123", "MagicOS", "", description = "记录生活", followers = "21.0万"), matched = true) {}
                } } }
            } }
        } }
        val density = compose.activity.resources.displayMetrics.density
        for (dark in listOf(false, true)) {
            compose.runOnIdle { night.value = dark }
            compose.waitForIdle()
            val bitmap = capture("search-card-${if (dark) "dark" else "light"}")
            val pixel = bitmap.getPixel((370 * density).toInt(), (25 * density).toInt())
            val expected = if (dark) android.graphics.Color.rgb(30, 31, 36) else android.graphics.Color.rgb(243, 229, 228)
            for (shift in listOf(16, 8, 0)) assertTrue(kotlin.math.abs(((expected shr shift) and 255) - ((pixel shr shift) and 255)) <= 1)
            bitmap.recycle()
        }
    }

    private fun capture(name: String): Bitmap {
        compose.waitForIdle()
        val view = compose.activity.window.decorView
        val node = android.graphics.RenderNode(name).apply { setPosition(0, 0, view.width, view.height) }
        compose.runOnUiThread { view.draw(node.beginRecording()); node.endRecording() }
        val bitmap = android.graphics.HardwareRenderer::class.java.getDeclaredMethod("createHardwareBitmap", android.graphics.RenderNode::class.java, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType)
            .invoke(null, node, view.width, view.height) as Bitmap
        val output = File("build/reports/notification-parity/$name.png").apply { parentFile?.mkdirs() }
        output.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        val pixels = bitmap.copy(Bitmap.Config.ARGB_8888, false)
        bitmap.recycle(); node.discardDisplayList()
        return pixels
    }
}
