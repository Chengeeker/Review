package com.review.compose

import androidx.compose.ui.text.font.FontWeight
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SearchParityTest {
    @Test fun nativeSessionLoadsRankedHotCardsAndIgnoresNavigationCards() = runBlocking {
        val repository = Repository(nativeRequest = { endpoint, parameters ->
            assertEquals("cardlist", endpoint)
            assertEquals("106003type=25&t=3&disable_hot=1&filter_type=realtimehot", parameters["containerid"])
            """{"cards":[{"card_group":[
              {"desc":"体育榜","scheme":"sinaweibo://pageinfo?containerid=board"},
              {"desc":"置顶词","is_pinned":1,"scheme":"sinaweibo://searchall?q=pinned"},
              {"desc":"第一词","desc_extr":"1234","scheme":"sinaweibo://searchall?containerid=100103type%3D1%26q%3Dfirst"},
              {"desc":"第一词","scheme":"sinaweibo://searchall?q=duplicate"},
              {"desc":"第二词","scheme":"sinaweibo://searchall?q=second"}
            ]}]}"""
        })
        val items = repository.hotList("", "hot")
        assertEquals(listOf("置顶词", "第一词", "第二词"), items.map(Trend::word))
        assertEquals(listOf(0, 1, 2), items.map(Trend::rank))
        assertEquals("1234", items[1].heat)
    }

    @Test fun hotListRecoversWhenPrimaryWebApiRejectsTheRequest() = runBlocking {
        val paths = mutableListOf<String>()
        val repository = Repository()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            paths += request.url.encodedPath
            val json = if (request.url.encodedPath == "/ajax/statuses/hot_band")
                """{"ok":1,"data":{"band_list":[{"word":"备用榜","realpos":1}]}}"""
            else """{"ok":0}"""
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body(json.toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(repository.api, client)
        assertEquals("备用榜", repository.hotList("SUB=test", "hot").single().word)
        assertEquals(listOf("/ajax/side/hotSearch", "/ajax/statuses/hot_band"), paths)
    }

    @Test fun nativeProfileChecksUidAndAcceptsAnEmptyNativeTimeline() = runBlocking {
        val repository = Repository(nativeRequest = { endpoint, params ->
            assertEquals("42", params["uid"])
            when (endpoint) {
                "profile" -> """{"userInfo":{"idstr":"999","screen_name":"其他账号"}}"""
                "users/show" -> """{"idstr":"42","screen_name":"个人主页","followers_count":12}"""
                "statuses/user_timeline" -> """{"statuses":[]}"""
                else -> error("Unexpected request $endpoint")
            }
        })
        val user = repository.profile("", "42")
        assertEquals("个人主页", user.name)
        assertEquals("12", user.followers)
        assertEquals(Page<Post>(emptyList()), repository.userPosts("", "42", 1))
    }

    @Test fun hotKeywordOpensNativePostsWithoutWebCookie() = runBlocking {
        val repository = Repository(nativeRequest = { endpoint, params ->
            assertEquals("cardlist", endpoint)
            assertEquals("100103type=1&q=A%26B", params["containerid"])
            """{"data":{"cards":[{"card_group":[
              {"card_type":9,"mblog":{"idstr":"123","text":"搜索结果","user":{"idstr":"42","screen_name":"作者"}}}
            ]}]}}"""
        })
        assertEquals("123", repository.globalSearch("", "A&B", 1).items.single().id)
    }

    @Test fun directUsersUseRealFollowerThresholdAndSuggestionsIgnoreSuggestionUsers() {
        assertEquals(566000L, followerCount("56.6万"))
        assertEquals(10000L, followerCount("10,000"))
        assertEquals(120000000L, followerCount("1.2亿"))
        assertEquals(5L, followerCount("5"))
        assertEquals(0L, followerCount("未知"))
        assertEquals(listOf("猫", "猫咪"), searchWords(JSONObject("""{"data":{"users":[{"screen_name":"不能当作联想词"}],"query_relates":[{"word":"猫"},"猫咪",null,{},"猫"]}}""")))
    }
    @Test fun metadataRetainsHostImageCountsAndOfficialPin() {
        val header = parseTopicHeader(JSONObject("""{"topic_ori":"猫","object":{"summary":"<b>介绍</b>","image":{"pic_big":"http://example.com/a.jpg"}},"count":{"read":"12345678","mention":300},"claim_info":{"idstr":"42","screen_name":"主持人","verified":true,"verified_type":0},"object_attr":{"intention":{"topping_docs_topic":"123456_1"}}}"""))
        assertEquals("https://example.com/a.jpg", header.image)
        assertEquals("介绍", header.summary); assertEquals("123456", header.topId)
        assertEquals(12345678L, header.reads); assertEquals("42", header.host?.id)
        assertTrue(header.host!!.isVerified); assertEquals(0, header.host.verifiedType)
        assertEquals("1234.6万", topicCount(header.reads))
        assertEquals("1亿", topicCount(100000000))
        assertEquals("", parseTopicHeader(JSONObject("""{"object_attr":{"intention":{"topping_docs_topic":"-1"}}}""")).topId)
    }
    @Test fun tabsPreserveOfficialOrderAndOnlyApplyExistingLocalFilters() {
        val first = Post("1", "a", text = "正文", time = "Wed Nov 04 12:00:00 +0800 2026", likes = 30, shares = 20)
        val second = Post("2", "b", text = "#话题# 视频", time = "2026-11-05T05:00:00Z", likes = 60)
        val rows = listOf(first, second)
        assertEquals(rows, searchDisplayPosts(rows, "综合"))
        assertEquals(listOf(second, first), searchDisplayPosts(rows, "实时"))
        assertEquals(listOf(second, first), searchDisplayPosts(rows, "热门"))
        assertEquals(listOf(second), searchDisplayPosts(rows, "视频"))
        assertEquals(listOf(second), searchDisplayPosts(rows, "话题"))
        assertEquals(listOf(first), searchDisplayPosts(listOf(first), "视频"))
        assertEquals("#甲VS乙#", searchKeyword("甲VS乙")); assertEquals("普通关键词", searchKeyword("普通关键词"))
    }
    @Test fun weightAdjustmentPreservesHierarchyAndBounds() {
        assertEquals(300, adjustedFontWeight(FontWeight.Normal, -100).weight)
        assertEquals(600, adjustedFontWeight(FontWeight.Bold, -100).weight)
        assertEquals(700, adjustedFontWeight(FontWeight.Normal, 300).weight)
        assertEquals(900, adjustedFontWeight(FontWeight.Bold, 300).weight)
        assertEquals(100, adjustedFontWeight(FontWeight.Thin, -100).weight)
    }
}
