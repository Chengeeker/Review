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
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreInterceptKeyBeforeSoftKeyboard
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.platform.LocalConfiguration
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
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
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
    var commentsJump by remember(post.id) { mutableIntStateOf(0) }
    var authorFilter by remember(post.id, sort, refresh, model.uid) { mutableStateOf<AuthorCommentFilter?>(null) }
    val initialComment = LocalReviewRoute.current?.initialComment
    val commentData = remember(post.id, model.uid) {
        PagedContentState<Comment>().apply { rows.value = listOfNotNull(initialComment) }
    }
    DisposableEffect(commentData) { onDispose { commentData.stopObservingPosts?.invoke() } }
    val top = LocalContentTop.current
    val bottomBarDensity = Density(LocalDensity.current.density, LocalConfiguration.current.fontScale)
    val capsuleHeight = maxOf(44.dp, 29.dp + with(bottomBarDensity) { 10.sp.toDp() })
    val listPadding = PaddingValues(top = top, bottom = maxOf(100.dp,
        capsuleHeight + 32.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()))
    val backdrop = if (model.bool("liquidGlass")) {
        val layer = rememberGraphicsLayer()
        remember(layer) { ReviewBackdrop(layer) }
    } else null
    LaunchedEffect(commentsJump) {
        if (commentsJump > 0) commentData.scroll.animateScrollToItem(1)
    }
    // The frosted bar samples this page, including the background behind transparent comment rows.
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().then(if (backdrop != null) Modifier.recordBackdrop(backdrop) else Modifier)
            .background(MaterialTheme.colorScheme.background)) {
            val header: androidx.compose.foundation.lazy.LazyListScope.() -> Unit = {
                item("detail-post") {
                    Column {
                        PostCard(post, post.favorited, {}, { model.postAction(post, "favorite") }, gallery, model::openPost, detail = true)
                        if (active && model.detailLoading) LinearProgressIndicator(Modifier.fillMaxWidth())
                        if (active) model.detailError?.let { ErrorNotice(it, model::reloadDetail) }
                    }
                }
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
                0 -> PagedContent("reposts:${post.id}:${model.uid}", { model.repository.reposts(model.sessionCookie, post.id, it.toInt().coerceAtLeast(1)) }, Post::id, header, contentPadding = listPadding) { PostRow(it, gallery) }
                2 -> PagedContent("likers:${post.id}:${model.uid}", { model.repository.likers(model.sessionCookie, post.id, it.toInt().coerceAtLeast(1)) }, User::id, header, contentPadding = listPadding) { UserRow(it) }
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
                }, Comment::id, header, retained = commentData, contentPadding = listPadding, allowEmptyContinuation = sort >= 2, reloadKey = sort to refresh) { comment ->
                    CommentRow(post, comment, gallery, { reply = it; compose = true }, { parent = comment }, { refresh++ })
                }
            }
        }
        CompositionLocalProvider(LocalBackdrop provides backdrop, LocalDensity provides bottomBarDensity) {
            DetailBottomBar(post, capsuleHeight, Modifier.align(Alignment.BottomCenter), model.actionBusy,
                onWrite = { reply = null; compose = true }, onLike = { model.postAction(post, "like") },
                onRepost = { model.openRepostDraft(post) }, onComments = { tab = 1; commentsJump++ })
        }
    }
    if (active) parent?.let { root ->
        CommentThreadSheet(post, root, gallery, { parent = null }, { reply = it; compose = true }, refresh)
    }
    if (active && compose) CommentEditor(post, reply, { compose = false }, { compose = false; refresh++; model.reloadDetail() })
}

