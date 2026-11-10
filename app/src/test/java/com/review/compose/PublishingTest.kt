package com.review.compose

import android.location.Location
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import okhttp3.HttpUrl.Companion.toHttpUrl

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PublishingTest {
    @Test fun videoUploadCookieIsLimitedToTheControlService() = kotlinx.coroutines.runBlocking {
        val api = ApiClient()
        var requests = 0
        val client = okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            assertTrue(ApiClient.videoUploadSessionAllowed(request.url))
            assertEquals("SUB=fixture", request.header("Cookie"))
            requests++
            okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                .body(okhttp3.ResponseBody.create(null, "{}" )).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(api, client)
        for (path in listOf("init", "check")) api.raw("https://gzfileplatform.api.weibo.com/2/fileplatform/$path.json", "SUB=fixture")
        assertEquals(2, requests)
        for (url in listOf("http://gzfileplatform.api.weibo.com/2/fileplatform/init.json", "https://gzfileplatform.api.weibo.com.evil.test/2/fileplatform/init.json",
            "https://gzfileplatform.api.weibo.com/2/fileplatform/upload.json", "https://gzfileplatform.api.weibo.com/other", "https://gzfileplatform.api.weibo.com:8443/2/fileplatform/init.json",
            "https://person@gzfileplatform.api.weibo.com/2/fileplatform/init.json", "https://cdn.weibocdn.com/2/fileplatform/init.json")) {
            assertFalse(url, ApiClient.videoUploadSessionAllowed(url.toHttpUrl()))
            assertTrue(url, runCatching { api.raw(url, "SUB=fixture") }.exceptionOrNull() is IllegalArgumentException)
        }
        assertEquals(2, requests)
    }
    @Test fun commentLikeAndUnlikeUseTheOfficialObjectPayload() = kotlinx.coroutines.runBlocking {
        val repository = Repository()
        val paths = mutableListOf<String>()
        val client = okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            paths += request.url.encodedPath
            val form = request.body as okhttp3.FormBody
            val fields = (0 until form.size).associate { form.name(it) to form.value(it) }
            assertEquals(mapOf("object_id" to "123", "object_type" to "comment"), fields)
            okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                .body(okhttp3.ResponseBody.create(null, """{"ok":1}""")).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(repository.api, client)
        repository.interact("SUB=test; XSRF-TOKEN=fixture", "commentLike", "123", true)
        repository.interact("SUB=test; XSRF-TOKEN=fixture", "commentLike", "123", false)
        assertEquals(listOf("/ajax/statuses/updateLike", "/ajax/statuses/destroyLike"), paths)
    }
    @Test fun topicPickerKeepsAliasesAndSuperTopicMetadata() = kotlinx.coroutines.runBlocking {
        val repository = Repository()
        val client = okhttp3.OkHttpClient.Builder().addInterceptor { chain ->
            assertEquals("topic", chain.request().url.queryParameter("type"))
            okhttp3.Response.Builder().request(chain.request()).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                .body("""{"ok":1,"data":{"hotquery":[{"suggestion":"#摄影#","count":12},{"word":"猫[超话]","topic_id":"100808cat","discuss":"42"}],"query_relates":[{"query":"旅行"},"摄影","自然"]}}""".let { okhttp3.ResponseBody.create(null, it) }).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(repository.api, client)
        val topics = repository.picker("SUB=test", "topic", "摄")
        assertEquals(listOf("摄影", "猫", "旅行", "自然"), topics.map { it.optString("title") })
        assertEquals(12, topics[0].optInt("discuss_num"))
        assertTrue(topics[1].optBoolean("is_super_topic"))
        assertEquals("100808cat", topics[1].optString("oid"))
        assertFalse(topics[2].optBoolean("is_super_topic"))
    }
    @Test fun locationUsesPublisherKeysAndDoesNotDuplicateText() {
        val poi = normalizePlace(JSONObject("""{"id":"p1","name":"地点","longitude":"121.1","latitude":"31.2","pc_title":"地点链接"}"""))
        val fields = publishFields(contentWithPlace("正文", poi), 5, emptyList(), extras = placeFields(poi))
        assertEquals("5", fields["visible"])
        assertEquals("正文\n地点链接", fields["content"])
        assertEquals("p1", fields["poiid"]); assertEquals("地点", fields["poititle"])
        assertEquals("121.1", fields["long"]); assertEquals("31.2", fields["lat"])
        assertEquals("0", fields["spot_type"]); assertFalse(fields.containsKey("lon"))
        assertEquals("正文\n地点链接", contentWithPlace("正文\n地点链接", poi))
        assertTrue(placeFields(JSONObject().put("title", "仅名称")).isEmpty())
        assertEquals("📍 仅名称", contentWithPlace("", JSONObject().put("title", "仅名称")))
    }
    @Test fun nearbySortKeepsOfficialDistanceAndUnknownLast() {
        val location = Location("test").apply { latitude = 31.2; longitude = 121.1 }
        val items = listOf(JSONObject("""{"title":"未知"}"""), JSONObject("""{"title":"远","distance":2000}"""), JSONObject("""{"title":"近","lon":121.1,"lat":31.2}"""))
        assertEquals(listOf("近", "远", "未知"), nearbyPlaces(items, location).map { it.optString("title") })
        assertEquals(listOf("未知", "远", "近"), nearbyPlaces(items, null).map { it.optString("title") })
        assertEquals("距你 2.0 公里", placeSubtitle(nearbyPlaces(items, location)[1]))
        assertFalse(items[2].has("distance_m"))
    }
    @Test fun mediaPayloadKeepsTypeAndRejectsMixedVideo() {
        val fields = publishFields("", 0, listOf(Upload("a", "image/gif")))
        assertEquals("image/gif", org.json.JSONArray(fields.getValue("pic_id")).getJSONObject(0).getString("type"))
        assertThrows(IllegalArgumentException::class.java) { publishFields("x", 2, emptyList()) }
        assertThrows(IllegalArgumentException::class.java) { publishFields("x", 0, listOf(Upload("v", "video"), Upload("a", "image/jpeg"))) }
    }
}
