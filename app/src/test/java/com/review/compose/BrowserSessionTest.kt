package com.review.compose

import org.junit.Assert.*
import org.junit.Test

class BrowserSessionTest {
    @Test fun sessionsNeverReachForeignOrMalformedAddresses() {
        listOf("https://example.com/", "https://weibo.com.example.com/", "https://weibo.com@evil.example/", "http://weibo.com/", "file:///weibo.com").forEach {
            assertTrue(it, browserCookieWrites(it, "SUB=test", "SUB=old").isEmpty())
        }
        assertTrue(browserCookieWrites("https://weibo.com/", "SUB=test\r\nInjected: yes", "").isEmpty())
    }
    @Test fun replacementsKeepEqualsAndRemoveStaleAccountCookies() {
        val writes = browserCookieWrites("https://m.weibo.cn/page", "SUB=new==; UID=42", "SUB=old; OLD_SESSION=stale")
        assertTrue(writes.any { it.first == "https://weibo.cn/" && it.second == "SUB=new==; Domain=.weibo.cn; Path=/; Secure; HttpOnly" })
        assertTrue(writes.any { it.second == "OLD_SESSION=; Max-Age=0; Domain=.weibo.cn; Path=/; Secure; HttpOnly" })
        assertTrue(writes.none { "old" in it.second || "stale" in it.second })
        assertTrue(writes.all { it.first in setOf("https://m.weibo.cn/page", "https://weibo.cn/") })
    }
}