@Composable
private fun DetailBottomBar(post: Post, capsuleHeight: Dp, modifier: Modifier, actionBusy: Boolean,
    onWrite: () -> Unit, onLike: () -> Unit, onRepost: () -> Unit, onComments: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    val prompt = "说点什么…"
    val promptStyle = LocalTextStyle.current.copy(color = colors.onSurfaceVariant, fontSize = 13.5.sp)
    val promptWidth = rememberTextMeasurer().measure(prompt, promptStyle, maxLines = 1).size.width
    BoxWithConstraints(modifier.navigationBarsPadding().padding(start = 14.dp, end = 14.dp, top = 4.dp, bottom = 16.dp)
        .fillMaxWidth()) {
        // Keep the prompt's compact sizing while letting the gap grow to reach both edges.
        val capsuleSpace = (minOf(maxWidth, 288.dp) - 10.dp).coerceAtLeast(0.dp)
        val preferredPrompt = capsuleSpace * (9f / 21f)
        val minActions = minOf(capsuleSpace - preferredPrompt, 144.dp)
        val promptContent = with(LocalDensity.current) { promptWidth.toDp() } + 24.dp
        val promptCapsule = maxOf(preferredPrompt, promptContent + 12.dp).coerceAtMost(capsuleSpace - minActions)
        val promptPadding = ((promptCapsule - promptContent) / 2).coerceIn(4.dp, 14.dp)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            DetailCapsule(Modifier.width(promptCapsule).height(capsuleHeight)) {
                Row(Modifier.fillMaxSize().reviewClickable(onClickLabel = "发表评论", role = Role.Button, onClick = onWrite)
                    .padding(horizontal = promptPadding), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Edit, null, Modifier.size(16.dp), tint = colors.onSurfaceVariant)
                    Spacer(Modifier.width(8.dp))
                    BasicText(prompt, Modifier.weight(1f), style = promptStyle, maxLines = 1, softWrap = false,
                        autoSize = TextAutoSize.StepBased(minFontSize = 8.sp, maxFontSize = 13.5.sp, stepSize = .5.sp))
                }
            }
            DetailCapsule(Modifier.width(minOf(150.dp, capsuleSpace - promptCapsule)).height(capsuleHeight)) {
                Row(Modifier.fillMaxSize()) {
                    DetailAction(if (post.liked) Icons.Rounded.Favorite else Icons.Outlined.FavoriteBorder, "点赞",
                        post.likes, if (post.liked) colors.primary else colors.onSurfaceVariant, enabled = !actionBusy, onClick = onLike)
                    DetailAction(Icons.Rounded.Repeat, "转发", post.shares, colors.onSurfaceVariant, onClick = onRepost)
                    DetailAction(Icons.Rounded.ChatBubbleOutline, "评论", post.comments, colors.onSurfaceVariant, onClick = onComments)
                }
            }
        }
    }
}

@Composable
private fun DetailCapsule(modifier: Modifier, content: @Composable () -> Unit) {
    val colors = MaterialTheme.colorScheme
    val dark = colors.surface.luminance() < .5f
    val glass = LocalBackdrop.current != null
    val shape = RoundedCornerShape(24.dp)
    Surface(modifier, shape = shape, color = when {
        glass -> Color.Transparent
        dark -> Color(0xFF262626)
        else -> colors.surfaceContainerHighest.copy(alpha = .92f)
    }, border = if (glass) null else BorderStroke(.6.dp, colors.outlineVariant.copy(alpha = if (dark) .2f else .35f)),
        shadowElevation = if (glass) 0.dp else 2.dp) {
        Box {
            if (glass) Box(Modifier.matchParentSize().liquidBackdrop(
                if (dark) Color.Black.copy(alpha = .4f) else Color.White.copy(alpha = 240f / 255f), blur = 1.5.dp))
            content()
        }
    }
}

