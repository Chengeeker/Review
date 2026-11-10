package com.review.compose

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.Before
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PagingStateTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var model: ReviewModel
    @Before fun setupModel() {
        val context = org.robolectric.RuntimeEnvironment.getApplication()
        runCatching { androidx.work.WorkManager.getInstance(context) }.onFailure { androidx.work.WorkManager.initialize(context, androidx.work.Configuration.Builder().build()) }
        model = ReviewModel(context)
    }

    @Test fun returningToAChannelKeepsRowsAndScrollWithoutRepeatingTheRequest() {
        val pages = mutableMapOf<String, PagedContentState<String>>()
        val requests = mutableMapOf<String, Int>()
        compose.setContent {
            CompositionLocalProvider(LocalReview provides model) {
            MaterialTheme {
                var channel by remember { mutableStateOf("热门") }
                Column {
                    Row { listOf("热门", "最新").forEach { name -> Button(onClick = { channel = name }) { Text(name) } } }
                    Box(Modifier.weight(1f)) {
                        val name = channel
                        PagedContent(name, { requests[name] = (requests[name] ?: 0) + 1; Page(List(40) { "$name-$it" }) }, { it }, retained = pages.getOrPut(name) { PagedContentState() }) { Text(it) }
                    }
                }
            }
            }
        }
        compose.onNode(hasScrollToIndexAction()).performScrollToIndex(20)
        compose.waitForIdle()
        val previousIndex = pages.getValue("热门").scroll.firstVisibleItemIndex
        compose.onNodeWithText("最新").performClick()
        compose.onNodeWithText("最新-0").assertIsDisplayed()
        compose.onNodeWithText("热门").performClick()
        compose.waitForIdle()
        assertEquals(previousIndex, pages.getValue("热门").scroll.firstVisibleItemIndex)
        assertEquals(mapOf("热门" to 1, "最新" to 1), requests)
    }
    @Test fun changingAndReselectingAFilterKeepsScrollAndRejectsThePreviousRequest() {
        val data = PagedContentState<String>()
        var reload by mutableIntStateOf(0)
        val requested = java.util.concurrent.CopyOnWriteArrayList<Int>()
        val blocked = kotlinx.coroutines.CompletableDeferred<Unit>()
        compose.setContent {
            CompositionLocalProvider(LocalReview provides model) {
                MaterialTheme {
                    PagedContent("comments", {
                        val generation = reload
                        requested += generation
                        if (generation == 1) blocked.await()
                        Page(List(30) { "筛选$generation-$it" })
                    }, { it }, header = {
                        item("post") { Box(Modifier.height(androidx.compose.ui.unit.Dp(1400f))) { Text("文章顶部") } }
                        item("filter") { Button(onClick = { reload++ }) { Text("筛选评论") } }
                    }, retained = data, reloadKey = reload) { Text(it) }
                }
            }
        }
        compose.onNode(hasScrollToIndexAction()).performScrollToIndex(1)
        compose.waitForIdle()
        val index = data.scroll.firstVisibleItemIndex
        val offset = data.scroll.firstVisibleItemScrollOffset
        val top = compose.onNodeWithText("筛选评论").fetchSemanticsNode().boundsInRoot.top
        compose.onNodeWithText("筛选评论").performClick()
        compose.runOnIdle {
            assertEquals(index, data.scroll.firstVisibleItemIndex)
            assertEquals(offset, data.scroll.firstVisibleItemScrollOffset)
            assertEquals(false, data.refreshing.value)
        }
        compose.onNodeWithText("筛选评论").performClick()
        compose.waitForIdle()
        assertEquals(listOf(0, 1, 2), requested.toList())
        assertEquals(top, compose.onNodeWithText("筛选评论").fetchSemanticsNode().boundsInRoot.top, .5f)
        assertEquals(index, data.scroll.firstVisibleItemIndex)
        assertEquals(offset, data.scroll.firstVisibleItemScrollOffset)
        assertEquals("筛选2-0", data.rows.value.first())
        blocked.complete(Unit)
        compose.waitForIdle()
        assertEquals("筛选2-0", data.rows.value.first())
    }
    @Test fun pullingAFirstPageShowsItsNewRowsAboveThePreviousStableKey() {
        val data = PagedContentState<String>()
        val response = kotlinx.coroutines.CompletableDeferred<Page<String>>()
        val cursors = mutableListOf<String>()
        val oldRows = List(40) { "旧内容$it" }
        compose.setContent { CompositionLocalProvider(LocalReview provides model) {
            MaterialTheme {
                PagedContent("pull", { cursor ->
                    cursors += cursor
                    if (cursors.size == 1) Page(oldRows, "next") else response.await()
                }, { it }, retained = data, loadOnScrollOnly = true) { Text(it, Modifier.height(48.dp)) }
            }
        } }
        compose.onNodeWithText("旧内容0").assertIsDisplayed()
        compose.onNode(hasScrollToIndexAction()).performTouchInput {
            swipeDown(startY = height * .25f, endY = height * .8f, durationMillis = 320)
        }
        compose.waitForIdle()
        assertEquals(listOf("0", "0"), cursors)
        response.complete(Page(listOf("新增0", "新增1") + oldRows, "next"))
        compose.waitForIdle()
        assertEquals(0, data.scroll.firstVisibleItemIndex)
        assertEquals(0, data.scroll.firstVisibleItemScrollOffset)
        compose.onNodeWithText("新增0").assertIsDisplayed()
    }
    @Test fun retryingAFailedPullRetriesTheFirstPageAndShowsItsBeginning() {
        val data = PagedContentState<String>()
        val cursors = mutableListOf<String>()
        compose.setContent { CompositionLocalProvider(LocalReview provides model) {
            MaterialTheme {
                PagedContent("retry-pull", { cursor ->
                    cursors += cursor
                    if (cursors.size == 2) error("刷新失败测试")
                    Page(List(40) { "第${cursors.size}次内容$it" }, "next")
                }, { it }, retained = data, loadOnScrollOnly = true) { Text(it, Modifier.height(48.dp)) }
            }
        } }
        compose.onNodeWithText("第1次内容0").assertIsDisplayed()
        compose.onNode(hasScrollToIndexAction()).performTouchInput {
            swipeDown(startY = height * .25f, endY = height * .8f, durationMillis = 320)
        }
        compose.waitForIdle()
        assertEquals(0, data.scroll.firstVisibleItemIndex)
        assertEquals("第1次内容0", data.rows.value.first())
        compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("重试"))
        compose.onNodeWithText("重试").performClick()
        compose.waitForIdle()
        assertEquals(listOf("0", "0", "0"), cursors)
        assertEquals(0, data.scroll.firstVisibleItemIndex)
        assertEquals(0, data.scroll.firstVisibleItemScrollOffset)
        compose.onNodeWithText("第3次内容0").assertIsDisplayed()
    }
    @Test fun hiddenRetainedChannelReceivesConfirmedUpdatesAndUnsubscribesAtPageDestruction() {
        val owner = object : androidx.lifecycle.LifecycleOwner {
            override val lifecycle = androidx.lifecycle.LifecycleRegistry(this)
        }
        val pages = mutableMapOf<String, PagedContentState<Post>>()
        val post = Post("123", "作者", text = "动态", likes = 1)
        compose.runOnUiThread { owner.lifecycle.currentState = androidx.lifecycle.Lifecycle.State.RESUMED }
        compose.setContent { CompositionLocalProvider(LocalReview provides model, androidx.lifecycle.compose.LocalLifecycleOwner provides owner) {
            var channel by remember { mutableStateOf("热门") }
            Column {
                Button(onClick = { channel = if (channel == "热门") "最新" else "热门" }) { Text("切换") }
                PagedContent(channel, { Page(listOf(post)) }, Post::id, retained = pages.getOrPut(channel) { PagedContentState() }) { Text("${it.likes} 个赞") }
            }
        } }
        compose.onNodeWithText("1 个赞").assertExists()
        compose.onNodeWithText("切换").performClick()
        compose.runOnIdle { model.updatePost(post.withInteraction("like", true)) }
        compose.onNodeWithText("2 个赞").assertExists()
        assertEquals(2, pages.getValue("热门").rows.value.single().likes)
        compose.onNodeWithText("切换").performClick()
        compose.onNodeWithText("2 个赞").assertExists()
        assertEquals(2, model.postObservers.size)
        compose.runOnUiThread { owner.lifecycle.currentState = androidx.lifecycle.Lifecycle.State.DESTROYED }
        assertEquals(0, model.postObservers.size)
    }
}
