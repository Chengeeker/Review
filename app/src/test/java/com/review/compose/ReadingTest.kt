package com.review.compose

import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
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
class ReadingTest {
    @Test fun layeredBirthdayCardUsesBackgroundCanvasAndOnlyBirthdayCaption() {
        val status = JSONObject("""{"idstr":"1","url_struct":[{"url_type":39,"url_title":"生日快乐"}],"page_info":{
            "page_pic":{"image_url":"https://wx1.sinaimg.cn/large/face.png","width":200,"height":800},
            "card_background_url":"https://wx1.sinaimg.cn/large/card.jpg",
            "card_info":{"pic_info":{"pic_middle":{"width":1280,"height":720}}}
        }}""")
        val media = parsePost(status).images.single()
        assertEquals(1280, media.width)
        assertEquals(720, media.height)
        assertEquals("https://wx1.sinaimg.cn/large/card.jpg", media.background)
        assertEquals("生日快乐", media.birthdayCaption())
        val merged = mergeStatusMedia(listOf(media), listOf(media.copy(background = "", width = 200, height = 800))).single()
        assertEquals(1280, merged.width)
        assertEquals("", media.copy(title = "会员荣誉").birthdayCaption())
    }

    @Test fun automaticCardPrefersOfficialForegroundAndKeepsItThroughPartialHydration() {
        val caption = "今天是我的生日09月29日，来祝福我吧~"
        val post = parsePost(JSONObject("""{"idstr":"921","text_raw":"留言 http://t.cn/birthday",
            "url_struct":[{"url_type":39,"page_id":"other","url_title":"别的卡片"},
                {"url_type":39,"page_id":"birthday","url_title":"$caption","short_url":"http://t.cn/birthday","card_image_url":"https://example.invalid/flattened.png"}],
            "page_info":{"type":"23","object_type":"webpage","page_id":"birthday","page_pic":"https://example.invalid/flattened.png",
                "card_info":{"pic_url":"https://example.invalid/foreground.png","page_info":{"pic_info":{"pic_big":{
                    "url":"https://example.invalid/background.png","width":"854","height":"480"}}}}}}"""))
        val card = post.images.single()
        assertEquals("https://example.invalid/foreground.png", card.url)
        assertEquals("https://example.invalid/background.png", card.background)
        assertEquals(854, card.width)
        assertEquals(480, card.height)
        assertEquals(caption, card.birthdayCaption())
        assertEquals("留言", post.text)
        assertEquals(card, Post.restore(post.snapshot()).images.single())
        val incomplete = card.copy(url = "https://example.invalid/flattened.png", width = 16, height = 9, background = "", title = "")
        assertEquals(card, mergeStatusMedia(post.images, listOf(incomplete)).single())
        assertEquals("", card.copy(title = "祝贺获得金牌").birthdayCaption())
    }

    @Test fun galleryZoomCyclesThroughFlutterScales() {
        assertEquals(2.5f, galleryDoubleTapScale(1f, false), 0f)
        assertEquals(3.5f, galleryDoubleTapScale(1f, true), 0f)
        assertEquals(6f, galleryDoubleTapScale(3.5f, true), 0f)
        assertEquals(1f, galleryDoubleTapScale(6f, false), 0f)
    }

    @Test fun galleryLongImageUsesFullSourceAndPhysicalScreenPlane() {
        val media = Media("https://wx1.sinaimg.cn/large/long.jpg", width = 1000, height = 5000,
            preview = "https://wx1.sinaimg.cn/bmiddle/long.jpg")
        assertEquals(media.url, media.galleryPreviewUrl())
        assertEquals("https://wx1.sinaimg.cn/orj960/long.jpg", media.copy(height = 1000).galleryPreviewUrl())
        val screen = androidx.compose.ui.geometry.Rect(0f, 140f, 1260f, 2940f)
        val full = galleryImagePlane(screen, androidx.compose.ui.geometry.Size(1000f, 5000f), crop = false)
        assertEquals(140f, full.top, .01f)
        assertEquals(2940f, full.bottom, .01f)
        assertEquals(630f, full.center.x, .01f)
    }

