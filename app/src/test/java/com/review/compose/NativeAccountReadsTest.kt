package com.review.compose

import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.IOException

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NativeAccountReadsTest {
    @Test fun bareImportedCookieCanObtainTheCurrentMutationToken() = runBlocking {
        val api = ApiClient()
        val requests = mutableListOf<String>()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            requests += request.method + " " + request.url.encodedPath
            val response = Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
            if (request.method == "GET") {
                assertEquals("/ajax/getSpaConfig", request.url.encodedPath)
                assertEquals("application/json, text/plain, */*", request.header("Accept"))
                assertEquals("SUB=fixture", request.header("Cookie"))
                response.addHeader("Set-Cookie", "XSRF-TOKEN=current; Path=/; Secure")
            } else {
                assertEquals("current", request.header("X-XSRF-TOKEN"))
                assertEquals("SUB=fixture; XSRF-TOKEN=current", request.header("Cookie"))
                assertEquals("https://weibo.com", request.header("Origin"))
            }
            response.body("""{"ok":1}""".toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(api, client)
        api.post("https://weibo.com/ajax/statuses/setLike", "SUB=fixture", mapOf("id" to "123"))
        assertEquals(listOf("GET /ajax/getSpaConfig", "POST /ajax/statuses/setLike"), requests)
    }
    @Test fun desktopUnreadUsesCurrentFirstPartyCountsAndPreservesAllMentionComments() = runBlocking {
        val repository = Repository()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            assertEquals("rm.api.weibo.com", request.url.host)
            assertEquals("/2/remind/push_count.json", request.url.encodedPath)
            assertEquals("0", request.url.queryParameter("trim_null"))
            assertNull(request.url.queryParameter("callback"))
            assertEquals("https://weibo.com/", request.header("Referer"))
            assertEquals("SUB=desktop", request.header("Cookie"))
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("""{"mention_status":2,"all_mention_cmt":9,"mention_cmt":3,"attitude":4,"cmt":5,"dm":7}""".toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(repository.api, client)
        val reminder = repository.unreadMessages("SUB=desktop", "123")
        assertEquals(mapOf("mentions" to 11, "likes" to 4, "comments" to 5), interactionCounts(reminder))
        assertEquals(27, drawerUnreadTotal(reminder, 7))
    }

    @Test fun modernSessionConfigAvoidsTheRetiredEndpointsAndRejectsGuestIdentity() = runBlocking {
        val repository = Repository()
        val requested = mutableListOf<String>()
        var loggedIn = true
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            requested += request.url.encodedPath
            val body = if (request.url.encodedPath == "/ajax/getSpaConfig")
                """{"ok":1,"data":{"uid":"123","isNormal":$loggedIn,"user":{"idstr":"123"}}}""" else "{}"
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body(body.toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(repository.api, client)
        assertEquals(VerifiedWebSession("SUB=desktop", false, "123"), repository.verifyWebSession(null, "", desktopCookie = "SUB=desktop"))
        assertEquals(listOf("/ajax/getSpaConfig"), requested)
        assertTrue(runCatching { repository.verifyWebSession("999", "", desktopCookie = "SUB=desktop") }.exceptionOrNull() is IllegalArgumentException)
        loggedIn = false
        assertNull(repository.verifyWebSession(null, "", desktopCookie = "SUB=desktop"))
    }

    @Test fun explicit403RefreshesTheSameDomainTokenOnceAndReusesIt() = runBlocking {
        val api = ApiClient()
        val cookie = "SUB=test; XSRF-TOKEN=old"
        var writes = 0
        var refreshes = 0
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            val code: Int
            val body: String
            val builder = Response.Builder().request(request).protocol(Protocol.HTTP_1_1).message("OK")
            if (request.method == "POST") {
                writes++
                val token = if (writes == 1) "old" else "new-token"
                assertEquals(token, request.header("X-XSRF-TOKEN"))
                assertTrue(request.header("Cookie").orEmpty().contains("XSRF-TOKEN=$token"))
                code = if (writes == 1) 403 else 200
                body = """{"ok":1}"""
            } else {
                refreshes++
                assertEquals("weibo.com", request.url.host)
                assertEquals("/ajax/getSpaConfig", request.url.encodedPath)
                builder.addHeader("Set-Cookie", "XSRF-TOKEN=new-token; Path=/")
                code = 200; body = "{}"
            }
            builder.code(code).body(body.toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(api, client)
        repeat(2) { api.post("https://weibo.com/ajax/statuses/setLike", cookie, mapOf("id" to "123")) }
        assertEquals(3, writes)
        assertEquals(1, refreshes)
    }

    @Test fun transportAndNon403FailuresNeverRepeatAMutation() = runBlocking {
        for (status in listOf(401, 500, 0)) {
            val api = ApiClient()
            var attempts = 0
            val client = OkHttpClient.Builder().addInterceptor { chain ->
                attempts++
                if (status == 0) throw IOException("受控传输失败")
                Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(status).message("Rejected").body("{}".toResponseBody()).build()
            }.build()
            ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(api, client)
            assertTrue(runCatching { api.post("https://weibo.com/ajax/statuses/setLike", "SUB=test; XSRF-TOKEN=old", mapOf("id" to "123")) }.isFailure)
            assertEquals(1, attempts)
        }
    }
    @Test fun groupAndPrivateSendersKeepTheirRealAvatars() {
        val group = parseMessage(org.json.JSONObject("""{"mid":"1","from_user":{"idstr":"42","screen_name":"群友","avatar":"//wx1.sinaimg.cn/one.jpg"}}"""))
        assertEquals("42", group.sender)
        assertEquals("群友", group.name)
        assertEquals("https://wx1.sinaimg.cn/one.jpg", group.avatar)
        val private = parseMessage(org.json.JSONObject("""{"mid":"2","sender_id":"43","sender":{"avatar_large":"invalid","profile_image_url":"https://wx2.sinaimg.cn/two.jpg"}}"""))
        assertEquals("https://wx2.sinaimg.cn/two.jpg", private.avatar)
    }

    @Test fun nativeRejectionCanLoadTheAuthenticatedOAuthFollowingFeed() = runBlocking {
        val repository = Repository(
            nativeRequest = { _, _ -> throw com.review.weiboauth.WeiboApi.ApiFailure("native_read_rejected", 200, "-105") },
            oauthFollowingRequest = { uid, params ->
                assertEquals("123", uid)
                assertEquals(mapOf("page" to "1", "count" to "25"), params)
                """{"statuses":[{"idstr":"500","text":"关注流"}]}"""
            }
        )
        assertEquals("500", repository.feed("", "0", 1, ownerUid = "123").items.single().id)
    }

    @Test fun oauthPermissionDenialIsNotTreatedAsAnEmptyFeed() = runBlocking {
        val repository = Repository(
            nativeRequest = { _, _ -> throw com.review.weiboauth.WeiboApi.ApiFailure("native_read_rejected", 200, "-105") },
            oauthFollowingRequest = { _, _ -> throw com.review.weiboauth.WeiboApi.ApiFailure("oauth_read_rejected", 403, "10014") }
        )
        val error = runCatching { repository.feed("", "0", 1, ownerUid = "123") }.exceptionOrNull()
        assertTrue(error?.message.orEmpty().contains("10014"))
    }

    @Test fun malformedWebFeedDoesNotMaskTheOAuthFallback() = runBlocking {
        val repository = Repository(
            nativeRequest = { _, _ -> throw com.review.weiboauth.WeiboApi.ApiFailure("native_read_rejected", 200, "-105") },
            oauthFollowingRequest = { _, _ -> """{"statuses":[{"idstr":"500","text":"关注流"}]}""" }
        )
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("""{"ok":1}""".toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(repository.api, client)
        assertEquals("500", repository.feed("SUB=test", "0", 1, ownerUid = "123").items.single().id)
    }

    @Test fun native105DoesNotTriggerAnotherNativeTimelineRequest() = runBlocking {
        var requests = 0
        val repository = Repository(nativeRequest = { _, _ ->
            requests++
            throw com.review.weiboauth.WeiboApi.ApiFailure("native_read_rejected", 200, "-105")
        })
        val error = runCatching { repository.feed("", "0", 1) }.exceptionOrNull()
        assertTrue(error?.message.orEmpty().contains("-105"))
        assertEquals(1, requests)
    }

    @Test fun followingReturnsLongPostPreviewsBeforeRequestingFullText() = runBlocking {
        val repository = Repository(nativeRequest = { _, _ ->
            """{"statuses":[{"idstr":"500","text_raw":"预览正文","isLongText":true}]}"""
        })
        val requests = mutableListOf<String>()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            requests += request.url.encodedPath
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("""{"ok":1,"data":{"longTextContent_raw":"完整正文"}}""".toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(repository.api, client)
        val post = repository.feed("SUB=preview-test", "0", 1).items.single()
        assertEquals("预览正文", post.text)
        assertTrue(post.longText)
        assertTrue(requests.isEmpty())
        assertEquals("完整正文", repository.fullText("SUB=preview-test", post.id))
        assertEquals(listOf("/ajax/statuses/longtext"), requests)
    }

    @Test fun detailKeepsAvailableFullTextWhenSupplementFails() = runBlocking {
        val repository = Repository()
        val preview = "预览正文"
        val full = "预览正文\n\n已取得的完整正文"
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            val response = when (request.url.encodedPath) {
                "/ajax/statuses/show" -> """{"idstr":"430001","text_raw":"$preview","isLongText":true}"""
                "/ajax/statuses/longtext" -> """{"ok":0,"msg":"正文补全暂不可用"}"""
                else -> error("Unexpected request ${request.url.encodedPath}")
            }
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body(response.toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(repository.api, client)
        val source = Post("430001", "作者", text = preview, longText = true,
            raw = org.json.JSONObject().put("full_text_raw", full).toString())
        assertEquals(full, repository.detail("SUB=detail-fixture", source).availableFullText())
    }

    @Test fun accountCheckRequiresTheMatchingPersonalGroup() = runBlocking {
        val repository = Repository(nativeRequest = { endpoint, _ ->
            assertEquals("groups/allgroups", endpoint)
            """{"data":{"groups":[{"group":[{"gid":"11000123"},{"gid":"102803"}]}]}}"""
        })
        assertTrue(repository.verifyNativeAccount("123"))
        assertFalse(repository.verifyNativeAccount("23"))
        assertFalse(repository.verifyNativeAccount("999"))
    }

    @Test fun followingFallsBackToRegularSignedTimelineAfterBusinessRejection() = runBlocking {
        val requests = mutableListOf<String>()
        val repository = Repository(nativeRequest = { endpoint, _ ->
            requests += endpoint
            if (endpoint == "statuses/unread_friends_timeline") """{"errno":100005}"""
            else """{"data":{"statuses":[{"idstr":"123","text":"关注流"}],"max_id":"122"}}"""
        })
        val feed = repository.feed("", "0", 1)
        assertEquals("123", feed.items.single().id)
        assertEquals("122", feed.next)
        assertEquals(listOf("statuses/unread_friends_timeline", "statuses/friends/timeline"), requests)
    }

    @Test fun htmlDoesNotAdvertiseAnAjaxRequest() = runBlocking {
        val api = ApiClient()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            assertNull(request.header("X-Requested-With"))
            assertTrue(request.header("Accept").orEmpty().startsWith("text/html"))
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("article".toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(api, client)
        assertEquals("article", api.raw("https://weibo.com/ttarticle/p/show", html = true).text)
    }

    @Test fun mobileCookieStaysInItsDomainAndUnfollowUsesTheLegacyPath() = runBlocking {
        val repository = Repository().apply { mobileOnly = true }
        val cookie = "SUB=test; XSRF-TOKEN=test-token"
        repository.api.configureSession(cookie, mobileOnly = true)
        assertEquals("", repository.api.cookieFor("https://weibo.com/", cookie))
        assertEquals(cookie, repository.api.cookieFor("https://m.weibo.cn/", cookie))
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            assertEquals("m.weibo.cn", request.url.host)
            assertEquals("/api/friendships/destory", request.url.encodedPath)
            assertEquals("$cookie; MLOGIN=1", request.header("Cookie"))
            assertTrue(request.header("User-Agent").orEmpty().contains("iPhone"))
            assertEquals("test-token", request.header("X-XSRF-TOKEN"))
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("""{"ok":1}""".toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(repository.api, client)
        assertTrue(runCatching { repository.api.raw("https://weibo.com/ajax/config/getconfig", cookie) }.exceptionOrNull() is IOException)
        assertEquals(1, repository.interact(cookie, "follow", "42", false).getInt("ok"))
    }

    @Test fun safeRestoreDoesNotReadBrokenLoginCiphertext() = runBlocking {
        val context = org.robolectric.RuntimeEnvironment.getApplication()
        val secret = context.getSharedPreferences("session", 0)
        secret.edit().putString("data", "unreadable").commit()
        val store = BackupStore(context, com.review.weiboauth.WeiboAuthManager(context))
        store.restore(org.json.JSONObject("""{"app":"Review","version":"2.0","backup_mode":"safe","preferences":{"theme_mode":2}}"""))
        assertEquals("unreadable", secret.getString("data", null))
        assertEquals(2, context.getSharedPreferences("preferences", 0).getInt("theme", 0))
    }

    @Test fun safeBackupPreservesMutedGroupsAndUnreadBaselinesWithinTheCurrentAccount() = runBlocking {
        val context = org.robolectric.RuntimeEnvironment.getApplication()
        val prefs = context.getSharedPreferences("preferences", 0)
        prefs.edit().clear().putString("uid", "42").putBoolean("mute:42:group", true)
            .putFloat("read:42:group", 5f).putFloat("read-interaction:42:likes", 8f)
            .putBoolean("mute:99:other", true).commit()
        val store = BackupStore(context, com.review.weiboauth.WeiboAuthManager(context))
        val backup = store.export(false)
        val values = backup.getJSONObject("preferences")
        assertEquals("group", values.getJSONArray("muted_message_group_ids").getString(0))
        assertEquals(5, org.json.JSONObject(values.getString("message_contact_unread_baselines_json")).getInt("group"))
        assertFalse(values.has("user_uid"))
        prefs.edit().remove("mute:42:group").remove("read:42:group").remove("read-interaction:42:likes").commit()
        store.restore(backup)
        assertTrue(prefs.getBoolean("mute:42:group", false))
        assertEquals(5f, prefs.getFloat("read:42:group", 0f))
        assertEquals(8f, prefs.getFloat("read-interaction:42:likes", 0f))
        assertTrue(prefs.getBoolean("mute:99:other", false))
    }

    @Test fun nativeOnlySessionLoadsMessagesAndEveryNotificationCategory() = runBlocking {
        val fixtures = linkedMapOf(
            "direct_messages/user_list" to """{"user_list":[{"user":{"idstr":"42","screen_name":"联系人"},"direct_message":{"text":"最近消息"},"unread_count":2}]}""",
            "direct_messages/conversation" to """{"direct_messages":[{"mid":"80","sender_id":"42","text":"较早的消息"}]}""",
            "statuses/mentions" to """{"statuses":[{"id":"1"}]}""",
            "comments/mentions" to """{"comments":[{"id":"2"}]}""",
            "like/to_me" to """{"attitudes":[{"id":"3"}]}""",
            "comments/by_me" to """{"comments":[{"id":"4"}]}""",
            "comments/to_me" to """{"comments":[{"id":"5"}]}""",
            "remind/unread_count" to """{"mention_status":2,"mention_cmt":1,"cmt":4,"dm":2}"""
        )
        val requests = mutableListOf<String>()
        val repository = Repository(nativeRequest = { endpoint, params ->
            requests += endpoint
            if (endpoint == "direct_messages/conversation") {
                assertEquals("42", params["uid"])
                assertEquals("99", params["max_id"])
            }
            fixtures.getValue(endpoint)
        })
        val contact = repository.contacts("").single()
        assertEquals("最近消息", contact.text)
        assertEquals(2, contact.unread)
        assertEquals("较早的消息", repository.conversation("", "42", false, "99").items.single().text)
        listOf("mentions", "mentionComments", "likes", "sentComments", "comments").forEachIndexed { index, kind ->
            assertEquals("${index + 1}", repository.notifications("", kind, 1).items.single().getString("id"))
        }
        assertEquals(9, drawerUnreadTotal(repository.unreadMessages("", "123"), contact.unread))
        assertEquals(fixtures.keys.toList(), requests)
    }

    @Test fun rejectedWebMessagesFallBackAndNativeRejectionsAreNotEmptySuccesses() = runBlocking {
        var nativeCalls = 0
        val repository = Repository(nativeRequest = { _, _ ->
            nativeCalls++
            if (nativeCalls == 1) """{"user_list":[]}""" else """{"errno":100005,"user_list":[]}"""
        })
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("""{"ok":0}""".toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(repository.api, client)
        assertTrue(repository.contacts("SUB=test").isEmpty())
        assertTrue(runCatching { repository.contacts("") }.exceptionOrNull() is IOException)
        assertTrue(runCatching { repository.conversation("", "1", true) }.exceptionOrNull()?.message.orEmpty().contains("群聊需要网页会话"))
        assertEquals(2, nativeCalls)
    }

    @Test fun nativeOnlySessionReadsCommentsRepostsAndFavorites() = runBlocking {
        val repository = Repository(nativeRequest = { endpoint, params ->
            when (endpoint) {
                "comments/build_comments" -> {
                    assertEquals("99", params["max_id"])
                    """{"comments":[{"id":"12","text":"评论"}],"max_id":"30"}"""
                }
                "statuses/repost_timeline" -> """{"reposts":[{"idstr":"14","text":"转发"}]}"""
                "favorites" -> """{"favorites":[{"status":{"idstr":"15","text":"收藏"}}]}"""
                else -> error("Unexpected endpoint $endpoint")
            }
        })
        val page = repository.commentPage("", Post("123", "作者", text = "正文"), "99")
        assertEquals("12", page.items.single().id)
        assertEquals("30", page.next)
        assertEquals("14", repository.reposts("", "123", 1).items.single().id)
        val saved = repository.savedPosts("", "42", 1, false).items.single()
        assertEquals("15", saved.id)
        assertTrue(saved.favorited)
    }

    @Test fun commentPagingUsesTheCurrentFlutterContractAndEndsAtInvalidCursors() = runBlocking {
        val repository = Repository(nativeRequest = { endpoint, params ->
            assertEquals("comments/build_comments", endpoint)
            assertEquals("1", params["is_reload"])
            assertEquals("0", params["is_mix"])
            assertEquals(if (params["max_id"] == "0") "10" else "20", params["count"])
            assertFalse(params.containsKey("max_id_type"))
            assertFalse(params.containsKey("type"))
            """{"data":{"comments":[{"cid":"12","text":"评论"}],"max_id":null}}"""
        })
        val post = Post("123", "作者", text = "正文")
        assertEquals("0", repository.commentPage("", post, "0").next)
        assertEquals("0", repository.commentPage("", post, "99").next)
    }
}
