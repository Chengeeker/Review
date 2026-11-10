package com.review.compose

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle

@Composable
fun ConversationScreen(id: String, group: Boolean, gallery: (List<Media>, Int) -> Unit) {
    val model = LocalReview.current
    val scope = rememberCoroutineScope()
    var rows by remember(id, model.uid) { mutableStateOf<List<Message>>(emptyList()) }
    var cursor by remember(id) { mutableStateOf("0") }
    var more by remember(id) { mutableStateOf(false) }
    var loading by remember(id) { mutableStateOf(false) }
    var loaded by remember(id, group, model.uid) { mutableStateOf(false) }
    var error by remember(id) { mutableStateOf<String?>(null) }
    var sending by remember(id) { mutableStateOf(false) }
    var draft by rememberSaveable(id, model.uid) { mutableStateOf(model.option("chatDraft:${model.uid}:$id")) }
    var editor by rememberSaveable(id, model.uid, stateSaver = TextFieldValue.Saver) { mutableStateOf(TextFieldValue(draft, TextRange(draft.length))) }
    var emoji by rememberSaveable(id, model.uid) { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    BackHandler(LocalPageActive.current && emoji) { emoji = false }
    LaunchedEffect(draft) { if (editor.text != draft) editor = TextFieldValue(draft, TextRange(draft.length)) }
    var sentUnconfirmed by rememberSaveable(id) { mutableStateOf(false) }
    var pendingText by rememberSaveable(id) { mutableStateOf("") }
    var pendingId by rememberSaveable(id) { mutableStateOf("") }
    var beforeIds by rememberSaveable(id) { mutableStateOf("") }
    fun updateEditor(value: TextFieldValue) {
        editor = value
        if (draft != value.text) {
            draft = value.text
            model.setOption("chatDraft:${model.uid}:$id", draft)
            if (draft != pendingText) sentUnconfirmed = false
        }
    }
    val colors = MaterialTheme.colorScheme
    val route = LocalReviewRoute.current
    val target = route?.contact
    val cookie = model.sessionCookie
    val senderProfiles = remember(id, group, model.uid) { mutableStateMapOf<String, User>() }
    val attemptedSenders = remember(id, model.uid, cookie) { mutableSetOf<String>() }
    val state = rememberLazyListState()
    var room by remember(id, group, model.uid) { mutableStateOf(route?.group?.let(::chatGroup)) }
    LaunchedEffect(id, group, model.uid, cookie) {
        if (!group || model.demo || cookie.isBlank() || room != null) return@LaunchedEffect
        try {
            val metadata = model.repository.chatGroupMetadata(cookie, id)
            route?.group = metadata
            room = chatGroup(metadata)
        } catch (e: CancellationException) { throw e } catch (_: java.io.IOException) { }
    }
    LaunchedEffect(rows, id, model.uid, cookie) {
        for (message in rows) {
            if (!message.notice && message.avatar.isNotBlank() && message.sender.isNotBlank() && senderProfiles[message.sender]?.avatar.isNullOrBlank()) {
                senderProfiles[message.sender] = User(message.sender, message.name, message.avatar,
                    isVerified = message.verified, verifiedType = message.verifiedType)
            }
        }
        if (model.demo || cookie.isBlank() || attemptedSenders.size >= 128) return@LaunchedEffect
        val missing = rows.asSequence().filterNot(Message::notice).map(Message::sender).filter { it.matches(Regex("[1-9][0-9]*")) }
            .distinct().filter { senderProfiles[it]?.avatar.isNullOrBlank() && it !in attemptedSenders &&
                (it != model.uid || model.me?.avatar.isNullOrBlank()) && (group || it != target?.id || target?.avatar.isNullOrBlank()) }
            .take(minOf(12, 128 - attemptedSenders.size)).toList()
        for (batch in missing.chunked(4)) coroutineScope {
            batch.map { sender -> async {
                val user = try { model.repository.chatUser(cookie, sender) }
                catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { null }
                attemptedSenders.add(sender)
                if (user?.id == sender && user.avatar.isNotBlank()) senderProfiles[sender] = user
            } }.awaitAll()
        }
    }
    suspend fun load(older: Boolean = false): Boolean {
        if (model.demo) return true
        if (loading) return false
        loading = true; error = null
        try {
            val page = model.repository.conversation(cookie, id, group, if (older) cursor else "0")
            val incoming = page.items.filterNot { fresh -> rows.any { it.id == fresh.id } }
            rows = (page.items + rows).distinctBy { it.id }.sortedWith(compareByDescending { it.id.toBigIntegerOrNull() })
            loaded = true
            if (sentUnconfirmed) {
                val before = beforeIds.split(',').toSet()
                val confirmed = page.items.any { msg -> (pendingId.isNotBlank() && msg.id == pendingId) || (pendingId.isBlank() && msg.id !in before && msg.sender == model.uid && msg.text == pendingText) }
                if (confirmed) { if (draft == pendingText) { draft = ""; model.setOption("chatDraft:${model.uid}:$id", "") }; sentUnconfirmed = false; pendingText = ""; pendingId = "" }
            }
            if (older || cursor == "0") { more = canContinuePage(if (older) cursor else "0", page.next, incoming.isNotEmpty()); cursor = page.next }
            return true
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) { error = e.message ?: "消息加载失败"; return false }
        finally { loading = false }
    }
    val lifecycle = LocalLifecycleOwner.current
    LaunchedEffect(id, group, model.uid, cookie, lifecycle) {
        lifecycle.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            if (!loaded || sentUnconfirmed) load()
            while (true) { delay(15000); if (!sending && error == null) load() }
        }
    }
    val end by remember { derivedStateOf { (state.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: -1) >= state.layoutInfo.totalItemsCount - 4 } }
    LaunchedEffect(end, rows.size) { if (end && more && error == null) load(true) }
    fun send() {
        if (sending || draft.isBlank() || sentUnconfirmed) return
        if (model.demo || model.uid.isBlank()) { model.navigate("account"); return }
        if (model.sessionCookie.isBlank()) { error = "发送私信需要网页会话，请导入同一账号的 Cookie"; return }
        val text = draft
        sending = true; sentUnconfirmed = true; pendingText = text; pendingId = ""; beforeIds = rows.joinToString(",") { it.id }
        scope.launch {
            try {
                pendingId = model.repository.sendMessage(model.sessionCookie, id, group, text)
                if (load() && !sentUnconfirmed) state.animateScrollToItem(0)
                else error = "服务器已接收，暂未回读到消息。请刷新核实，避免重复发送。"
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "发送结果未确认，已保留输入，请先刷新核实" }
            finally { sending = false }
        }
    }
    Column(Modifier.fillMaxSize().imePadding()) {
        if (rows.isEmpty()) Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            if (loading) CircularProgressIndicator() else Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Outlined.ChatBubbleOutline, null, Modifier.size(54.dp), tint = colors.onSurfaceVariant.copy(alpha = .35f))
                Spacer(Modifier.height(12.dp)); Text(error ?: "暂无聊天消息，打个招呼吧", fontSize = 14.sp, color = colors.onSurfaceVariant)
                if (error != null) TextButton(onClick = hapticClick { scope.launch { load() } }) { Text("重试") }
            }
        } else {
            if (error != null && sentUnconfirmed) ErrorNotice(error.orEmpty()) { scope.launch { load() } }
            LazyColumn(Modifier.weight(1f), state, reverseLayout = true, contentPadding = PaddingValues(horizontal = 14.dp, vertical = 12.dp)) {
                itemsIndexed(rows, key = { _, message -> message.id }) { index, message ->
                    Column {
                        if (showChatTime(message.time, rows.getOrNull(index + 1)?.time)) ChatTimeDivider(message.time)
                        ChatBubble(message, group, target, senderProfiles[message.sender], room, gallery)
                    }
                }
                item { Box(Modifier.fillMaxWidth().height(48.dp), contentAlignment = Alignment.Center) {
                    if (loading) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    else if (error != null) TextButton(onClick = hapticClick { scope.launch { load(true) } }) { Text("历史消息加载失败，点击重试") }
                    else if (!more) Text("已到最早消息")
                    else TextButton(onClick = hapticClick { scope.launch { load(true) } }) { Text("加载更早消息") }
                } }
            }
        }
        ReviewDivider(thickness = .5.dp)
        Row(Modifier.fillMaxWidth().background(colors.surface).padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = hapticClick {
                emoji = !emoji
                if (emoji) { focusManager.clearFocus(); keyboard?.hide() }
                else { focus.requestFocus(); keyboard?.show() }
            }) {
                Icon(if (emoji) Icons.Outlined.Keyboard else Icons.Outlined.SentimentSatisfiedAlt,
                    if (emoji) "切换键盘" else "插入表情", tint = if (emoji) colors.primary else colors.onSurfaceVariant)
            }
            BasicTextField(editor, { if (!emoji || it.text != editor.text) updateEditor(it) },
                Modifier.weight(1f).background(colors.surfaceContainerHighest.copy(alpha = .55f), RoundedCornerShape(22.dp)).padding(horizontal = 14.dp, vertical = 10.dp)
                    .focusRequester(focus).onFocusChanged { if (it.isFocused) emoji = false },
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.onSurface), cursorBrush = SolidColor(colors.primary), minLines = 1, maxLines = 4,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send), keyboardActions = KeyboardActions(onSend = { send() }),
                decorationBox = { input -> Box { if (editor.text.isEmpty()) Text("发送消息...", fontSize = 14.5.sp, color = colors.onSurfaceVariant); input() } })
            Spacer(Modifier.width(8.dp)); FilledIconButton(enabled = !sending, onClick = hapticClick(::send)) {
                if (sending) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = colors.onPrimary) else Icon(Icons.Outlined.Send, "发送", Modifier.size(20.dp))
            }
        }
        if (emoji) Surface(color = colors.surface) {
            EmojiPanel(backspace = { updateEditor(editor.erasePhrase()) }) { updateEditor(editor.insertPhrase(it)) }
        }
    }
}
