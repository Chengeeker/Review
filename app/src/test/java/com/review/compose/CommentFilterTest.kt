package com.review.compose

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class CommentFilterTest {
    @Test fun incompletePreviewsDoNotExcludeAuthorAndScanResumesAfterBudget() = runBlocking {
        val root = Comment("root", "Other", "question", uid = "other", replies = 99, replyCountKnown = true)
        var calls = 0
        val filter = AuthorCommentFilter("author", { Page(listOf(root)) }, { _, cursor ->
            calls++
            val number = cursor.toInt()
            if (number < 4) Page(listOf(Comment("$number", "Other", "reply", uid = "other")), "${number + 1}")
            else Page(listOf(Comment("answer", "Author", "answer", uid = "author")))
        })
        val first = filter.next()
        assertTrue(first.items.isEmpty()); assertNotEquals("0", first.next); assertEquals(3, calls)
        val second = filter.next()
        assertEquals(listOf(root), second.items); assertEquals("0", second.next); assertEquals(5, calls)
    }
    @Test fun repeatedReplyCursorStopsAndKnownEmptyRepliesNeedNoRequests() = runBlocking {
        var calls = 0
        val root = Comment("r", "Other", "", uid = "other")
        val filter = AuthorCommentFilter("author", { Page(listOf(root)) }, { _, _ -> calls++; Page(emptyList(), "0") })
        assertEquals("0", filter.next().next); assertEquals(1, calls)
        val known = AuthorCommentFilter("author", { Page(listOf(root.copy(replyCountKnown = true))) }, { _, _ -> error("Unnecessary reply fetch") })
        assertTrue(known.next().items.isEmpty())
    }
    @Test fun rootCursorDeduplicationPreventsRepeatingAnInfiniteScan() = runBlocking {
        var calls = 0
        val filter = AuthorCommentFilter("author", { calls++; Page(emptyList(), "same") }, { _, _ -> error("No roots") })
        assertEquals("0", filter.next().next); assertEquals(2, calls)
    }
}
