package com.review.weiboauth

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NativeLoginTest {
    @Test fun oauthIdentityRequiresAnExplicitMatchingUid() {
        assertTrue(WeiboAuthManager.matchesOAuthAccount("123", JSONObject("""{"uid":123}""")))
        assertFalse(WeiboAuthManager.matchesOAuthAccount("123", JSONObject("""{"uid":"999"}""")))
        assertFalse(WeiboAuthManager.matchesOAuthAccount("123", JSONObject("""{}""")))
    }

    @Test fun oauthRenewalOnlyReplacesFreshTokenFields() {
        val original = WeiboSession.parse(JSONObject("""{
            "uid":"123","gsid":"original","cookie":"SUB=original",
            "oauth2.0":{"access_token":"old","expires":3600}
        }"""), null, 1000)
        val candidate = original.withRenewedOAuth(JSONObject("""{
            "gsid":"ignored","cookie":"SUB=ignored","oauth2.0":{"access_token":"new","expires_in":7200}
        }"""), 2000)!!
        assertEquals("123", candidate.uid)
        assertEquals("new", candidate.accessToken)
        assertEquals("7200", candidate.oauthExpires)
        assertEquals("original", candidate.gsid)
        assertEquals("SUB=original", candidate.cookie)
        listOf(
            """{"access_token":"old","expires_in":3600}""",
            """{"access_token":"new"}""",
            """{"uid":"999","access_token":"new","expires_in":3600}"""
        ).forEach { assertNull(original.withRenewedOAuth(JSONObject(it), 2000)) }
    }

    @Test fun signingConfigurationIsVisibleThroughAndroidAssets() {
        NativeRuntime.checkSigningConfig(org.robolectric.RuntimeEnvironment.getApplication())
    }

    @Test fun smsResponseAuthenticatesNativeAccountWithoutWebCookie() {
        val session = WeiboSession.parse(JSONObject("""{
            "uid":123,"gsid":"_2A-native-test","oauth2.0":{"access_token":"oauth-test","expires":3600}
        }"""), null, 1000)

        assertTrue(session.hasNativeLoginProof())
        assertNull(session.cookie)
        assertTrue(WeiboSession.fromJson(session.toJson()).hasNativeLoginProof())
    }

    @Test fun incompleteResponsesCannotProveNativeLogin() {
        listOf(
            """{"uid":"0","gsid":"native-test","oauth2.0":{"access_token":"oauth-test","expires":3600}}""",
            """{"uid":"123","oauth2.0":{"access_token":"oauth-test","expires":3600}}""",
            """{"uid":"123","gsid":"native-test","oauth2.0":{"access_token":"oauth-test","expires":0}}""",
            """{"uid":"123","gsid":"native-test","cookie":"SUB=test"}"""
        ).forEach { json ->
            assertFalse(WeiboSession.parse(JSONObject(json), null, 1000).hasNativeLoginProof())
        }
    }

    @Test fun nativeResponseRetainsBothBrowserCookieScopes() {
        val session = WeiboSession.parse(JSONObject("""{
            "uid":"123","cookie":{"uid":"123","cookie":{".weibo.com":"SUB=desktop",".weibo.cn":"SUB=mobile"}}
        }"""), null, 1000)
        val restored = WeiboSession.fromJson(session.toJson())

        assertEquals("SUB=desktop", restored.desktopCookie)
        assertEquals("SUB=mobile", restored.mobileCookie)
        assertNull(WeiboSession.fromJson(JSONObject("""{"uid":"123","cookie":"SUB=legacy"}""")).mobileCookie)
    }
}