    @Test fun previewsUpgradeOnlyImageCdnVariantsAndKeepSignedQueriesAndAnimation() {
        assertEquals("https://wx1.sinaimg.cn/orj960/a.jpg?token=a%2Fb#part", highQualityPreviewUrl("https://wx1.sinaimg.cn/bmiddle/a.jpg?token=a%2Fb#part"))
        assertEquals("https://wx1.sinaimg.cn/orj960/a.jpg", highQualityPreviewUrl("https://wx1.sinaimg.cn/orj360/a.jpg"))
        listOf("https://wx1.sinaimg.cn/mw2000/a.jpg", "https://wx1.sinaimg.cn/large/a.jpg", "https://wx1.sinaimg.cn/thumbnail/a.gif",
            "https://wx1.sinaimg.cn.evil.test/thumbnail/a.jpg", "https://upload.api.weibo.com/2/mss/msget?fid=a", "https://user@wx1.sinaimg.cn/thumbnail/a.jpg").forEach {
            assertEquals(it, highQualityPreviewUrl(it))
        }
        val source = org.json.JSONObject("""{"large":{"url":"https://wx1.sinaimg.cn/large/a.jpg"},"bmiddle":{"url":"https://wx1.sinaimg.cn/bmiddle/a.jpg"}}""")
        assertEquals("https://wx1.sinaimg.cn/large/a.jpg", pictureMedia(source, "https://wx1.sinaimg.cn/large/a.jpg").preview)
        val long = Media(width = 1000, height = 10000)
        val size = previewDecodeSize(long, 600, 600, false)
        assertTrue(size.width >= 500)
        assertTrue(size.width.toLong() * size.height <= 3_000_000L)
        assertEquals(androidx.compose.ui.unit.IntSize(180, 180), previewDecodeSize(Media(width = 2000, height = 2000), 180, 180, false))
        assertEquals("02:05", videoTime(125000))
    }

