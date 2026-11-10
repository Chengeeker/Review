package com.review.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

data class PollOption(val id: String, val text: String, val votes: Int, val percent: Double?, val hasCount: Boolean)
data class Poll(val id: String, val title: String, val options: List<PollOption>, val participants: Int, val creator: String,
    val end: String, val voted: Boolean, val multiple: Boolean, val ended: Boolean) {
    val hasResults get() = options.any { it.hasCount }
}
private fun JSONObject.firstString(vararg keys: String) = keys.firstNotNullOfOrNull { key -> opt(key)?.takeIf { it != JSONObject.NULL && it.toString().isNotBlank() }?.toString() }.orEmpty()
private fun JSONObject.flag(vararg keys: String) = keys.any { opt(it)?.toString() in setOf("true", "1") }
fun parsePoll(status: JSONObject, fallbackId: String = ""): Poll? {
    fun candidate(value: JSONObject, parent: JSONObject): Poll? {
        val raw = listOf("options", "vote_options", "vote_option", "vote_option_list", "option_list", "vote_list", "items").firstNotNullOfOrNull { value.optJSONArray(it) ?: (value.opt(it) as? String)?.let { json -> runCatching { JSONArray(json) }.getOrNull() } } ?: return null
        val title = value.firstString("title", "vote_title", "subject", "question", "name", "content").ifBlank { parent.firstString("content", "title", "display_name") }
        if (title.isBlank()) return null
        val options = (0 until raw.length()).mapNotNull { i ->
            val item = raw.optJSONObject(i)
            if (item == null) (raw.opt(i) as? String)?.takeIf { it.isNotBlank() }?.let { PollOption("$i", it, 0, null, false) }
            else {
                val text = item.firstString("text", "title", "name", "option", "option_text", "content")
                val countKeys = arrayOf("votes", "vote_count", "count", "num", "total", "part_num")
                val percent = item.firstString("percent", "percentage", "vote_percent", "vote_percentage", "part_ratio").toDoubleOrNull()?.let { if (it <= 1) it * 100 else it }
                if (text.isBlank()) null else PollOption(item.firstString("id", "option_id", "oid", "value").ifBlank { "$i" }, plainText(text), item.firstString(*countKeys).toIntOrNull() ?: 0, percent, countKeys.any(item::has) || percent != null)
            }
        }
        if (options.isEmpty()) return null
        val expiry = value.firstString("end_timestamp", "end_at", "expire_time", "expire_date").ifBlank { parent.firstString("expire_date") }.toLongOrNull()?.let { if (it > 100000000000L) it else it * 1000 }
        val ended = value.flag("is_ended", "ended", "is_end") || (value.has("state") && value.optInt("state") == 0) || (expiry != null && expiry <= System.currentTimeMillis())
        val description = value.firstString("end_description", "end_time_desc", "end_time_text", "expire_desc", "endtime", "end_time").ifBlank {
            if (ended) "已结束" else expiry?.let { val minutes = (it - System.currentTimeMillis()) / 60000; when { minutes >= 1440 -> "还剩${minutes / 1440}天"; minutes >= 60 -> "还剩${minutes / 60}小时"; else -> "还剩${minutes.coerceAtLeast(1)}分钟" } }.orEmpty()
        }
        return Poll(value.firstString("id", "vote_id", "poll_id").ifBlank { fallbackId }, plainText(title), options,
            value.firstString("participant_count", "participants_count", "participate_count", "vote_count", "total_count", "join_num", "total_votes", "part_info").ifBlank { parent.firstString("part_info") }.toIntOrNull() ?: 0,
            value.firstString("creator_name", "create_user_name").ifBlank { parent.firstString("user_nick") }.ifBlank { status.optJSONObject("user")?.optString("screen_name").orEmpty() },
            description, value.flag("has_voted", "voted", "is_voted", "parted") || value.optInt("parted") > 0 || raw.objects().any { it.flag("selected", "is_selected", "checked") },
            value.flag("is_multiple", "multiple", "multi_choice", "is_multi_select") || parent.flag("is_multi_select"), ended)
    }
    fun visit(value: Any?, depth: Int): Poll? {
        if (depth > 12) return null
        if (value is JSONObject) {
            for (key in listOf("vote_object", "vote_info", "voteInfo", "vote", "poll_info", "pollInfo", "poll")) value.optJSONObject(key)?.let { candidate(it, value)?.let { poll -> return poll } }
            if (value === status && fallbackId.isNotBlank()) candidate(value, value)?.let { return it }
            if (value.firstString("type", "object_type").contains(Regex("vote|poll", RegexOption.IGNORE_CASE))) candidate(value, value)?.let { return it }
            for (key in value.keys()) if (key != "retweeted_status") visit(value.opt(key), depth + 1)?.let { return it }
        } else if (value is JSONArray) for (i in 0 until value.length()) visit(value.opt(i), depth + 1)?.let { return it }
        return null
    }
    return visit(status, 0)
}

