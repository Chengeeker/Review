package com.review.compose

import kotlinx.coroutines.ensureActive

class AuthorCommentFilter(private val author: String, private val roots: suspend (String) -> Page<Comment>, private val replies: suspend (Comment, String) -> Page<Comment>) {
    private val pending = ArrayDeque<Comment>()
    private val seen = mutableSetOf<String>()
    private val rootCursors = mutableSetOf("0")
    private val replyCursors = mutableSetOf("0")
    private var rootCursor = "0"
    private var replyCursor = "0"
    private var moreRoots = true
    private var batch = 0
    private fun containsAuthor(comment: Comment): Boolean = comment.uid == author || comment.children.any(::containsAuthor)
    private fun finishRoot() { pending.removeFirst(); replyCursor = "0"; replyCursors.clear(); replyCursors += "0" }
    suspend fun next(): Page<Comment> {
        val matches = mutableListOf<Comment>()
        var requests = 0
        while (true) {
            kotlinx.coroutines.currentCoroutineContext().ensureActive()
            if (pending.isEmpty()) {
                if (!moreRoots || requests >= 4 || matches.isNotEmpty()) break
                val page = roots(rootCursor); requests++
                moreRoots = page.next != "0" && page.next.isNotBlank() && rootCursors.add(page.next)
                rootCursor = page.next; pending.addAll(page.items.filter { seen.add(it.id) }); continue
            }
            val root = pending.first()
            if (containsAuthor(root)) { matches += root; finishRoot(); continue }
            if (root.replyCountKnown && root.replies <= root.children.size) { finishRoot(); continue }
            if (requests >= 4 || matches.isNotEmpty()) break
            val page = replies(root, replyCursor); requests++
            val found = page.items.any(::containsAuthor)
            if (found || page.next in setOf("", "0") || !replyCursors.add(page.next)) { finishRoot(); if (found) matches += root }
            else replyCursor = page.next
        }
        batch++
        return Page(matches, if (pending.isNotEmpty() || moreRoots) batch.toString() else "0")
    }
}
