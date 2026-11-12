package com.review.compose

import androidx.compose.foundation.clickable
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "zh-rCN-w412dp-h915dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class RichTextHitTest {
    @get:Rule val compose = createComposeRule()

    @Test fun wrappedTopicDoesNotStealOrdinaryTextClicks() {
        val app = RuntimeEnvironment.getApplication()
        runCatching { androidx.work.WorkManager.getInstance(app) }.onFailure {
            androidx.work.WorkManager.initialize(app, androidx.work.Configuration.Builder().build())
        }
        val model = ReviewModel(app)
        val text = "第一行普通正文\n这是第二行的普通正文内容#这是跨行话题内容# 后面的普通正文"
        var opened = 0
        compose.setContent { CompositionLocalProvider(LocalReview provides model) { ReviewTheme(false) {
            Surface { Box(Modifier.width(280.dp).clickable { opened++ }) {
                RichText(text, style = TextStyle(fontSize = 16.sp, lineHeight = 20.sp))
            } }
        } } }
        val node = compose.onNodeWithText(text, useUnmergedTree = true)
        val layouts = mutableListOf<TextLayoutResult>()
        node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        val layout = layouts.single()
        val start = text.indexOf('#')
        val end = text.lastIndexOf('#')
        assertEquals(1, layout.getLineForOffset(start))
        assertEquals(2, layout.getLineForOffset(end))
        node.performTouchInput { click(layout.getBoundingBox(text.indexOf("第二行")).center) }
        assertEquals("Ordinary text on a link's first line must open its card", 1, opened)
        node.performTouchInput { click(layout.getBoundingBox(text.indexOf("后面")).center) }
        assertEquals("Ordinary text on a link's last line must open its card", 2, opened)
        node.performTouchInput { click(layout.getBoundingBox(start + 1).center) }
        assertEquals("The actual topic must not open the card", 2, opened)
        assertEquals("searchResults:${android.net.Uri.encode("#这是跨行话题内容#")}", model.screen)
        compose.runOnIdle { model.back() }
        node.performTouchInput { click(layout.getBoundingBox(end - 1).center) }
        assertEquals("searchResults:${android.net.Uri.encode("#这是跨行话题内容#")}", model.screen)
        assertEquals(2, opened)
    }

    @Test fun linksStayClickableWithoutExpandingIntoNearbyTextAtDifferentSizes() {
        val app = RuntimeEnvironment.getApplication()
        runCatching { androidx.work.WorkManager.getInstance(app) }.onFailure {
            androidx.work.WorkManager.initialize(app, androidx.work.Configuration.Builder().build())
        }
        val model = ReviewModel(app)
        val token = mutableStateOf("#话题#")
        val size = mutableStateOf(16)
        val scroll = ScrollState(0)
        var opened = 0
        compose.setContent { CompositionLocalProvider(LocalReview provides model) { ReviewTheme(true) {
            Surface { Column(Modifier.height(400.dp).verticalScroll(scroll)) {
                Box(Modifier.width(280.dp).clickable { opened++ }) {
                RichText("普通文字\n普通正文${token.value} 后面的正文", style = TextStyle(fontSize = size.value.sp, lineHeight = (size.value * 1.3f).sp))
                }
                Spacer(Modifier.height(500.dp))
            } }
        } } }
        for (font in listOf(12, 24)) for ((link, route) in listOf(
            "#这是一个比较长的跨行话题#" to "searchResults:",
            "#这是一个比较长的超话[超话]#" to "topic:",
            "@这是一个比较长的用户名称用于测试" to "profile:",
            "https://example.org/some/long/path" to "browser:"
        )) {
            compose.runOnIdle { token.value = link; size.value = font }
            val text = "普通文字\n普通正文$link 后面的正文"
            val node = compose.onNodeWithText(text, useUnmergedTree = true)
            val layouts = mutableListOf<TextLayoutResult>()
            node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            val layout = layouts.single()
            for (offset in listOf(2, text.indexOf("正文"), text.indexOf("后面"))) {
                val before = opened
                node.performTouchInput { click(layout.getBoundingBox(offset).center) }
                assertEquals("$link at $font sp: ordinary character $offset", before + 1, opened)
            }
            val range = layout.layoutInput.text.getLinkAnnotations(0, text.length).single()
            for (offset in listOf(range.start, range.end - 1)) {
                val before = opened
                node.performTouchInput { click(layout.getBoundingBox(offset).center) }
                assertEquals(before, opened)
                assertTrue("$link should open $route, got ${model.screen}", model.screen.startsWith(route))
                compose.runOnIdle { model.back() }
            }
        }
        val before = opened
        compose.onNodeWithText("普通文字\n普通正文${token.value} 后面的正文", useUnmergedTree = true)
            .performTouchInput { swipeUp() }
        assertEquals("Scrolling text must not activate the parent", before, opened)
        assertTrue(scroll.value > 0)
    }
}
