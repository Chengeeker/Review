@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.media.AudioManager
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

@Composable
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
fun VideoSurface(media: Media, active: Boolean, close: () -> Unit, download: (Media) -> Unit, controlsEnabled: Boolean = true,
    onControlsHeight: (Int) -> Unit = {}, embedded: Boolean = false, onToggleChrome: () -> Unit = {},
    onFullscreenChanged: (Boolean) -> Unit = {}, saving: Boolean = false, post: Post? = null) {
    val context = LocalContext.current
    val model = LocalReview.current
    val cookie = model.sessionCookie
    val liveLayer = media.live && !controlsEnabled
    val client = remember(media.video, cookie) {
        okhttp3.OkHttpClient.Builder().addNetworkInterceptor { chain ->
            val request = chain.request().newBuilder().removeHeader("Cookie")
            MediaFiles.privateMediaCookie(chain.request().url.toString(), cookie).takeIf(String::isNotBlank)?.let { request.header("Cookie", it) }
            chain.proceed(request.build())
        }.build()
    }
    val player = remember(client) {
        val factory = androidx.media3.datasource.okhttp.OkHttpDataSource.Factory(client).setUserAgent(ApiClient.USER_AGENT)
            .setDefaultRequestProperties(mapOf("Referer" to "https://weibo.com/"))
        ExoPlayer.Builder(context).setMediaSourceFactory(DefaultMediaSourceFactory(context).setDataSourceFactory(factory)).build().apply {
            repeatMode = Player.REPEAT_MODE_ONE
            if (media.live) setAudioAttributes(
                androidx.media3.common.AudioAttributes.Builder().setContentType(androidx.media3.common.C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
        }
    }
    DisposableEffect(player) { onDispose {
        player.release()
        // Closing a pooled TLS socket can write its close alert; keep that work off the UI thread.
        client.dispatcher.executorService.apply {
            execute { client.connectionPool.evictAll() }
            shutdown()
        }
    } }
    key(player, liveLayer) {
        VideoPlayerContent(player, media, active, close, download, controlsEnabled, onControlsHeight, embedded,
            onToggleChrome, onFullscreenChanged, saving, post) {
            AndroidView(factory = { context ->
                (if (liveLayer) android.view.LayoutInflater.from(context).inflate(R.layout.live_photo_player, null, false) as PlayerView else PlayerView(context))
                    .apply { useController = false; keepScreenOn = false; setKeepContentOnPlayerReset(true); this.player = player }
            },
                modifier = Modifier.fillMaxSize(), onRelease = { it.player = null })
        }
    }
}

@Composable
internal fun VideoPlayerContent(player: Player, media: Media, active: Boolean, close: () -> Unit, download: (Media) -> Unit,
    controlsEnabled: Boolean = true, onControlsHeight: (Int) -> Unit = {}, embedded: Boolean = false,
    onToggleChrome: () -> Unit = {}, onFullscreenChanged: (Boolean) -> Unit = {}, saving: Boolean = false, post: Post? = null,
    video: @Composable () -> Unit) {
    val context = LocalContext.current
    val model = LocalReview.current
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val visible = active && LocalPageActive.current && lifecycle.isAtLeast(Lifecycle.State.STARTED)
    val liveLayer = media.live && !controlsEnabled
    var renderedFrame by remember(player) { mutableStateOf(false) }
    var wantsPlayback by remember { mutableStateOf(true) }
    val shouldPlay by rememberUpdatedState(visible && wantsPlayback)
    var url by remember { mutableStateOf(media.video) }
    var playbackUrl by remember { mutableStateOf(media.video) }
    var qualities by remember { mutableStateOf(normalizeVideoQualities(media.qualities, media.video)) }
    var controls by remember { mutableStateOf(controlsEnabled) }
    var error by remember { mutableStateOf<String?>(null) }
    var retry by remember { mutableIntStateOf(0) }
    val canRefresh = !media.live && (normalizeVideoId(media.videoId) != null || post?.id?.let { it.isNotBlank() && it.all(Char::isDigit) } == true)
    var refreshSource by remember { mutableStateOf(false) }
    var recovered by remember { mutableStateOf(false) }
    var position by remember { mutableLongStateOf(player.currentPosition) }
    var duration by remember { mutableLongStateOf(player.duration.coerceAtLeast(0)) }
    var buffered by remember { mutableLongStateOf(0) }
    var playing by remember { mutableStateOf(player.isPlaying) }
    var initialized by remember { mutableStateOf(player.playbackState == Player.STATE_READY) }
    var buffering by remember { mutableStateOf(!initialized) }
    var menu by remember { mutableStateOf("") }
    var speed by remember { mutableFloatStateOf(1f) }
    var fast by remember { mutableStateOf(false) }
    var timer by remember { mutableIntStateOf(0) }
    var hud by remember { mutableStateOf("") }
    var hudValue by remember { mutableFloatStateOf(.5f) }
    var hudVersion by remember { mutableIntStateOf(0) }
    var width by remember { mutableFloatStateOf(1f) }
    var height by remember { mutableFloatStateOf(1f) }
    var drag by remember { mutableFloatStateOf(0f) }
    var dragMode by remember { mutableStateOf("") }
    var startLevel by remember { mutableFloatStateOf(.5f) }
    var scrubbing by remember { mutableStateOf(false) }
    var resumeAfterScrub by remember { mutableStateOf(false) }
    val audio = remember(context) { context.getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    val activity = LocalActivity.current
    val view = LocalView.current
    val window = (view.parent as? DialogWindowProvider)?.window ?: activity?.window
    val verticalThreshold = with(LocalDensity.current) { 14.dp.toPx() }
    val pulse = reviewPulse()
    var fullscreen by remember { mutableStateOf(false) }
    fun rotate(value: Boolean) { fullscreen = value; onFullscreenChanged(value); timer++ }
    BackHandler(fullscreen) { rotate(false) }
    DisposableEffect(activity, window, fullscreen) {
        val wasFullscreen = fullscreen
        val bars = window?.let { WindowCompat.getInsetsController(it, it.decorView) }
        val insets = window?.decorView?.let(androidx.core.view.ViewCompat::getRootWindowInsets)
        val statusVisible = insets?.isVisible(WindowInsetsCompat.Type.statusBars()) != false
        val navVisible = insets?.isVisible(WindowInsetsCompat.Type.navigationBars()) != false
        val behavior = bars?.systemBarsBehavior
        if (wasFullscreen) {
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            bars?.systemBarsBehavior = androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            bars?.hide(WindowInsetsCompat.Type.systemBars())
        }
        onDispose { if (wasFullscreen) {
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            if (statusVisible) bars?.show(WindowInsetsCompat.Type.statusBars()) else bars?.hide(WindowInsetsCompat.Type.statusBars())
            if (navVisible) bars?.show(WindowInsetsCompat.Type.navigationBars()) else bars?.hide(WindowInsetsCompat.Type.navigationBars())
            if (behavior != null) bars?.systemBarsBehavior = behavior
        } }
    }
    DisposableEffect(window, visible) {
        val brightness = if (visible) window?.attributes?.screenBrightness else null
        onDispose { if (brightness != null) window?.let { it.attributes = it.attributes.apply { screenBrightness = brightness } } }
    }
    DisposableEffect(visible, playing, window) {
        val keepAwake = visible && playing
        if (keepAwake) window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose { if (keepAwake) window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
    }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlayerError(failure: PlaybackException) {
                renderedFrame = false
                initialized = false
                if (canRefresh && !recovered) {
                    recovered = true; refreshSource = true; buffering = true; error = null; retry++
                } else { error = "视频加载失败或链接已失效"; buffering = false }
            }
            override fun onIsPlayingChanged(value: Boolean) { playing = value }
            override fun onRenderedFirstFrame() { renderedFrame = true }
            override fun onPlaybackStateChanged(state: Int) {
                buffering = state == Player.STATE_BUFFERING
                if (state == Player.STATE_READY) initialized = true
                if (state == Player.STATE_ENDED) { wantsPlayback = false; controls = controlsEnabled }
                duration = player.duration.coerceAtLeast(0)
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener); player.pause(); onFullscreenChanged(false) }
    }
    var selectedTrack by remember(player) { mutableStateOf("自动") }
    LaunchedEffect(url, retry) {
        renderedFrame = false
        try {
            val resolved = when {
                refreshSource -> model.repository.refreshVideo(model.sessionCookie, media, post)
                videoObjectId(url) != null || liveRoomId(url) != null -> model.repository.resolveVideo(model.sessionCookie, url)
                else -> media.copy(video = url)
            }
            refreshSource = false
            if (resolved.qualities.isNotEmpty()) qualities = normalizeVideoQualities(resolved.qualities, resolved.video)
            val playback = qualities.values.firstOrNull { it == resolved.video } ?: qualities.values.firstOrNull() ?: resolved.video
            playbackUrl = playback
            val resume = player.currentPosition
            if (controlsEnabled && !media.live) selectVideoTrack(player, null)
            selectedTrack = "自动"
            player.setMediaItem(MediaItem.fromUri(playback), resume); player.prepare()
            player.setPlaybackSpeed(speed); player.playWhenReady = shouldPlay; error = null
        } catch (e: CancellationException) { throw e } catch (e: Exception) { error = e.message; buffering = false }
    }
    LaunchedEffect(visible, wantsPlayback) {
        player.playWhenReady = shouldPlay
        if (!visible && fast) { fast = false; player.setPlaybackSpeed(speed) }
    }
    LaunchedEffect(controls, playing, menu, fast, scrubbing, dragMode, timer) {
        if (controls && playing && menu.isBlank() && !fast && !scrubbing && dragMode.isBlank()) { delay(4000); controls = false }
    }
    LaunchedEffect(player, visible) { while (visible) {
        if (!scrubbing) position = player.currentPosition
        duration = player.duration.coerceAtLeast(0); buffered = player.bufferedPosition.coerceAtLeast(0); delay(250)
    } }
    LaunchedEffect(hudVersion, dragMode) {
        if (dragMode.isBlank() && hud.isNotBlank()) { delay(if (hud == "forward" || hud == "rewind") 800 else 600); hud = "" }
    }
    fun togglePlayback() {
        if (!initialized) return
        wantsPlayback = !wantsPlayback
        if (!wantsPlayback) controls = true
        else if (duration > 0 && player.currentPosition >= duration) player.seekTo(0)
        timer++
    }
    val trackChoices = if (controlsEnabled && !media.live) rememberVideoTrackChoices(player) else emptyMap()
    val manualQualities = qualities.takeIf { it.values.distinct().size > 1 }.orEmpty()
    val currentQuality = if (manualQualities.isNotEmpty()) manualQualities.entries.firstOrNull { it.value == playbackUrl }?.key ?: "画质"
        else selectedTrack.takeIf { trackChoices.isNotEmpty() }
    val author = post?.author ?: model.mediaAuthor
    Box(Modifier.fillMaxSize().background(if (liveLayer) Color.Transparent else Color.Black).onSizeChanged { width = it.width.coerceAtLeast(1).toFloat(); height = it.height.coerceAtLeast(1).toFloat() }) {
        Box(Modifier.fillMaxSize().graphicsLayer { alpha = if (liveLayer && (!visible || !renderedFrame)) 0f else 1f }) { video() }
        if (!liveLayer && !initialized && error == null && media.url.isNotBlank()) MediaImage(media, "视频封面", Modifier.fillMaxSize(), fit = true, backgroundColor = Color.Black)
        if (controlsEnabled) Box(Modifier.matchParentSize().testTag("video-gestures").pointerInput(player, fullscreen) {
            detectTapGestures(onTap = {
                pulse(); controls = !controls; timer++; if (!fullscreen) onToggleChrome()
            }, onDoubleTap = { point ->
                if (initialized) {
                    pulse()
                    when {
                        point.x < width * .35f || point.x > width * .65f -> {
                            val forward = point.x > width * .65f
                            player.seekTo((player.currentPosition + if (forward) 10000 else -10000).coerceIn(0L, duration))
                            hud = if (forward) "forward" else "rewind"; hudVersion++
                        }
                        else -> togglePlayback()
                    }
                    timer++
                }
            }, onLongPress = { point ->
                if (initialized && (point.x < width * .45f || point.x > width * .55f)) { pulse(); fast = true; player.setPlaybackSpeed(2f) }
            }, onPress = {
                try { tryAwaitRelease() } finally { if (fast) { fast = false; player.setPlaybackSpeed(speed); timer++ } }
            })
        }.pointerInput(player) {
            detectVerticalDragGestures(onDragStart = { point ->
                drag = 0f; dragMode = if (point.x < width / 2) "brightness" else "volume"
                startLevel = if (dragMode == "brightness") window?.attributes?.screenBrightness?.takeIf { it >= 0 }
                    ?: runCatching { Settings.System.getInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128) / 255f }.getOrDefault(.5f)
                    else audio.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() / audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
            }, onDragEnd = { dragMode = ""; hudVersion++; timer++ }, onDragCancel = { dragMode = ""; hudVersion++; timer++ }) { change, delta ->
                drag += delta
                if (kotlin.math.abs(drag) <= verticalThreshold) return@detectVerticalDragGestures
                hudValue = (startLevel - drag / (height * .65f)).coerceIn(if (dragMode == "brightness") .01f else 0f, 1f)
                if (dragMode == "brightness") window?.let { it.attributes = it.attributes.apply { screenBrightness = hudValue } }
                else { runCatching { audio.setStreamVolume(AudioManager.STREAM_MUSIC, (hudValue * audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)).toInt(), 0) }; player.volume = hudValue }
                hud = dragMode; change.consume()
            }
        })
        if (!liveLayer && buffering && error == null) CircularProgressIndicator(Modifier.align(Alignment.Center), color = Color.White.copy(alpha = .7f))
        error?.takeIf { !liveLayer || visible }?.let { message -> Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Rounded.ErrorOutline, null, Modifier.size(48.dp), tint = Color.White.copy(alpha = .7f))
            Spacer(Modifier.height(12.dp)); Text(message, color = Color.White.copy(alpha = .7f), fontSize = 14.sp)
            Spacer(Modifier.height(16.dp)); FilledTonalButton(onClick = hapticClick { refreshSource = canRefresh; recovered = canRefresh; error = null; buffering = true; initialized = false; retry++ }) { Text("重试") }
        } }
        if (fast) Row(Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 50.dp)
            .shadow(12.dp, RoundedCornerShape(20.dp)).clip(RoundedCornerShape(20.dp)).background(Color.Black.copy(alpha = .87f))
            .border(.8.dp, Color.White.copy(alpha = .24f), RoundedCornerShape(20.dp)).padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.FastForward, null, Modifier.size(20.dp), tint = Color(0xFFFFD740)); Spacer(Modifier.width(8.dp))
            Text("2.0X 倍速快进中", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, letterSpacing = .5.sp)
        }
        if (hud.isNotBlank()) VideoGestureHud(hud, hudValue, Modifier.align(Alignment.Center))
        if (controls && controlsEnabled && !embedded) ReviewVideoTop(title = media.title, author = author, fullscreen = fullscreen,
            close = { if (fullscreen) rotate(false) else close() }) {
            ReviewVideoAction("download", "下载视频", enabled = !saving, busy = saving) { download(media.copy(video = playbackUrl, qualities = qualities)) }
            ReviewVideoAction("share", "分享视频") {
                val link = post?.id?.takeIf { it.matches(Regex("[0-9A-Za-z]+")) }?.let { "https://weibo.com/detail/$it" } ?: playbackUrl
                (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("视频链接", link))
                runCatching { context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain")
                    .putExtra(Intent.EXTRA_TEXT, "${media.title.ifBlank { "微博视频" }}\n$link"), "分享视频")) }
                    .onFailure { model.notice = "视频链接已复制至剪贴板" }
            }
        }
        if (controls && controlsEnabled && initialized) ReviewVideoBottom(
            Modifier.align(Alignment.BottomCenter).onSizeChanged { onControlsHeight(it.height) },
            position, duration, buffered, playing, speed, fullscreen, quality = currentQuality,
            onPlay = ::togglePlayback, onSpeed = { menu = "speed"; timer++ }, onQuality = { menu = "quality"; timer++ },
            onFullscreen = { rotate(!fullscreen) }, onSeekStart = {
                pulse(); resumeAfterScrub = wantsPlayback; scrubbing = true; wantsPlayback = false
            }, onSeek = { target -> position = target; player.seekTo(target) }, onSeekEnd = {
                scrubbing = false; wantsPlayback = resumeAfterScrub; timer++
            })
    }
    val dismiss: () -> Unit = { menu = ""; timer++ }
    if (menu == "speed") ReviewVideoChoices("播放倍速", standardVideoSpeeds.map { "${it}X" }, "${speed}X", dismiss) {
        speed = it.removeSuffix("X").toFloat(); player.setPlaybackSpeed(speed); model.notice = "已切换至 ${speed}X 倍速"
    }
    if (menu == "quality" && currentQuality != null)
        ReviewVideoChoices("清晰度选择", if (manualQualities.isNotEmpty()) manualQualities.keys.toList() else listOf("自动") + trackChoices.keys, currentQuality, dismiss) { choice ->
            if (manualQualities.isNotEmpty()) manualQualities[choice]?.let { url = it }
            else { selectVideoTrack(player, trackChoices[choice]); selectedTrack = choice }
        }
    LaunchedEffect(currentQuality) { if (currentQuality == null && menu == "quality") dismiss() }
}

