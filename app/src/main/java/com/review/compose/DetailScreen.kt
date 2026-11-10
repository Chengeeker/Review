@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.CancellationSignal
import android.view.View
import android.view.Window
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreInterceptKeyBeforeSoftKeyboard
import androidx.compose.ui.input.key.type
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.graphics.Insets
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsAnimationControlListenerCompat
import androidx.core.view.WindowInsetsAnimationControllerCompat
import androidx.core.view.WindowInsetsCompat
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume
import kotlin.math.roundToInt

@Composable
fun DetailScreen(model: ReviewModel, gallery: (List<Media>, Int) -> Unit, source: Post? = model.selected) {
    val post = source ?: return
    val active = LocalPageActive.current
    var tab by rememberSaveable(post.id) { mutableIntStateOf(1) }
    var sort by rememberSaveable(post.id) { mutableIntStateOf(0) }
    var sorting by remember { mutableStateOf(false) }
    val hot = sort == 0
    var refresh by remember(post.id) { mutableIntStateOf(0) }
    var compose by remember { mutableStateOf(false) }
    var reply by remember { mutableStateOf<Comment?>(null) }
    var parent by remember { mutableStateOf<Comment?>(null) }
    var authorFilter by remember(post.id, sort, refresh, model.uid) { mutableStateOf<AuthorCommentFilter?>(null) }
    val initialComment = LocalReviewRoute.current?.initialComment
    val commentData = remember(post.id, model.uid) {
        PagedContentState<Comment>().apply { rows.value = listOfNotNull(initialComment) }
    }
    DisposableEffect(commentData) { onDispose { commentData.stopObservingPosts?.invoke() } }
    // The frosted bar samples this page, including the background behind transparent comment rows.
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        Box(Modifier.weight(1f)) {
            val header: androidx.compose.foundation.lazy.LazyListScope.() -> Unit = {
                item("detail-post") { PostCard(post, post.favorited, {}, { model.postAction(post, "favorite") }, gallery, model::openPost, detail = true) }
                if (active && model.detailLoading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
                if (active) model.detailError?.let { item { ErrorNotice(it, model::reloadDetail) } }
                item("detail-tabs") {
                    val colors = MaterialTheme.colorScheme
                    Row(Modifier.padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        listOf("转发 ${post.shares}", "评论 ${post.comments}", "赞 ${post.likes}").forEachIndexed { i, title ->
                            if (i > 0) Spacer(Modifier.width(20.dp))
                            Column(Modifier.clip(RoundedCornerShape(16.dp)).selectable(tab == i, role = Role.Tab, onClick = hapticClick { tab = i }).padding(4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(title, fontSize = 15.sp, fontWeight = reviewWeight(if (tab == i) FontWeight.Bold else FontWeight.Normal), color = if (tab == i) colors.onSurface else colors.onSurfaceVariant)
                                Spacer(Modifier.height(4.dp))
                                val indicator by androidx.compose.animation.core.animateDpAsState(if (tab == i) 24.dp else 0.dp, androidx.compose.animation.core.tween(200), label = "detailTab")
                                Box(Modifier.size(indicator, 3.dp).background(colors.primary, RoundedCornerShape(1.5.dp)))
                            }
                        }
                        Spacer(Modifier.weight(1f))
                        if (tab == 1) Box {
                            Row(Modifier.reviewClickable { sorting = true }.padding(horizontal = 6.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Rounded.SwapVert, "排序方式", Modifier.size(16.dp), tint = colors.primary); Spacer(Modifier.width(3.dp)); Text(listOf("按热度", "按时间", "含楼主")[sort], fontSize = 12.5.sp, fontWeight = reviewWeight(FontWeight.Medium), color = colors.primary) }
                            DropdownMenu(sorting, { sorting = false }, shape = RoundedCornerShape(12.dp)) { listOf(2, 0, 1).forEach { i -> DropdownMenuItem(text = { Text(listOf("按热度", "按时间", "含楼主")[i], fontWeight = reviewWeight(if (sort == i) FontWeight.Bold else FontWeight.Normal)) }, leadingIcon = { Icon(when (i) { 0 -> Icons.Rounded.LocalFireDepartment; 1 -> Icons.Rounded.Schedule; else -> Icons.Outlined.Forum }, null, Modifier.size(18.dp), tint = if (sort == i) colors.primary else colors.onSurfaceVariant) }, onClick = hapticClick { sort = i; refresh++; sorting = false }) } }
                        }
                    }
                }
            }
            when (tab) {
                0 -> PagedContent("reposts:${post.id}:${model.uid}", { model.repository.reposts(model.sessionCookie, post.id, it.toInt().coerceAtLeast(1)) }, Post::id, header) { PostRow(it, gallery) }
                2 -> PagedContent("likers:${post.id}:${model.uid}", { model.repository.likers(model.sessionCookie, post.id, it.toInt().coerceAtLeast(1)) }, User::id, header) { UserRow(it) }
                else -> PagedContent("comments:${post.id}:${model.uid}", { cursor ->
                    val page = if (post.demo) Page(PreviewContent.comments)
                    else if (sort < 2) model.repository.commentPage(model.sessionCookie, post, cursor, hot)
                    else {
                        require(post.uid.isNotBlank()) { "尚未获得作者资料，请先重试详情" }
                        if (cursor == "0" || authorFilter == null) authorFilter = AuthorCommentFilter(post.uid, { model.repository.commentPage(model.sessionCookie, post, it, false) }, { root, next -> model.repository.commentPage(model.sessionCookie, post, next, false, root) })
                        authorFilter!!.next()
                    }
                    if (cursor == "0" && refresh == 0 && sort == 0 && initialComment != null) {
                        val official = page.items.firstOrNull { it.id == initialComment.id || it.children.any { child -> child.id == initialComment.id } }
                        page.copy(items = listOf(official ?: initialComment) + page.items.filterNot { it.id == (official ?: initialComment).id })
                    } else page
                }, Comment::id, header, retained = commentData, allowEmptyContinuation = sort >= 2, reloadKey = sort to refresh) { comment ->
                    CommentRow(post, comment, gallery, { reply = it; compose = true }, { parent = comment }, { refresh++ })
                }
            }
        }
        Surface(color = MaterialTheme.colorScheme.surface) {
            Column {
            ReviewDivider(thickness = .5.dp, color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .3f))
            Row(Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f).clip(RoundedCornerShape(24.dp)).background(MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = .5f)).reviewClickable { reply = null; compose = true }.padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Edit, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant); Spacer(Modifier.width(8.dp)); Text("发送一条友善的评论...", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Spacer(Modifier.width(8.dp))
                IconButton(onClick = hapticClick { reply = null; compose = true }) { Icon(Icons.Rounded.Send, "发表评论", tint = MaterialTheme.colorScheme.primary) }
            }
            }
        }
    }
    if (active) parent?.let { root ->
        CommentThreadSheet(post, root, gallery, { parent = null }, { reply = it; compose = true }, refresh)
    }
    if (active && compose) CommentEditor(post, reply, { compose = false }, { compose = false; refresh++; model.reloadDetail() })
}

