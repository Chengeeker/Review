package com.review.compose

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.BiasAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import kotlinx.coroutines.delay

@Composable
internal fun VideoHintOverlay(player: Player, visible: Boolean, speed: Boolean = true, inset: Dp = 0.dp, contentKey: Any? = null, content: @Composable () -> Unit) {
    var ratio by remember(player) { mutableFloatStateOf(0f) }
    DisposableEffect(player) {
        fun update(size: VideoSize) { ratio = if (size.height > 0) size.width * size.pixelWidthHeightRatio / size.height else 0f }
        update(player.videoSize)
        val listener = object : Player.Listener { override fun onVideoSizeChanged(videoSize: VideoSize) { update(videoSize) } }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(visible, speed, contentKey) {
        shown = visible
        if (visible && speed) { delay(900); shown = false }
    }
    if (visible && shown) BoxWithConstraints(Modifier.fillMaxSize()) {
        val topSpace = if (ratio > 0f) inset + ((maxHeight - inset * 2 - maxWidth / ratio) / 2).coerceAtLeast(0.dp) else 0.dp
        Box(if (topSpace >= 144.dp) Modifier.align(Alignment.TopCenter).height(topSpace).padding(top = 56.dp)
            else Modifier.align(BiasAlignment(0f, -.5f)), contentAlignment = Alignment.Center) { content() }
    }
}
