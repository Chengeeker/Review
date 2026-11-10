package com.review.compose

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "zh-rCN-w412dp-h915dp-xxhdpi")
class OverlayRenderingTest {
    @get:Rule val compose = createComposeRule()
    @Test fun genericRowsKeepFlutterTypographyAndOuterPadding() {
        compose.setContent { ReviewTheme(false) { Column {
            ReviewListItem(headlineContent = { Text("单行项目") }, modifier = Modifier.testTag("one-line"))
            ReviewListItem(headlineContent = { Text("双行项目") }, supportingContent = { Text("辅助说明") }, modifier = Modifier.testTag("two-lines"))
        } } }
        val density = org.robolectric.RuntimeEnvironment.getApplication().resources.displayMetrics.density
        assertEquals(62f * density, compose.onNodeWithTag("one-line").fetchSemanticsNode().boundsInRoot.height, 1f)
        assertEquals(78f * density, compose.onNodeWithTag("two-lines").fetchSemanticsNode().boundsInRoot.height, 1f)
        for ((label, size) in listOf("单行项目" to 15f, "辅助说明" to 12.5f)) {
            val results = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(label, useUnmergedTree = true).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
            assertEquals(size, results.single().layoutInput.style.fontSize.value, 0f)
        }
    }
    @Test fun changingFontSizeAlsoChangesInheritedLineHeightLikeFlutter() {
        compose.setContent { ReviewTheme(false) { Column { Text("小字", fontSize = 10.5.sp); Text("大字", fontSize = 21.sp) } } }
        val small = compose.onNodeWithText("小字").fetchSemanticsNode().boundsInRoot.height
        val large = compose.onNodeWithText("大字").fetchSemanticsNode().boundsInRoot.height
        assertTrue("Small labels must not inherit a fixed 20sp line box", large / small in 1.9f..2.1f)
    }
    @Test fun refreshShowsTheRealFailureAndMovesTheListBelowTheHeader() {
        val busy = mutableStateOf(false)
        val failed = mutableStateOf(false)
        var requests = 0
        compose.setContent { ReviewTheme(false) {
            ReviewRefresh(busy.value, { requests++; busy.value = true }, failed = failed.value, topInset = 0.dp) {
                LazyColumn(Modifier.fillMaxSize().testTag("refresh-list")) { items(30) { Text("行 $it", Modifier.fillMaxWidth().height(48.dp)) } }
            }
        } }
        val before = compose.onNodeWithText("行 0").fetchSemanticsNode().boundsInRoot.top
        compose.onNodeWithTag("refresh-list").performTouchInput { swipeDown() }
        compose.onNodeWithText("正在刷新...").assertIsDisplayed()
        assertEquals(1, requests)
        assertTrue(compose.onNodeWithText("行 0").fetchSemanticsNode().boundsInRoot.top > before)
        compose.runOnIdle { failed.value = true; busy.value = false }
        compose.onNodeWithText("刷新失败").assertIsDisplayed()
        compose.onNodeWithText("刷新成功").assertDoesNotExist()
        compose.mainClock.advanceTimeBy(1300)
        compose.onNodeWithText("刷新失败").assertDoesNotExist()
    }
    @Test fun repeatedToastRestartsLifetimeWithoutMovingWithPageContent() {
        val message = mutableStateOf<String?>("已复制")
        val revision = mutableIntStateOf(1)
        val page = mutableStateOf("页面一")
        compose.setContent { ReviewTheme(false) {
            Column { Text(page.value); ReviewToast(message.value, revision.intValue, false) { message.value = null } }
        } }
        compose.mainClock.autoAdvance = false
        compose.mainClock.advanceTimeBy(120)
        val position = compose.onNodeWithText("已复制").fetchSemanticsNode().boundsInWindow
        compose.runOnUiThread { page.value = "页面二" }
        compose.mainClock.advanceTimeBy(1000)
        assertEquals(position, compose.onNodeWithText("已复制").fetchSemanticsNode().boundsInWindow)
        compose.runOnUiThread { revision.intValue++ }
        compose.mainClock.advanceTimeBy(2000)
        compose.onNodeWithText("已复制").assertExists()
        compose.mainClock.advanceTimeBy(1000)
        compose.onNodeWithText("已复制").assertDoesNotExist()
    }
    @Test fun dialogUsesOriginalTitleSizeAndDismissesThroughItsButtons() {
        val shown = mutableStateOf(true)
        compose.setContent { ReviewTheme(true) {
            if (shown.value) ReviewAlertDialog({ shown.value = false }, title = { Text("确认操作") }, text = { Text("保留原来的弹窗样式") }, confirmButton = { TextButton(onClick = { shown.value = false }) { Text("确定") } })
        } }
        val text = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText("确认操作").performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(text) }
        assertEquals(18.sp, text.single().layoutInput.style.fontSize)
        compose.onNodeWithText("确定").performClick()
        compose.onNodeWithText("确认操作").assertDoesNotExist()
    }
}
