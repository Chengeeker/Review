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

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SmsSessionTest {
    private fun repository(owner: String = "123", groupProof: Boolean = true, delayFirst: Boolean = false): Repository {
        val repository = Repository(nativeRequest = { _, _ ->
            throw com.review.weiboauth.WeiboApi.ApiFailure("native_read_rejected", 200, "-105")
        }, oauthFollowingRequest = { _, _ -> error("A verified web session must serve the feed") })
        val delayed = java.util.concurrent.atomic.AtomicBoolean(delayFirst)
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            if (delayed.compareAndSet(true, false)) Thread.sleep(150)
            val request = chain.request()
            assertEquals("weibo.com", request.url.host)
            assertEquals("SUB=sms; XSRF-TOKEN=csrf", request.header("Cookie"))
            val body = when (request.url.encodedPath) {
                "/ajax/feed/allGroups" -> if (groupProof) """{"ok":1,"groups":[{"group":[{"gid":"11000$owner"}]}]}""" else """{"groups":[]}"""
                "/ajax/profile/detail" -> """{"ok":1,"data":{"uid":"$owner"}}"""
                "/ajax/feed/friendstimeline" -> {
                    check(owner == "123") { "A different account's following feed must not be probed" }
                    """{"ok":1,"statuses":[{"idstr":"42","text":"真实关注流","user":{"idstr":"99","screen_name":"关注作者"}}]}"""
                }
                else -> "{}"
            }
            val config = request.url.encodedPath.endsWith("config")
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(if (config) 404 else 200).message("Test response")
                .body(body.toResponseBody()).build()
        }.build()
        ApiClient::class.java.getDeclaredField("client").apply { isAccessible = true }.set(repository.api, client)
        return repository
    }

    @Test fun nativeSmsResponseCanReadFollowingWithoutAnotherCookieImport() = runBlocking {
        val repository = repository()
        val verified = repository.verifyWebSession("123", "SUB=sms; XSRF-TOKEN=csrf", desktopCookie = "SUB=sms; XSRF-TOKEN=csrf")
        assertEquals(VerifiedWebSession("SUB=sms; XSRF-TOKEN=csrf", false, "123"), verified)
        assertEquals("42", repository.feed(verified!!.cookie, "0", 1, ownerUid = "123").items.single().id)
    }

    @Test fun oldSmsOnlyAccountRecoversItsStoredDesktopCookieInTheBackground() = runBlocking {
        val repository = repository()
        val credentials = mapOf("uid" to "123", "desktopCookie" to "SUB=sms; XSRF-TOKEN=csrf")
        val verified = repository.recoverWebSession("123", "", false, credentials)
        assertEquals(VerifiedWebSession("SUB=sms; XSRF-TOKEN=csrf", false, "123"), verified)
        assertEquals("42", repository.feed(verified!!.cookie, "0", 1, ownerUid = "123").items.single().id)
    }

    @Test fun nativeCookieUsesTheSameNormalizationAndProfileProofAsManualImport() = runBlocking {
        val verified = repository(groupProof = false).verifyWebSession("123", "", desktopCookie = "sub=sms; SUB=stale; XSRF-TOKEN=csrf; EMPTY=")
        assertEquals(VerifiedWebSession("SUB=sms; XSRF-TOKEN=csrf", false, "123"), verified)
    }

    @Test fun anotherAccountsProfileIsRejectedBeforeReadingItsFollowingFeed() = runBlocking {
        assertTrue(runCatching {
            repository("999", groupProof = false).verifyWebSession("123", "", desktopCookie = "SUB=sms; XSRF-TOKEN=csrf")
        }.exceptionOrNull() is IllegalArgumentException)
    }

    @Test fun anotherAccountsGroupCannotCompleteSmsLoginOrRecovery() = runBlocking {
        assertTrue(runCatching {
            repository("999").verifyWebSession("123", "", desktopCookie = "SUB=sms; XSRF-TOKEN=csrf")
        }.exceptionOrNull() is IllegalArgumentException)
        assertNull(repository("999").recoverWebSession("123", "", false,
            mapOf("uid" to "123", "desktopCookie" to "SUB=sms; XSRF-TOKEN=csrf")))
    }

    @Test fun aTimedOutForegroundProbeCanRecoverFromTheSameStoredSmsSession() = runBlocking {
        val repository = repository(delayFirst = true)
        assertNull(kotlinx.coroutines.withTimeoutOrNull(30) {
            repository.verifyWebSession("123", "", desktopCookie = "SUB=sms; XSRF-TOKEN=csrf")
        })
        val verified = repository.recoverWebSession("123", "", false,
            mapOf("uid" to "123", "desktopCookie" to "SUB=sms; XSRF-TOKEN=csrf"))
        assertEquals(VerifiedWebSession("SUB=sms; XSRF-TOKEN=csrf", false, "123"), verified)
        assertEquals("42", repository.feed(verified!!.cookie, "0", 1, ownerUid = "123").items.single().id)
    }
}
