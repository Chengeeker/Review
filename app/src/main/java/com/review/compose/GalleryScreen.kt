@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.os.Build
import android.widget.ImageView
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.gestures.stopScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.MotionPhotosOn
import androidx.compose.material.icons.rounded.PauseCircleOutline
import androidx.compose.material.icons.rounded.PlayCircleOutline
import androidx.compose.material3.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.border
import androidx.compose.ui.draw.clip
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.compose.ui.platform.LocalView
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlin.math.abs
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.isSpecified

internal val LocalGalleryOpenFrom = staticCompositionLocalOf<((List<Media>, Int, Map<Int, GalleryOrigin>) -> Unit)?> { null }
internal fun Media.galleryPreviewUrl(): String = (if (long || (width > 0 && height.toFloat() / width > 2f)) url else preview.ifBlank { url })
    .let { if (gif) it else highQualityPreviewUrl(it) }
internal fun galleryDoubleTapScale(scale: Float, long: Boolean): Float = when {
    scale <= 1.01f -> if (long) 3.5f else 2.5f
    scale <= 3.6f -> 6f
    else -> 1f
}

private val galleryCurve = CubicBezierEasing(.215f, .61f, .355f, 1f)

@Composable
internal fun Gallery(media: List<Media>, start: Int, sources: Map<Int, GalleryOrigin> = emptyMap(), onClose: () -> Unit) {
    val model = LocalReview.current
    val initial = start.coerceIn(media.indices)
    val pager = rememberPagerState(initial) { media.size }
    val scope = rememberCoroutineScope()
    val origin = remember { sources[initial] }
    val openingAnchor = remember { origin?.anchor() }
    val openingImage = remember { origin?.bitmap?.takeUnless(Bitmap::isRecycled) }
    val motion = remember { GalleryOpeningMotion(scope, if (openingAnchor != null && openingImage != null) 0f else 1f) }
    var flight by remember { mutableStateOf<GalleryFlight?>(null) }
    var returnGeneration by remember { mutableIntStateOf(0) }
    var viewport by remember { mutableStateOf(Rect.Zero) }
    val pagePlanes = remember { mutableMapOf<Int, () -> GalleryPlane?>() }
    val closing = motion.returning
    val preparingFlight = openingAnchor != null && openingImage != null && motion.position == 0f && !closing
    val morphing = preparingFlight || (flight != null && (motion.position < 1f || closing))
    DisposableEffect(flight?.source) {
        val source = flight?.source
        source?.covered = true
        onDispose { source?.covered = false }
    }
    LaunchedEffect(motion.position == 1f, closing) {
        if (motion.position == 1f && !closing) {
            withFrameNanos {}
            if (!motion.returning && motion.position == 1f) flight = null
        }
    }
    fun close() {
        if (motion.returning) return
        if (flight == null || motion.position >= 1f) {
            val page = pager.currentPage
            val source = sources[page]
            val anchor = source?.anchor()
            val plane = pagePlanes[page]?.invoke()
            flight = if (source != null && anchor != null && plane != null) GalleryFlight(source, anchor, plane) else null
            pager.requestScrollToPage(page)
        }
        val generation = ++returnGeneration
        motion.returnToSource {
            flight?.source?.covered = false
            scope.launch {
                withFrameNanos {}
                snapshotFlow { !motion.holdingGesture || !motion.returning || generation != returnGeneration }.first { it }
                if (motion.returning && generation == returnGeneration) onClose()
            }
        }
    }
    @Composable fun Content(inDialog: Boolean) {
        val pulse = reviewPulse()
        val item = media[pager.currentPage]
        val context = LocalContext.current
        var zoomed by remember { mutableStateOf(false) }
        var dragY by remember(pager.currentPage) { mutableFloatStateOf(0f) }
        var dragFraction by remember(pager.currentPage) { mutableFloatStateOf(0f) }
        var saveMessage by remember { mutableStateOf<String?>(null) }
        var saveRevision by remember { mutableIntStateOf(0) }
        val (saving, saveMedia) = rememberMediaSaver { saveMessage = it; saveRevision++ }
        var showControls by remember { mutableStateOf(true) }
        var livePlaying by remember(pager.currentPage) { mutableStateOf(false) }
        var liveSave by remember { mutableStateOf(false) }
        var videoControlsHeight by remember { mutableIntStateOf(0) }
        var videoFullscreen by remember { mutableStateOf(false) }
        var thumbnailScrolling by remember { mutableStateOf(false) }
        val mainDragging by pager.interactionSource.collectIsDraggedAsState()
        LaunchedEffect(mainDragging) { if (mainDragging) livePlaying = false }
        val density = LocalDensity.current
        val landscape = androidx.compose.ui.platform.LocalConfiguration.current.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
        val view = LocalView.current
        val window = if (inDialog) (view.parent as? DialogWindowProvider)?.window else LocalActivity.current?.window
        DisposableEffect(window, inDialog) {
            if (inDialog) window?.apply {
                setWindowAnimations(0)
                setDimAmount(0f)
                setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.TRANSPARENT))
                applyReviewSystemBars(this, view, dark = true)
            }
            val status = androidx.core.view.WindowInsetsCompat.Type.statusBars()
            onDispose { if (!inDialog && window != null) androidx.core.view.WindowCompat.getInsetsController(window, view).show(status) }
        }
        LaunchedEffect(window, showControls) {
            window?.let {
                val bars = androidx.core.view.WindowCompat.getInsetsController(it, view)
                val status = androidx.core.view.WindowInsetsCompat.Type.statusBars()
                if (showControls) bars.show(status) else bars.hide(status)
            }
        }
        val hasHdr = MediaFiles.hdr[item.url] == true
        var hdrActive by remember(window) { mutableStateOf(false) }
        LaunchedEffect(hasHdr, motion.position == 1f, closing) {
            if (!hasHdr) hdrActive = false
            else if (motion.position == 1f && !closing) hdrActive = true
        }
        DisposableEffect(window, hdrActive) {
            val original = window?.colorMode
            val changed = Build.VERSION.SDK_INT >= 34 && hdrActive && view.display?.isHdr == true && original != ActivityInfo.COLOR_MODE_HDR
            if (changed) {
                window?.colorMode = ActivityInfo.COLOR_MODE_HDR
                if (Build.VERSION.SDK_INT >= 35) window?.setDesiredHdrHeadroom(0f)
            }
            onDispose { if (changed && original != null) window?.colorMode = original }
        }
        BackHandler { close() }
        fun save(target: Media) = saveMedia(listOf(target))
        val mediaLayer = androidx.compose.ui.graphics.rememberGraphicsLayer()
        val mediaBackdrop = remember(mediaLayer) { ReviewBackdrop(mediaLayer) }
        CompositionLocalProvider(LocalBackdrop provides mediaBackdrop) {
        Box(Modifier.fillMaxSize().onGloballyPositioned { coordinates ->
            val position = coordinates.positionOnScreen()
            if (!position.isSpecified) return@onGloballyPositioned
            viewport = Rect(position, Size(coordinates.size.width.toFloat(), coordinates.size.height.toFloat()))
            if (motion.position == 0f && !motion.returning && flight == null && origin != null && openingAnchor != null && openingImage != null) {
                val destination = galleryImagePlane(viewport, Size(openingImage.width.toFloat(), openingImage.height.toFloat()), crop = false)
                flight = GalleryFlight(origin, openingAnchor, GalleryPlane(openingImage, destination, viewport))
                motion.open()
            }
        }.galleryOverlayInput(
            target = { if (motion.returning) flight?.anchor?.visible?.translate(-viewport.topLeft) else null },
            canSwipe = { flight != null && media.size > 1 && !motion.returning },
            hold = { motion.holdingGesture = it },
            reopen = { if (motion.returning) { returnGeneration++; flight?.source?.covered = true; pulse(); motion.open() } },
            swipe = { direction ->
                val index = pager.currentPage + if (direction < 0) 1 else -1
                if (index in media.indices) {
                    motion.finishOpening(); flight = null
                    scope.launch { pager.scrollToPage(index) }
                }
            },
        ).graphicsLayer { alpha = if (closing && !morphing) motion.position else 1f }
            .background(Color.Black.copy(alpha = motion.position * (1f - dragFraction).coerceIn(0f, 1f)))) {
            HorizontalPager(pager, userScrollEnabled = !zoomed && !videoFullscreen && !closing && !morphing,
                modifier = Modifier.fillMaxSize().graphicsLayer { alpha = if (morphing) 0f else 1f }.recordBackdrop(mediaBackdrop), beyondViewportPageCount = 0) { page ->
                val picture = media[page]
                if (picture.video.isNotBlank() && !picture.live) {
                    if (page == pager.settledPage && !pager.isScrollInProgress && !closing) VideoSurface(picture, true, ::close, { save(it.copy(live = false)) },
                        onControlsHeight = { videoControlsHeight = it }, embedded = true, onToggleChrome = { showControls = !showControls },
                        onFullscreenChanged = { videoFullscreen = it }, saving = saving)
                    else MediaImage(picture, "视频封面", Modifier.fillMaxSize(), fit = true, backgroundColor = Color.Black)
                } else {
                    val firstBitmap = remember(page) { if (page == initial) openingImage else sources[page]?.bitmap }
                    var scale by remember(page) { mutableFloatStateOf(1f) }
                    var pan by remember(page) { mutableStateOf(Offset.Zero) }
                    var displayedBitmap by remember(page) { mutableStateOf(firstBitmap) }
                    var zoomAnimation by remember(page) { mutableStateOf<kotlinx.coroutines.Job?>(null) }
                    DisposableEffect(page) {
                        pagePlanes[page] = {
                            displayedBitmap?.takeUnless(Bitmap::isRecycled)?.let { bitmap ->
                                val plane = galleryImagePlane(viewport, Size(bitmap.width.toFloat(), bitmap.height.toFloat()), crop = false)
                                val center = viewport.center
                                GalleryPlane(bitmap, Rect(center + (plane.topLeft - center) * scale + pan + Offset(0f, dragY),
                                    center + (plane.bottomRight - center) * scale + pan + Offset(0f, dragY)), viewport)
                            }
                        }
                        onDispose { pagePlanes.remove(page) }
                    }
                    LaunchedEffect(pager.currentPage) { zoomAnimation?.cancel(); scale = 1f; pan = Offset.Zero; zoomed = false }
                    BoxWithConstraints(Modifier.fillMaxSize()) {
                        val density = LocalDensity.current
                        val pageWidth = maxWidth; val pageHeight = maxHeight
                        val width = with(density) { pageWidth.toPx() }; val height = with(density) { pageHeight.toPx() }
                        val gesture = rememberTransformableState { zoom, offset, _ ->
                            zoomAnimation?.cancel()
                            scale = (scale * zoom).coerceIn(1f, 8f)
                            pan = Offset((pan.x + offset.x).coerceIn(-width * (scale - 1) / 2, width * (scale - 1) / 2),
                                (pan.y + offset.y).coerceIn(-height * (scale - 1) / 2, height * (scale - 1) / 2)); zoomed = scale > 1.01f
                        }
                        Box(Modifier.fillMaxSize().transformable(gesture, canPan = { scale > 1f })
                            .pointerInput(page, width, height) { detectTapGestures(onTap = { tap ->
                                if (tap.x >= width / 3 && tap.x < width * 2 / 3) showControls = !showControls else close()
                            }, onDoubleTap = { tap ->
                                pulse()
                                zoomAnimation?.cancel()
                                val target = galleryDoubleTapScale(scale, picture.long)
                                val from = pan
                                val focus = Offset(tap.x - width / 2, tap.y - height / 2)
                                val destination = focus - (focus - from) * (target / scale)
                                val boundX = width * (target - 1) / 2
                                val boundY = height * (target - 1) / 2
                                val to = Offset(destination.x.coerceIn(-boundX, boundX), destination.y.coerceIn(-boundY, boundY))
                                zoomed = true
                                zoomAnimation = scope.launch {
                                    val initialScale = scale
                                    Animatable(0f).animateTo(1f, tween(220, easing = galleryCurve)) {
                                        scale = initialScale + (target - initialScale) * value
                                        pan = from + (to - from) * value
                                    }
                                    zoomed = scale > 1.01f
                                }
                            }, onLongPress = { if (picture.live) { pulse(); livePlaying = true } }, onPress = { try { tryAwaitRelease() } finally { if (picture.live) livePlaying = false } }) }
                            .pointerInput(page, zoomed, closing, height) { if (!zoomed && !closing) detectVerticalDragGestures(onDragEnd = {
                                if (abs(dragY) > height * .18f) { pulse(); close() }
                                else scope.launch { Animatable(dragY).animateTo(0f, tween(200, easing = galleryCurve)) { dragY = value; dragFraction = abs(value) / (height * .5f) } }
                            }, onDragCancel = { dragY = 0f; dragFraction = 0f }) { _, delta ->
                                dragY += delta; dragFraction = abs(dragY) / (height * .5f)
                            } }, contentAlignment = Alignment.Center) {
                            Box(Modifier.fillMaxSize().graphicsLayer { scaleX = scale; scaleY = scale; translationX = pan.x; translationY = pan.y + dragY }, contentAlignment = Alignment.Center) {
                                if (picture.card) {
                                    val ratio = galleryRatio(picture)
                                    val cardWidth = minOf(pageWidth, pageHeight * ratio)
                                    WebCardImage(picture, "网页卡片", Modifier.width(cardWidth).aspectRatio(ratio), caption = true, onBitmap = { displayedBitmap = it })
                                } else OriginalImage(picture, model.sessionCookie, Modifier.fillMaxSize(),
                                    firstBitmap = firstBitmap, onBitmap = { displayedBitmap = it }, showImage = !morphing)
                                if (picture.live && picture.video.isNotBlank() && page == pager.settledPage && !pager.isScrollInProgress && !closing && !morphing) VideoSurface(picture, livePlaying, ::close, { save(picture.copy(live = false)) }, false)
                            }
                        }
                    }
                }
            }
            flight?.let { GalleryFlightImage(it, viewport.topLeft, motion.position) }
            val chrome = showControls && !videoFullscreen && !morphing && !closing && dragFraction == 0f
            val desiredThumbnailBottom = if (item.video.isNotBlank() && !item.live) with(density) { videoControlsHeight.toDp() } + 8.dp
                else WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + 32.dp
            var thumbnailBottom by remember { mutableStateOf(desiredThumbnailBottom) }
            LaunchedEffect(desiredThumbnailBottom, thumbnailScrolling) { if (!thumbnailScrolling) thumbnailBottom = desiredThumbnailBottom }
            if (chrome && (item.video.isBlank() || item.live)) Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                GalleryGlassButton(Icons.AutoMirrored.Outlined.ArrowBack, "返回", click = ::close)
                Spacer(Modifier.weight(1f))
                val live = item.live && item.video.isNotBlank()
                if (live) {
                    val pill = RoundedCornerShape(20.dp)
                    val textColor = if (livePlaying) Color.Black else Color.White
                    val background by animateColorAsState(if (livePlaying) Color.White else Color.Black.copy(alpha = .54f), tween(250))
                    val outline by animateColorAsState(if (livePlaying) Color.White else Color.White.copy(alpha = .24f), tween(250))
                    Row(Modifier.clip(pill).background(background).border(1.dp, outline, pill)
                        // Flutter adds the decoration's 1dp border to the 14dp × 6dp padding.
                        .reviewClickable { livePlaying = !livePlaying }.padding(horizontal = 15.dp, vertical = 7.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Icon(if (livePlaying) Icons.Rounded.PauseCircleOutline else Icons.Rounded.PlayCircleOutline, null, Modifier.size(16.dp), tint = textColor)
                        Spacer(Modifier.width(5.dp))
                        Text(if (livePlaying) "暂停 Live 图" else "播放 Live 图", color = textColor, fontSize = 12.5.sp,
                            fontWeight = FontWeight.Bold, style = MaterialTheme.typography.bodyMedium)
                    }
                } else {
                    Text("${pager.currentPage + 1} / ${media.size}",
                        Modifier.background(Color.Black.copy(alpha = .45f), RoundedCornerShape(16.dp)).padding(horizontal = 14.dp, vertical = 6.dp),
                        color = Color.White, fontSize = 13.sp, lineHeight = 16.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.weight(1f))
                GalleryGlassButton(Icons.Rounded.Download, "下载", enabled = !saving, busy = saving) { if (item.live) liveSave = true else save(item) }
            }
            if (chrome && hasHdr) HdrBadge(Modifier.align(Alignment.BottomEnd).navigationBarsPadding()
                .padding(end = 16.dp, bottom = if (media.size > 1) 110.dp else 24.dp))
            if (chrome && media.size > 1 && !(landscape && item.video.isNotBlank() && !item.live)) GalleryThumbnails(media, pager,
                Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(start = 12.dp, end = 12.dp, bottom = thumbnailBottom),
                onScrolling = { thumbnailScrolling = it }, onUserDrag = { livePlaying = false })
            ReviewToast(saveMessage, saveRevision, MaterialTheme.colorScheme.background.luminance() < .5f) { saveMessage = null }
            if (liveSave) ModalBottomSheet(onDismissRequest = { liveSave = false }, containerColor = Color.Transparent, dragHandle = null,
                contentWindowInsets = { WindowInsets(0) }, shape = RoundedCornerShape(0.dp)) {
                Surface(Modifier.padding(16.dp), shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surface) {
                    Column(Modifier.navigationBarsPadding()) {
                        Spacer(Modifier.height(12.dp))
                        Text("保存实况照片", Modifier.align(Alignment.CenterHorizontally), fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.Bold))
                        Spacer(Modifier.height(12.dp))
                        ReviewListItem(headlineContent = { Text("保存静态高清大图") }, leadingContent = { Icon(Icons.Outlined.PhotoLibrary, null) }, modifier = Modifier.reviewClickable { liveSave = false; save(item) })
                        ReviewListItem(headlineContent = { Text("保存 Live 动图 / 视频") }, leadingContent = { Icon(Icons.Rounded.MotionPhotosOn, null) }, modifier = Modifier.reviewClickable { liveSave = false; save(item.copy(live = false)) })
                        ReviewListItem(headlineContent = { Text("全部保存 (高清大图 + Live 视频)") }, leadingContent = { Icon(Icons.Outlined.DownloadForOffline, null) }, modifier = Modifier.reviewClickable { liveSave = false; saveMedia(listOf(item, item.copy(live = false))) })
                    }
                }
            }
        }
        }
    }
    if (sources.isEmpty()) {
        Dialog(onDismissRequest = ::close, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) { Content(true) }
    } else Content(false)
}