suspend fun Repository.pollResult(cookie: String, post: Post, id: String): Poll {
    for (address in listOf(ApiClient.MOBILE + "/api/statuses/show", ApiClient.DESKTOP + "/ajax/statuses/show")) {
        try { parsePoll(api.get(address, cookie, mapOf("id" to post.id)), id)?.takeIf { it.id == id && it.hasResults }?.let { return it } }
        catch (e: CancellationException) { throw e } catch (_: Exception) { }
    }
    error("暂未返回完整投票结果，请稍后重试")
}

@Composable
fun PollCard(post: Post) {
    val model = LocalReview.current
    val initial = remember(post.raw) { parsePoll(post.data) } ?: return
    var poll by remember(post.id, initial) { mutableStateOf(initial) }
    var all by remember(post.id) { mutableStateOf(false) }
    var show by remember(post.id) { mutableStateOf(false) }
    var choices by remember(post.id) { mutableStateOf(setOf<String>()) }
    var busy by remember(post.id) { mutableStateOf(false) }
    var error by remember(post.id) { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val colors = MaterialTheme.colorScheme
    fun submit(ids: Set<String>) {
        if (busy || ids.isEmpty()) return
        if (model.uid.isBlank()) { model.navigate("account"); return }
        busy = true; error = null
        scope.launch {
            try {
                require(poll.id.isNotBlank()) { "投票编号尚未加载，请先刷新" }
                val result = model.repository.api.post(ApiClient.DESKTOP + "/ajax/statuses/setVote", model.sessionCookie, mapOf("id" to poll.id, "vote_items" to ids.joinToString(","), "ext" to "4"))
                choices = emptySet()
                poll = parsePoll(result, poll.id)?.takeIf { it.hasResults } ?: model.repository.pollResult(model.sessionCookie, post, poll.id)
                show = poll.hasResults
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "投票结果未确认，请先查看结果" }
            finally { busy = false }
        }
    }
    val results = poll.hasResults && (show || poll.voted || poll.ended)
    Surface(shape = RoundedCornerShape(16.dp), color = colors.surfaceContainerHighest.copy(alpha = .55f)) {
        Column(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 10.dp)) {
            Text(poll.title, fontSize = 16.sp, lineHeight = 21.6.sp, fontWeight = reviewWeight(FontWeight.SemiBold)); Spacer(Modifier.height(10.dp))
            (if (all) poll.options else poll.options.take(3)).forEach { item ->
                val selected = item.id in choices
                val percent = item.percent ?: if (poll.options.sumOf { it.votes } > 0) item.votes * 100.0 / poll.options.sumOf { it.votes } else 0.0
                Box(Modifier.fillMaxWidth().padding(bottom = 8.dp).heightIn(min = 48.dp).border(1.dp, if (selected) colors.primary else colors.outline.copy(alpha = .8f), RoundedCornerShape(9.dp))
                    .background(if (selected) colors.primary.copy(alpha = .1f) else Color.Transparent, RoundedCornerShape(9.dp))
                    .reviewClickable(enabled = !results && !poll.voted && !poll.ended && !busy) { if (poll.multiple) choices = if (selected) choices - item.id else choices + item.id else submit(setOf(item.id)) }.padding(horizontal = 12.dp, vertical = 10.dp), contentAlignment = Alignment.Center) {
                    if (results) Box(Modifier.matchParentSize().drawBehind { drawRect(colors.primary.copy(alpha = .12f), size = Size(size.width * (percent / 100).toFloat().coerceIn(0f, 1f), size.height)) })
                    Row(verticalAlignment = Alignment.CenterVertically) { Text(item.text, Modifier.weight(1f), textAlign = TextAlign.Center, fontSize = 16.sp, color = if (results) colors.onSurface else colors.primary)
                        if (results) { Text("${item.votes}票", fontSize = 13.sp); Spacer(Modifier.width(6.dp)); Text("${percent.toInt()}%", fontSize = 13.sp, color = colors.primary) } }
                }
            }
            if (poll.multiple && !results && choices.isNotEmpty()) TextButton(onClick = hapticClick { submit(choices) }, Modifier.align(Alignment.End), enabled = !busy) { Text(if (busy) "提交中…" else "提交投票") }
            Row { if (poll.options.size > 3) TextButton(onClick = hapticClick { all = !all }) { Text(if (all) "收起" else "查看全部选项 ›") }; Spacer(Modifier.weight(1f))
                if (!poll.ended && (!poll.voted || !poll.hasResults)) TextButton(onClick = hapticClick {
                    if (show) show = false else { busy = true; scope.launch { try { poll = model.repository.pollResult(model.sessionCookie, post, poll.id); show = true; error = null } catch (e: CancellationException) { throw e } catch (e: Exception) { error = e.message } finally { busy = false } } }
                }, enabled = !busy) { Text(if (show) "返回选项" else "查看结果") }
            }
            Row { Text("${poll.participants}人参与", fontSize = 12.sp); Spacer(Modifier.width(8.dp)); Text(poll.end, fontSize = 12.sp); Spacer(Modifier.weight(1f)); if (poll.creator.isNotBlank()) Text("@${poll.creator} 创建", fontSize = 12.sp) }
            error?.let { Text(it, color = colors.error, fontSize = 12.sp) }
        }
    }
}