    @Test fun galleryReturnCanReverseFromTheCurrentFrameAndWaitForHeldTouch() = runBlocking {
        val clock = androidx.compose.runtime.BroadcastFrameClock()
        val motion = GalleryOpeningMotion(kotlinx.coroutines.CoroutineScope(coroutineContext + clock), 0f)
        var closed = 0
        suspend fun frame(milliseconds: Long) {
            clock.sendFrame(milliseconds * 1_000_000)
            kotlinx.coroutines.yield()
        }
        motion.open()
        kotlinx.coroutines.yield()
        frame(0); frame(132)
        assertEquals(.4f, motion.position, .001f)
        motion.returnToSource { closed++ }
        frame(172)
        assertEquals(.2f, motion.position, .001f)
        motion.holdingGesture = true
        frame(222)
        assertEquals(0f, motion.position, .001f)
        assertEquals(0, closed)
        motion.open()
        motion.holdingGesture = false
        androidx.compose.runtime.snapshots.Snapshot.sendApplyNotifications()
        kotlinx.coroutines.yield()
        frame(240); frame(405)
        assertEquals(.5f, motion.position, .001f)
        motion.finishOpening()
        assertEquals(0, closed)
    }
    @Test fun parsesOrderedMediaAndKeepsRepostSeparate() {
        val input = JSONObject("""{
          "idstr":"1234567890123456789","text":"Hello<br>world &amp; friends",
          "user":{"id":88,"screen_name":"Reader","profile_image_url":"http://images.example/avatar.jpg"},
          "pic_ids":["b","a"],"pic_infos":{"a":{"largest":{"url":"https://images.example/a.jpg"}},"b":{"largest":{"url":"https://images.example/b.jpg"}}},
          "retweeted_status":{"id":"90","text_raw":"Quoted text","user":{"screen_name":"Other"},"pic_ids":["quote"]}
        }""")
        val post = parsePost(input)
        assertEquals("1234567890123456789", post.id)
        assertEquals("https://images.example/avatar.jpg", post.avatar)
        assertEquals(listOf("https://images.example/b.jpg", "https://images.example/a.jpg"), post.images.map { it.url })
        assertTrue(post.text.contains("world & friends"))
        assertEquals(1, post.repost!!.images.size)
        assertEquals("Quoted text", post.repost.text)
    }
    @Test fun savedContentRoundTripsIncludingMediaAndQuotedPost() {
        PreviewContent.posts.forEach { assertEquals(it, Post.restore(JSONObject(it.snapshot().toString()))) }
    }
    @Test fun paginationDeduplicatesByIdentityWithoutReordering() {
        val first = PreviewContent.posts[0]; val second = PreviewContent.posts[1]
        assertEquals(listOf(first, second), mergePosts(listOf(first), listOf(first.copy(text = "changed"), second)))
        assertEquals(listOf(first, second), mergePosts(listOf(first, second), emptyList()))
        assertTrue(canContinuePage("0", "123", true))
        assertFalse(canContinuePage("123", "123", true))
        assertFalse(canContinuePage("123", "456", false))
        listOf("0", "-1", "", "null").forEach { assertFalse(canContinuePage("123", it, true)) }
        // A refresh starts a new traversal even if its first cursor matches an earlier traversal.
        assertTrue(canContinuePage("0", "123", true))
    }
    @Test fun imageUrlsCannotOpenLocalFilesOrContainCredentials() {
        listOf("file:///sdcard/private", "javascript:alert(1)", "https://secret@example.com/image", "content://local/photo").forEach { assertEquals("", secureImage(it)) }
        assertEquals("https://example.com/image", secureImage("//example.com/image"))
    }
    @Test fun invalidCookiesAreRejectedBeforeAnyRequest() = runBlocking {
        listOf("", "SUB=ok\r\nX-Injected: true", "SUB=" + "a".repeat(32769)).forEach {
            try { Repository().importWebSession(it, null); fail("Invalid credentials accepted") } catch (_: IllegalArgumentException) { }
        }
    }
    @Test fun paddedBareSubAndLowercaseHeadersUseTheSameVerifiedCookie() = runBlocking {
        val repository = sessionRepository { request ->
            assertEquals("SUB=_2Atest==", request.header("Cookie"))
            """{"ok":1,"data":{"islogin":true,"uid":"123"}}"""
        }
        assertEquals(VerifiedWebSession("SUB=_2Atest==", false, "123"), repository.importWebSession("_2Atest==", null))
        assertEquals(VerifiedWebSession("SUB=_2Atest==", false, "123"), repository.verifyWebSession("123", "sub=_2Atest=="))
    }
    @Test fun accountVerificationRequiresAuthenticatedIdentity() {
        assertEquals("123", authenticatedUid(JSONObject("""{"data":{"login":true,"uid":"123"}}""")))
        assertEquals("456", authenticatedUid(JSONObject("""{"data":{"user":{"id":456}}}""")))
        assertNull(authenticatedUid(JSONObject("""{"data":{"login":false,"uid":"123","user":{"id":123}}}""")))
        assertNull(authenticatedUid(JSONObject("""{"uid":"123"}""")))
        assertNull(authenticatedUid(JSONObject("""{"data":{"login":true,"uid":"0"}}""")))
    }

    @Test fun nativeLoginTriesAlternateDesktopConfig() = runBlocking {
        val requests = mutableListOf<String>()
        val repository = sessionRepository { request ->
            requests += request.url.encodedPath
            if (request.url.encodedPath == "/ajax/statuses/config")
                """{"data":{"islogin":"True","user":{"uid":123}}}"""
            else """{"data":{"islogin":false}}"""
        }

        assertEquals(VerifiedWebSession("SUB=test", false, "123"), repository.verifyWebSession("123", "SUB=test"))
        assertEquals(listOf("/ajax/getSpaConfig", "/ajax/config/getconfig", "/ajax/statuses/config"), requests)
    }

    @Test fun nativeLoginVerifiesMobileOnlySessionWithMobileHeaders() = runBlocking {
        val repository = sessionRepository { request ->
            if (request.url.host == "m.weibo.cn" &&
                request.header("User-Agent")?.contains("iPhone") == true &&
                request.header("Referer") == "https://m.weibo.cn/" &&
                request.header("X-XSRF-TOKEN") == "test=token"
            ) """{"data":{"login":true,"uid":"123"}}"""
            else """{"ok":-100}"""
        }

        val cookie = "SUB=test; XSRF-TOKEN=test%3Dtoken"
        assertEquals(VerifiedWebSession(cookie, true, "123"), repository.verifyWebSession("123", cookie))
    }