@Composable
fun CommentEditor(post: Post, reply: Comment?, close: () -> Unit, sent: () -> Unit) {
    val model = LocalReview.current
    var text by rememberSaveable(post.id, reply?.id, stateSaver = TextFieldValue.Saver) { mutableStateOf(TextFieldValue()) }
    var emoji by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val colors = MaterialTheme.colorScheme
    val density = LocalDensity.current
    var closing by remember { mutableStateOf(false) }
    var allowSheetHide by remember { mutableStateOf(false) }
    var imeStart by remember { mutableIntStateOf(0) }
    var animatedIme by remember { mutableIntStateOf(0) }
    var visibleFraction by remember { mutableFloatStateOf(1f) }
    var sheetIme by remember { mutableStateOf<WindowInsets?>(null) }
    val opening = remember { Animatable(0f) }
    fun requestClose(): Boolean {
        if (closing || model.actionBusy) return false
        closing = true
        return true
    }
    val dismiss: () -> Unit = { requestClose() }
    val latestDismiss by rememberUpdatedState(dismiss)
    val latestClose by rememberUpdatedState(close)
    val sheet = remember(density) {
        // Open at the editor anchor so only the keyboard drives the entrance motion.
        SheetState(skipPartiallyExpanded = true, initialValue = SheetValue.Expanded,
            positionalThreshold = { with(density) { 56.dp.toPx() } }, velocityThreshold = { with(density) { 125.dp.toPx() } },
            confirmValueChange = { target ->
                if (target != SheetValue.Hidden || allowSheetHide) true
                else { latestDismiss(); false }
            })
    }
    val canDismiss = !closing && !model.actionBusy
    val scrim = BottomSheetDefaults.ScrimColor
    ModalBottomSheet(onDismissRequest = dismiss, dragHandle = null, sheetState = sheet,
        modifier = Modifier.graphicsLayer {
            // The sheet's anchored offset places it outside this layer's offscreen bounds.
            compositingStrategy = CompositingStrategy.ModulateAlpha
            alpha = opening.value * visibleFraction
            if (imeStart > 0) translationY = (sheetIme?.getBottom(density) ?: 0) - animatedIme.toFloat()
        },
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp), containerColor = colors.surface,
        scrimColor = scrim.copy(alpha = scrim.alpha * opening.value * visibleFraction), sheetGesturesEnabled = canDismiss,
        properties = ModalBottomSheetProperties(shouldDismissOnBackPress = canDismiss, shouldDismissOnClickOutside = canDismiss)) {
        val focusManager = LocalFocusManager.current
        val keyboard = LocalSoftwareKeyboardController.current
        val ime = WindowInsets.ime
        val view = LocalView.current
        val windowInfo = LocalWindowInfo.current
        val closePulse = reviewPulse()
        val window = (view.parent as? DialogWindowProvider)?.window
        SideEffect { sheetIme = ime }
        if (Build.VERSION.SDK_INT >= 33) DisposableEffect(window) {
            val dispatcher = window?.onBackInvokedDispatcher
            val callback = OnBackInvokedCallback { latestDismiss() }
            dispatcher?.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_OVERLAY, callback)
            onDispose { dispatcher?.unregisterOnBackInvokedCallback(callback) }
        }
        LaunchedEffect(closing) {
            if (!closing) {
                launch { opening.animateTo(1f, tween(160)) }
                snapshotFlow { windowInfo.isWindowFocused }.first { it }
                focus.requestFocus()
                return@LaunchedEffect
            }
            imeStart = ime.getBottom(density)
            animatedIme = imeStart
            if (imeStart == 0) {
                keyboard?.hide()
                allowSheetHide = true
                sheet.hide()
            } else {
                val controller = if (Build.VERSION.SDK_INT >= 30 && window != null) {
                    requestCommentImeControl(window, view)
                } else null
                val shown = controller?.currentInsets ?: Insets.of(0, 0, 0, imeStart)
                val hidden = controller?.hiddenStateInsets ?: Insets.NONE
                if (controller == null) keyboard?.hide()
                try {
                    Animatable(0f).animateTo(1f, tween(CommentImeDismissMillis)) {
                        visibleFraction = 1f - value
                        animatedIme = (shown.bottom + (hidden.bottom - shown.bottom) * value).roundToInt()
                        if (controller?.isReady == true) {
                            controller.setInsetsAndAlpha(
                                Insets.of(shown.left, shown.top, shown.right, animatedIme), 1f, value,
                            )
                        }
                    }
                } finally {
                    if (controller?.isReady == true) controller.finish(false)
                }
                if (controller?.isCancelled == true) keyboard?.hide()
            }
            latestClose()
        }
        Column(Modifier.fillMaxWidth().onPreInterceptKeyBeforeSoftKeyboard { event ->
            if (event.key != Key.Back) false else {
                if (event.type == KeyEventType.KeyUp && !event.nativeKeyEvent.isCanceled) requestClose()
                true
            }
        }) {
            Row(Modifier.padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(if (reply == null) "发表评论" else "回复 @${reply.author}", Modifier.weight(1f), fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.Bold))
                IconButton(onClick = { if (requestClose()) closePulse() }, enabled = canDismiss) { Icon(Icons.Outlined.Close, "关闭", Modifier.size(20.dp)) }
            }
            ReviewDivider()
            BasicTextField(text, { if (it.text.length <= 10000 && (!emoji || it.text != text.text)) text = it },
                Modifier.padding(horizontal = 16.dp, vertical = 8.dp).fillMaxWidth()
                    .background(colors.surfaceContainerHighest.copy(alpha = .3f), RoundedCornerShape(12.dp)).padding(12.dp)
                    .focusRequester(focus).onFocusChanged { if (it.isFocused) emoji = false }, minLines = 2, maxLines = 4,
                textStyle = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, color = colors.onSurface), cursorBrush = SolidColor(colors.primary),
                decorationBox = { input -> Box { if (text.text.isEmpty()) Text(if (reply == null) "写下你的友善评论..." else "回复 @${reply.author}...", fontSize = 15.sp, color = colors.onSurfaceVariant.copy(alpha = .7f)); input() } })
            Row(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(enabled = !closing, onClick = hapticClick {
                    emoji = !emoji
                    if (emoji) { focusManager.clearFocus(); keyboard?.hide() }
                    else { focus.requestFocus(); keyboard?.show() }
                }) {
                    Icon(if (emoji) Icons.Outlined.Keyboard else Icons.Outlined.SentimentSatisfiedAlt, if (emoji) "切换键盘" else "插入表情", tint = if (emoji) colors.primary else colors.onSurfaceVariant)
                }
                Spacer(Modifier.weight(1f))
                Button(onClick = hapticClick {
                    val submitted = text.text.trim()
                    if (submitted.isEmpty()) model.notice = "请输入评论内容"
                    else if (model.uid.isBlank()) { close(); model.navigate("account") }
                    else model.mutate { model.repository.writeComment(model.sessionCookie, post.id, submitted, reply?.id); sent(); model.notice = if (reply == null) "评论发表成功！" else "回复发表成功！" }
                }, enabled = !model.actionBusy && !closing, shape = RoundedCornerShape(20.dp), contentPadding = PaddingValues(horizontal = 20.dp, vertical = 10.dp)) {
                    if (model.actionBusy) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Text("发送", fontWeight = reviewWeight(FontWeight.Bold))
                }
            }
            model.actionError?.let { Text(it, Modifier.padding(horizontal = 16.dp), color = colors.error) }
            if (emoji) EmojiPanel(backspace = { text = text.erasePhrase() }) { phrase ->
                val inserted = text.insertPhrase(phrase)
                if (inserted.text.length <= 10000) text = inserted
            }
        }
    }
}

private const val CommentImeDismissMillis = 250

private suspend fun requestCommentImeControl(window: Window, view: View): WindowInsetsAnimationControllerCompat? =
    withTimeoutOrNull(180L) {
        suspendCancellableCoroutine { continuation ->
            val cancellation = CancellationSignal()
            continuation.invokeOnCancellation { cancellation.cancel() }
            WindowCompat.getInsetsController(window, view).controlWindowInsetsAnimation(
                WindowInsetsCompat.Type.ime(), CommentImeDismissMillis.toLong(), null, cancellation,
                object : WindowInsetsAnimationControlListenerCompat {
                    override fun onReady(controller: WindowInsetsAnimationControllerCompat, types: Int) {
                        if (continuation.isActive) continuation.resume(controller)
                        else if (controller.isReady) controller.finish(false)
                    }

                    override fun onFinished(controller: WindowInsetsAnimationControllerCompat) = Unit

                    override fun onCancelled(controller: WindowInsetsAnimationControllerCompat?) {
                        if (continuation.isActive) continuation.resume(null)
                    }
                },
            )
        }
    }