@Composable
private fun VideoGestureHud(type: String, level: Float, modifier: Modifier) {
    val percentage = (level * 100).toInt()
    val color = if (type == "brightness") Color(0xFFFFD740) else Color(0xFF18FFFF)
    val icon: ImageVector = when (type) {
        "brightness" -> if (percentage > 50) Icons.Rounded.Brightness7 else Icons.Rounded.Brightness4
        "volume" -> if (percentage == 0) Icons.Rounded.VolumeOff else if (percentage > 50) Icons.Rounded.VolumeUp else Icons.Rounded.VolumeDown
        "forward" -> Icons.Rounded.Forward10
        else -> Icons.Rounded.Replay10
    }
    Row(modifier.shadow(16.dp, RoundedCornerShape(16.dp)).clip(RoundedCornerShape(16.dp)).background(Color.Black.copy(alpha = .85f))
        .border(.8.dp, Color.White.copy(alpha = .24f), RoundedCornerShape(16.dp)).padding(horizontal = 20.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        val seek = type == "forward" || type == "rewind"
        Icon(icon, null, Modifier.size(if (seek) 28.dp else 26.dp), tint = if (seek) Color.White else color)
        Spacer(Modifier.width(if (seek) 8.dp else 12.dp))
        if (!seek) {
            Canvas(Modifier.width(100.dp).height(6.dp).clip(RoundedCornerShape(4.dp))) { drawRect(Color.White.copy(alpha = .24f)); drawRect(color, size = Size(size.width * level, size.height)) }
            Spacer(Modifier.width(12.dp))
        }
        Text(if (seek) (if (type == "forward") "+10s" else "-10s") else "$percentage%", color = Color.White,
            fontSize = if (seek) 16.sp else 13.sp, fontWeight = FontWeight.Bold)
    }
}

internal fun videoTime(ms: Long) = "%02d:%02d".format(java.util.Locale.ROOT, ms / 60000 % 60, ms / 1000 % 60)