    @Test fun firstCookieImportUsesVerifiedMobileAccountAfterDesktop404() = runBlocking {
        val requests = mutableListOf<String>()
        val repository = sessionRepository(status = { if (it.url.host == "weibo.com") 404 else 200 }) { request ->
            requests += request.url.encodedPath
            if (request.url.host == "m.weibo.cn") """{"ok":1,"data":{"login":true,"uid":"123"}}""" else "{}"
        }
        assertEquals(VerifiedWebSession("SUB=test", true, "123"), repository.importWebSession("SUB=test", null))
        assertEquals(listOf("/ajax/getSpaConfig", "/ajax/config/getconfig", "/ajax/statuses/config", "/api/config"), requests)
    }

    @Test fun cookieImportKeepsFirstCookieAndCanVerifyPersonalDesktopGroup() = runBlocking {
        val repository = sessionRepository { request ->
            assertEquals("SUB=first; XSRF-TOKEN=test", request.header("Cookie"))
            when (request.url.encodedPath) {
                "/ajax/feed/allGroups" -> """{"ok":1,"groups":[{"group":[{"gid":"102803"},{"gid":"11000123"}]}]}"""
                else -> """{"data":{"login":false}}"""
            }
        }
        assertEquals(VerifiedWebSession("SUB=first; XSRF-TOKEN=test", false, "123"),
            repository.importWebSession("SUB=first; sub=second; XSRF-TOKEN=test", null))
        assertTrue(runCatching { repository.importWebSession("SUB=first; XSRF-TOKEN=test", "999") }
            .exceptionOrNull() is IllegalArgumentException)
    }

    @Test fun cookieImportNeedsPrivateFeedEvidenceWhenOnlyProfileReturnsUid() = runBlocking {
        var feedAvailable = false
        val repository = sessionRepository { request ->
            when (request.url.encodedPath) {
                "/ajax/profile/detail" -> """{"ok":1,"data":{"verified_url":"https://weibo.com/verify?uid=123"}}"""
                "/ajax/feed/friendstimeline" -> if (feedAvailable) """{"statuses":[{"idstr":"1"}]}""" else """{"statuses":[]}"""
                else -> """{"data":{"login":false}}"""
            }
        }
        assertTrue(runCatching { repository.importWebSession("SUB=test", null) }.exceptionOrNull() is java.io.IOException)
        feedAvailable = true
        assertEquals(VerifiedWebSession("SUB=test", false, "123"), repository.importWebSession("SUB=test", null))
    }

    @Test fun nativeLoginRejectsDifferentAccountEvenWhenOtherEndpointsMatch() = runBlocking {
        val repository = sessionRepository { request ->
            val uid = if (request.url.encodedPath in setOf("/ajax/getSpaConfig", "/ajax/config/getconfig")) "456" else "123"
            """{"data":{"login":true,"uid":"$uid"}}"""
        }

        val failure = runCatching { repository.verifyWebSession("123", "SUB=test") }.exceptionOrNull()
        assertTrue(failure is IllegalArgumentException)
        assertFalse(repository.mobileOnly)
    }

    @Test fun nativeLoginDoesNotTrustMobileUserWithoutLoginFlag() = runBlocking {
        val repository = sessionRepository { request ->
            if (request.url.host == "m.weibo.cn") """{"data":{"user":{"id":"123"}}}"""
            else """{"ok":-100}"""
        }

        assertNull(repository.verifyWebSession("123", "SUB=test"))
        assertFalse(repository.mobileOnly)
    }