@Composable
private fun RowScope.DetailAction(icon: ImageVector, label: String, count: Int, tint: Color, enabled: Boolean = true, onClick: () -> Unit) {
    Column(Modifier.weight(1f).fillMaxHeight().reviewClickable(enabled, label, Role.Button, onClick)
        .padding(horizontal = 3.dp, vertical = 2.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center) {
        Icon(icon, label, Modifier.size(24.dp), tint = tint)
        Spacer(Modifier.height(1.dp))
        Text(compactCount(count), color = tint, fontSize = 9.sp, lineHeight = 10.sp,
            fontWeight = reviewWeight(FontWeight.SemiBold), maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
@OptIn(ExperimentalLayoutApi::class)
fun CommentEditor(post: Post, reply: Comment?, close: () -> Unit, sent: () -> Unit) {
    val model = LocalReview.current
    var text by rememberSaveable(post.id, reply?.id, stateSaver = TextFieldValue.Saver) { mutableStateOf(TextFieldValue()) }
    var emoji by remember { mutableStateOf(false) }
    var emojiDockBottom by remember { mutableIntStateOf(0) }
    val reservedDock = remember { Animatable(0f) }
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
            if (imeStart > 0) {
                val dock = reservedDock.value
                translationY = maxOf((sheetIme?.getBottom(density) ?: 0).toFloat(), dock) -
                    maxOf(animatedIme.toFloat(), dock * visibleFraction)
            }
        },
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp), containerColor = colors.surface,
        scrimColor = scrim.copy(alpha = scrim.alpha * opening.value * visibleFraction), sheetGesturesEnabled = canDismiss,
        properties = ModalBottomSheetProperties(shouldDismissOnBackPress = canDismiss, shouldDismissOnClickOutside = canDismiss)) {
        val focusManager = LocalFocusManager.current
        val keyboard = LocalSoftwareKeyboardController.current
        val ime = WindowInsets.ime
        val imeTarget = WindowInsets.imeAnimationTarget
        val navigationBars = WindowInsets.navigationBars
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
        LaunchedEffect(emoji, closing) {
            if (closing) return@LaunchedEffect
            if (emoji) {
                val alreadyLifted = ime.getBottom(density) > navigationBars.getBottom(density) || reservedDock.value > 0f
                if (alreadyLifted) reservedDock.snapTo(emojiDockBottom.toFloat())
                focusManager.clearFocus()
                keyboard?.hide()
                if (!alreadyLifted) reservedDock.animateTo(emojiDockBottom.toFloat(), tween(180))
            } else if (emojiDockBottom > 0) {
                withTimeoutOrNull(750L) {
                    snapshotFlow {
                        val target = imeTarget.getBottom(density)
                        target > navigationBars.getBottom(density) && ime.getBottom(density) >= target
                    }.first { it }
                }
                reservedDock.animateTo(0f, tween(180))
                emojiDockBottom = 0
            }
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
                    if (emoji) {
                        emoji = false
                        focus.requestFocus()
                        keyboard?.show()
                    } else {
                        val navigationBottom = navigationBars.getBottom(density)
                        emojiDockBottom = maxOf(ime.getBottom(density), reservedDock.value.roundToInt())
                            .takeIf { it > navigationBottom } ?: with(density) { 240.dp.roundToPx() } + navigationBottom
                        emoji = true
                    }
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
            if (emojiDockBottom > 0) {
                val panelHeight = with(density) { (emojiDockBottom - navigationBars.getBottom(this)).coerceAtLeast(0).toDp() }
                Box(Modifier.fillMaxWidth().clipToBounds().layout { measurable, constraints ->
                    // Material already reserves the live IME inset. The panel fills only the uncovered space.
                    val occupied = maxOf(ime.getBottom(this), navigationBars.getBottom(this))
                    val height = (reservedDock.value.roundToInt() - occupied).coerceIn(0, constraints.maxHeight)
                    val panel = measurable.measure(constraints.copy(minHeight = height, maxHeight = height))
                    layout(panel.width, height) { panel.placeRelative(0, 0) }
                }) {
                    EmojiPanel(backspace = { text = text.erasePhrase() }, modifier = Modifier
                        .wrapContentHeight(Alignment.Top, unbounded = true).height(panelHeight)) { phrase ->
                        val inserted = text.insertPhrase(phrase)
                        if (inserted.text.length <= 10000) text = inserted
                    }
                }
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
