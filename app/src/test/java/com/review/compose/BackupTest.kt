package com.review.compose

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class BackupTest {
    @Test fun unreadCountsAndMutationIdsIgnoreMissingValues() {
        val counts = interactionCounts(JSONObject("""{"mention_status":2,"like":5}"""))
        assertEquals(mapOf("mentions" to 2, "likes" to 5), counts)
        assertEquals(1, unreadAfterRead(6, 5))
        assertEquals(2, unreadAfterRead(2, 5))
        assertFalse(ApiClient.acceptedMutation(JSONObject("""{"id":null,"data":{"mid":"0"}}""")))
    }

    private fun backup() = JSONObject("""{"app":"Review","version":"2.0","backup_mode":"safe","preferences":{"theme_mode":2,"app_text_scale":0.95,"show_source":true,"search_history_list":["hello"]}}""")
    @Test fun originalSchemaAndUnknownKeysAreAccepted() {
        val data = backup(); data.getJSONObject("preferences").put("future_setting", JSONObject())
        assertEquals(2, validateBackup(data).getInt("theme_mode"))
        data.put("version", "1.0").remove("backup_mode")
        validateBackup(data)
    }
    @Test fun rejectsIncorrectTypesBeforeRestoringAnything() {
        for ((key, value) in listOf("theme_mode" to 1.5, "show_source" to "false", "search_history_list" to org.json.JSONArray("[12]"))) {
            val data = backup(); data.getJSONObject("preferences").put(key, value)
            assertThrows(IllegalArgumentException::class.java) { validateBackup(data) }
        }
    }
    @Test fun nativeSessionCannotCrossAccounts() {
        val data = backup().put("backup_mode", "full").put("native_session", """{"uid":"100"}""")
        data.getJSONObject("preferences").put("user_uid", "200")
        assertThrows(IllegalArgumentException::class.java) { validateBackup(data) }
        data.getJSONObject("preferences").put("user_uid", "100")
        validateBackup(data)
    }
    @Test fun credentialsCannotInjectHeaders() {
        val data = backup(); data.getJSONObject("preferences").put("weibo_full_cookie", "SUB=x\r\nAuthorization: secret")
        assertThrows(IllegalArgumentException::class.java) { validateBackup(data) }
    }
    @Test fun davOnlyAllowsExactLoopbackOrTlsAndSingleDirectory() {
        assertEquals("https://example.com/dav/Review/", DavConfig("example.com/dav", "a", "b", "Review").folder().toString())
        assertEquals("localhost", DavConfig("http://localhost/dav/", "a", "b", "Review").base().host)
        for (address in listOf("http://localhost.example.com/", "http://127.0.0.1.example.com/", "https://name:secret@example.com/", "https://example.com/?token=x"))
            assertThrows(IllegalArgumentException::class.java) { DavConfig(address, "a", "b", "Review").base() }
        assertThrows(IllegalArgumentException::class.java) { DavConfig("https://example.com/", "a", "b", "../elsewhere").folder() }
    }
    @Test fun unreadCountsAcceptNestedShapesAndBoundRecursion() {
        assertEquals(9, unreadCount(JSONObject("""{"data":{"mention_status":{"count":"9"}}}"""), listOf("mention_status")))
        assertEquals(0, unreadCount(JSONObject("""{"like":-3}"""), listOf("like")))
        assertNull(unreadCount(JSONObject("""{"other":1}"""), listOf("like")))
    }
}