    @Test fun nativeLoginKeepsDesktopAndMobileCookiesInTheirOwnDomains() = runBlocking {
        val requests = mutableListOf<Pair<String, String?>>()
        val repository = sessionRepository { request ->
            requests += request.url.host to request.header("Cookie")
            if (request.url.host == "m.weibo.cn" && request.header("Cookie") == "SUB=mobile")
                """{"data":{"login":true,"uid":"123"}}"""
            else """{"ok":-100}"""
        }

        assertEquals(
            VerifiedWebSession("SUB=mobile", true, "123"),
            repository.verifyWebSession("123", "SUB=desktop", "SUB=desktop", "SUB=mobile")
        )
        assertEquals(
            listOf("weibo.com" to "SUB=desktop", "weibo.com" to "SUB=desktop", "weibo.com" to "SUB=desktop", "weibo.com" to "SUB=desktop", "weibo.com" to "SUB=desktop", "m.weibo.cn" to "SUB=mobile"),
            requests
        )
    }

    @Test fun absentWebCookieSkipsWebRequests() = runBlocking {
        val repository = sessionRepository { fail("No browser request without a cookie"); "{}" }
        assertNull(repository.verifyWebSession("123", ""))
    }

    @Test fun webRecoverySkipsAnotherAccountsCandidateAndUsesVerifiedMobileCookie() = runBlocking {
        val requests = mutableListOf<Pair<String, String?>>()
        val repository = sessionRepository { request ->
            val cookie = request.header("Cookie")
            requests += request.url.host to cookie
            when (cookie) {
                "SUB=wrong" -> """{"data":{"login":true,"uid":"999"}}"""
                "SUB=mobile" -> """{"data":{"login":true,"uid":"123"}}"""
                else -> """{"ok":-100}"""
            }
        }
        val credentials = mapOf("uid" to "123", "desktopCookie" to "SUB=wrong", "mobileCookie" to "SUB=mobile")
        assertEquals(VerifiedWebSession("SUB=mobile", true, "123"), repository.recoverWebSession("123", "SUB=old", false, credentials))
        assertTrue(requests.contains("weibo.com" to "SUB=wrong"))
        assertEquals(listOf("m.weibo.cn"), requests.filter { it.second == "SUB=mobile" }.map { it.first })
        requests.clear()
        assertNull(repository.recoverWebSession("456", "", false, credentials))
        assertTrue(requests.isEmpty())
    }

    @Test fun browserCookiesMustMatchBothTheDomainAndActiveAccount() = runBlocking {
        val requests = mutableListOf<Pair<String, String?>>()
        val repository = sessionRepository { request ->
            requests += request.url.host to request.header("Cookie")
            val uid = if (request.url.host == "weibo.com") "999" else "123"
            """{"ok":1,"data":{"login":true,"uid":"$uid"}}"""
        }
        val recovered = repository.recoverWebSession("123", "", false, null,
            browserDesktop = "SUB=other-account", browserMobile = "SUB=same-account")
        assertEquals(VerifiedWebSession("SUB=same-account", true, "123"), recovered)
        assertEquals(listOf("weibo.com" to "SUB=other-account", "m.weibo.cn" to "SUB=same-account"), requests)
    }

    @Test fun shortLinksResolveWithoutAccountCredentialsAndLocationsRequireAnExactId() = runBlocking {
        val api = ApiClient()
        val requests = mutableListOf<Request>()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            requests += request
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(301).message("Redirect")
                .header("Location", "http://weibo.com/p/1001018008644030000000000")
                .body("".toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(api, client)
        assertNull(api.shortLinkTarget("https://t.cn.example.com/R2WxEin"))
        assertEquals("https://weibo.com/p/1001018008644030000000000", api.shortLinkTarget("https://t.cn/R2WxEin"))
        assertNull(requests.single().header("Cookie"))

        val repository = sessionRepository { request ->
            assertEquals("/ajax/statuses/place", request.url.encodedPath)
            assertEquals("深圳市", request.url.queryParameter("q"))
            """{"ok":1,"data":{"pois":[{"poiid":"B20912345678","title":"深圳乐高乐园"},{"poiid":"8008644030000000000","title":"深圳"}]}}"""
        }
        assertEquals("深圳", repository.linkedPlace("SUB=active", "8008644030000000000", listOf("深圳市")).optString("title"))
    }

    private fun sessionRepository(status: (Request) -> Int = { 200 }, body: (Request) -> String): Repository {
        val repository = Repository()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(status(request)).message("Test response")
                .body(body(request).toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(repository.api, client)
        return repository
    }
}
