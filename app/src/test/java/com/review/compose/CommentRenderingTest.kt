package com.review.compose

import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "zh-rCN-w412dp-h915dp-xxhdpi")
class CommentRenderingTest {
    @get:Rule val compose = createComposeRule()
    @Test fun threadPreservesPreviewWithoutRepeatingTheParentAndUsesServerCursor() {
        val parent = Comment("1", "原评论作者", "原评论内容", replies = 5, children = listOf(Comment("2", "回复者", "已有预览")))
        val merged = mergeThreadPreview(Page(listOf(Comment("3", "新回复者", "服务器新回复"), Comment("2", "回复者", "服务器更新")), "123"), parent.children)
        assertEquals(listOf("3", "2"), merged.items.map(Comment::id))
        assertEquals("服务器更新", merged.items.last().text)
        assertEquals("123", merged.next)
        val app = RuntimeEnvironment.getApplication()
        runCatching { androidx.work.WorkManager.getInstance(app) }.onFailure { androidx.work.WorkManager.initialize(app, androidx.work.Configuration.Builder().build()) }
        val model = ReviewModel(app)
        var dismissed = false
        compose.setContent { CompositionLocalProvider(LocalReview provides model) { ReviewTheme(true) {
            CommentThreadSheet(Post("p", "作者", text = "", demo = true), parent, { _, _ -> }, { dismissed = true }, {}, 0)
        } } }
        compose.onNodeWithText("共5条回复").assertIsDisplayed()
        compose.onNodeWithText("已有预览").assertIsDisplayed()
        compose.onNodeWithText("原评论内容").assertDoesNotExist()
        compose.onNodeWithText("没有更多回复").assertIsDisplayed()
        compose.onNodeWithContentDescription("刷新回复").performClick()
        compose.onNodeWithText("已有预览").assertIsDisplayed()
        compose.onNodeWithContentDescription("关闭").performClick()
        assertTrue(dismissed)
    }
    @Test fun commentKeepsAuthorBadgeTimestampChildrenAndActionsAcrossThemes() {
        val app = RuntimeEnvironment.getApplication()
        runCatching { androidx.work.WorkManager.getInstance(app) }.onFailure { androidx.work.WorkManager.initialize(app, androidx.work.Configuration.Builder().build()) }
        val model = ReviewModel(app)
        val dark = mutableStateOf(false)
        val comment = parseComment(JSONObject("""{"id":"1","user":{"id":"9","screen_name":"博主名字","verified":true,"verified_type":0},"created_at":"10分钟前","source":"北京","text_raw":"父评论正文","like_counts":12,"comments_count":5,"comments":[{"id":"2","user":{"id":"8","screen_name":"回复者"},"text_raw":"子评论正文"},{"id":"3","user":{"id":"7","screen_name":"第三位"},"text_raw":"第三条内容"},{"id":"4","user":{"id":"6","screen_name":"第四位"},"text_raw":"第四条内容"}]}"""))
        var replied = ""
        var opened = 0
        compose.setContent { CompositionLocalProvider(LocalReview provides model) { ReviewTheme(dark.value) { Surface { CommentRow(Post("p", "博主名字", uid = "9", text = ""), comment, { _, _ -> }, { replied = it.id }, { opened++ }, {}) } } } }
        compose.onNodeWithText("博主").assertIsDisplayed()
        compose.onNodeWithText("第四条内容").assertIsDisplayed()
        val time = compose.onNodeWithText("10分钟前  来自 北京", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val body = compose.onNodeWithText("父评论正文", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue(time.bottom <= body.top)
        val density = app.resources.displayMetrics.density
        assertEquals(74f * density, body.left, 1f)
        val childBody = compose.onNodeWithText("子评论正文", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertEquals((74f + 8f + 48f + 8f) * density, childBody.left, 1f)
        compose.onNodeWithText("共5条回复").performClick()
        assertEquals(1, opened)
        compose.onNodeWithText("子评论正文").performClick()
        compose.onNodeWithText("回复 @回复者").performClick()
        assertEquals("2", replied)
        compose.onNodeWithText("父评论正文").performClick()
        compose.onNodeWithText("删除评论").assertDoesNotExist()
        compose.onNodeWithText("复制评论内容").performClick()
        assertEquals("评论已复制到剪贴板", model.notice)
        compose.runOnIdle { dark.value = true }
        for (text in listOf("博主名字", "父评论正文", "10分钟前  来自 北京")) {
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(text, useUnmergedTree = true).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertTrue("Dark text: $text", layouts.single().layoutInput.style.color.luminance() > .45f)
        }
    }
}