private fun galleryRatio(media: Media): Float = if (media.width > 0 && media.height > 0) media.width.toFloat() / media.height else if (media.card) 16f / 9f else 1f

@Composable
internal fun GalleryThumbnails(media: List<Media>, pager: androidx.compose.foundation.pager.PagerState, modifier: Modifier, onScrolling: (Boolean) -> Unit, onUserDrag: () -> Unit) {
    val list = rememberLazyListState(pager.currentPage)
    val dragged by list.interactionSource.collectIsDraggedAsState()
    val mainDragged by pager.interactionSource.collectIsDraggedAsState()
    var ownsSelection by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val tick = reviewPulse()
    LaunchedEffect(dragged) { if (dragged) onUserDrag() }
    LaunchedEffect(list.isScrollInProgress) { onScrolling(list.isScrollInProgress) }
    LaunchedEffect(dragged, list.isScrollInProgress, mainDragged) {
        if (mainDragged) { ownsSelection = false; list.stopScroll() }
        else if (dragged) ownsSelection = true
        else if (!list.isScrollInProgress) ownsSelection = false
    }
    LaunchedEffect(ownsSelection) {
        if (!ownsSelection) return@LaunchedEffect
        snapshotFlow {
            val layout = list.layoutInfo
            val center = (layout.viewportStartOffset + layout.viewportEndOffset) / 2
            layout.visibleItemsInfo.minByOrNull { abs(it.offset + it.size / 2 - center) }?.index
        }.collectLatest { index -> if (index != null && index != pager.currentPage) { tick(); pager.scrollToPage(index) } }
    }
    LaunchedEffect(pager.currentPage, ownsSelection, pager.isScrollInProgress) {
        if (!ownsSelection && !pager.isScrollInProgress) list.scrollToItem(pager.currentPage)
    }
    BoxWithConstraints(modifier) {
        val cell = maxWidth * .16f
        LazyRow(state = list, contentPadding = PaddingValues(horizontal = (maxWidth - cell) / 2), modifier = Modifier.height(64.dp)) {
            items(media.size) { index ->
                val item = media[index]
                LaunchedEffect(item.url, item.canHaveHdrBadge) {
                    if (item.canHaveHdrBadge) MediaFiles.probeHdr(item.url)
                }
                val selected = pager.currentPage == index
                val outline = RoundedCornerShape(8.dp)
                Box(Modifier.width(cell).fillMaxHeight().padding(horizontal = 3.dp, vertical = 2.dp)
                    .then(if (selected) Modifier.border(2.dp, Color.White, outline) else Modifier)
                    .semantics { this.selected = selected }
                    .reviewClickable { scope.launch { list.scrollToItem(index); pager.scrollToPage(index) } }) {
                    Box(Modifier.fillMaxSize().padding(2.dp).clip(RoundedCornerShape(6.dp))) {
                        val image = Modifier.fillMaxSize()
                        if (item.card) WebCardImage(item, "第 ${index + 1} 张图片", image, caption = false)
                        else MediaImage(item.copy(url = item.preview.ifBlank { item.url }), "第 ${index + 1} 张图片", image)
                        if (!selected) Box(Modifier.matchParentSize().background(Color.White.copy(alpha = .5f)))
                        if (item.video.isNotBlank() && !item.live) Icon(Icons.Outlined.PlayCircle, null, Modifier.align(Alignment.Center).size(20.dp), tint = Color.White)
                        if (MediaFiles.hasHdrBadge(item)) HdrBadge(Modifier.align(Alignment.BottomEnd).padding(3.dp),
                            description = "第 ${index + 1} 张 HDR 图片", compact = true)
                    }
                }
            }
        }
    }
}

@Composable
fun OriginalImage(media: Media, cookie: String, modifier: Modifier, firstBitmap: Bitmap? = null, onBitmap: ((Bitmap) -> Unit)? = null,
    showImage: Boolean = true) {
    if (media.artwork > 0) { LandscapeArt(media.artwork, modifier); return }
    val context = LocalContext.current
    if (media.gif || media.url.substringBefore('?').endsWith(".gif", true)) {
        coil.compose.SubcomposeAsyncImage(model = coil.request.ImageRequest.Builder(context).data(media.url).diskCacheKey(MediaFiles.cacheKey(media.url, cookie)).memoryCacheKey(MediaFiles.cacheKey(media.url, cookie)).apply { MediaFiles.privateMediaCookie(media.url, cookie).takeIf(String::isNotBlank)?.let { addHeader("Cookie", it) } }.build(), contentDescription = "动画图片", modifier = modifier,
            contentScale = androidx.compose.ui.layout.ContentScale.Fit, loading = { Box(contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp), color = Color.White) } })
        return
    }
    var bitmap by remember(media.url, cookie) { mutableStateOf<Bitmap?>(MediaFiles.bitmaps.get(MediaFiles.cacheKey(media.url, cookie))) }
    var animation by remember(media.url, cookie) { mutableStateOf<java.io.File?>(null) }
    var error by remember(media.url) { mutableStateOf<String?>(null) }
    var attempt by remember(media.url) { mutableIntStateOf(0) }
    LaunchedEffect(media.url, attempt) {
        try {
            val file = MediaFiles.fetch(context, media.url, cookie)
            val animated = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { file.inputStream().use { it.read() == 0x47 && it.read() == 0x49 && it.read() == 0x46 } }
            if (animated) animation = file else bitmap = MediaFiles.decode(context, media, cookie)
            error = null
        }
        catch (e: CancellationException) { throw e }
        catch (e: Exception) { error = e.message }
        catch (_: OutOfMemoryError) { error = "图片解码内存不足，请重试" }
    }
    val displayed = bitmap ?: firstBitmap?.takeUnless(Bitmap::isRecycled)
    SideEffect { displayed?.let { onBitmap?.invoke(it) } }
    // Keep loading during the flight without mounting a native view beneath its pixels.
    if (!showImage) return
    Box(modifier, contentAlignment = Alignment.Center) {
        if (animation != null) coil.compose.AsyncImage(animation, "动画图片", Modifier.fillMaxSize(), contentScale = androidx.compose.ui.layout.ContentScale.Fit)
        else if (displayed != null) AndroidView(factory = { ImageView(it).apply { scaleType = ImageView.ScaleType.FIT_CENTER } }, update = { it.setImageBitmap(displayed) }, modifier = Modifier.fillMaxSize(), onRelease = { it.setImageDrawable(null) })
        else {
            val preview = media.galleryPreviewUrl().takeIf { it.isNotBlank() && it != media.url }
            if (preview != null) MediaImage(media.copy(url = preview), "图片预览", Modifier.fillMaxSize(), fit = true, overlay = true, onBitmap = onBitmap)
            if (error == null) {
                if (preview == null) CircularProgressIndicator(Modifier.size(24.dp), color = Color.White)
            } else TextButton(onClick = hapticClick { error = null; attempt++ }) { Text("图片加载失败，点击重试", color = Color.White) }
        }
    }
}
