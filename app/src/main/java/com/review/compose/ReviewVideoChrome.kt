@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

internal val standardVideoSpeeds = listOf(3f, 2f, 1.5f, 1.25f, 1f, .75f, .5f)

@Composable
private fun videoAction(action: () -> Unit): () -> Unit = hapticClick(action)

@Composable
private fun VideoGlyph(name: String, description: String?, size: Int = 24, color: Color = Color.White) { Icon(when (name) { "arrow_back" -> Icons.AutoMirrored.Rounded.ArrowBack; "play_arrow" -> Icons.Rounded.PlayArrow; "pause" -> Icons.Rounded.Pause; "fullscreen" -> Icons.Rounded.Fullscreen; "fullscreen_exit" -> Icons.Rounded.FullscreenExit; "download" -> Icons.Rounded.Download; "share" -> Icons.Rounded.Share; "close" -> Icons.Rounded.Close; else -> Icons.Rounded.Check }, description, Modifier.size(size.dp), tint = color) }

@Composable
internal fun ReviewVideoTop(modifier: Modifier = Modifier, title: String, author: String = "",
    fullscreen: Boolean = false, close: () -> Unit, actions: @Composable RowScope.() -> Unit = {}) {
    Row(modifier.fillMaxWidth().testTag("video-top-controls")
        .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = .87f), Color.Transparent)))
        .statusBarsPadding().padding(start = if (fullscreen) 24.dp else 12.dp, top = 8.dp,
            end = if (fullscreen) 24.dp else 12.dp, bottom = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        ReviewVideoAction("arrow_back", "返回", click = close)
        Spacer(Modifier.width(4.dp))
        Column(Modifier.weight(1f)) {
            Text(title.ifBlank { "视频播放" }, color = Color.White, fontSize = 15.sp,
                fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (author.isNotBlank() && !fullscreen) Text("@${author.removePrefix("@")}", color = Color.White.copy(alpha = .7f),
                fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        actions()
    }
}

@Composable
internal fun ReviewVideoAction(icon: String, label: String, enabled: Boolean = true, busy: Boolean = false, click: () -> Unit) {
    IconButton(onClick = videoAction(click), enabled = enabled, modifier = Modifier.size(48.dp)) {
        if (busy) CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
        else VideoGlyph(icon, label, color = Color.White.copy(alpha = if (enabled) 1f else .38f))
    }
}

@Composable
internal fun ReviewVideoBottom(modifier: Modifier, position: Long, duration: Long, buffered: Long,
    playing: Boolean, speed: Float, fullscreen: Boolean = false, enabled: Boolean = true, quality: String? = null,
    onPlay: () -> Unit, onSpeed: () -> Unit, onQuality: () -> Unit = {}, onFullscreen: (() -> Unit)? = null,
    onSeekStart: () -> Unit = {}, onSeek: (Long) -> Unit, onSeekEnd: () -> Unit = {}) {
    Column(modifier.fillMaxWidth().testTag("video-bottom-controls")
        .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = .87f))))
        .navigationBarsPadding().padding(start = if (fullscreen) 28.dp else 16.dp, top = 12.dp,
            end = if (fullscreen) 28.dp else 16.dp, bottom = 12.dp)) {
        ReviewVideoTrack(position, duration, buffered, enabled, onSeekStart, onSeek, onSeekEnd)
        Spacer(Modifier.height(4.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            ReviewVideoAction(if (playing) "pause" else "play_arrow", if (playing) "暂停" else "播放", enabled, click = onPlay)
            Spacer(Modifier.width(4.dp))
            Text(buildAnnotatedString {
                withStyle(SpanStyle(color = Color.White)) { append(standardVideoTime(position)) }
                withStyle(SpanStyle(color = Color.White.copy(alpha = .38f))) { append(" / ") }
                withStyle(SpanStyle(color = Color.White.copy(alpha = .7f))) { append(standardVideoTime(duration)) }
            }, Modifier.weight(1f), fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.width(8.dp))
            ReviewVideoPill(if (speed == 1f) "倍速" else "${speed}X", "播放倍速", enabled, onSpeed)
            if (quality != null) { Spacer(Modifier.width(8.dp)); ReviewVideoPill(quality, "清晰度选择", enabled, onQuality) }
            if (onFullscreen != null) {
                Spacer(Modifier.width(8.dp))
                Box(Modifier.clip(RoundedCornerShape(12.dp)).background(Color.White.copy(alpha = .12f))
                    .border(.6.dp, Color.White.copy(alpha = .24f), RoundedCornerShape(12.dp))
                    .clickable(interactionSource = null, indication = null, role = Role.Button, onClick = videoAction(onFullscreen))
                    .padding(4.dp)) {
                    VideoGlyph(if (fullscreen) "fullscreen_exit" else "fullscreen", if (fullscreen) "退出全屏" else "全屏", 20)
                }
            }
        }
    }
}

@Composable
private fun ReviewVideoPill(label: String, description: String, enabled: Boolean, click: () -> Unit) {
    Text(label, Modifier.clip(RoundedCornerShape(12.dp)).background(Color.White.copy(alpha = .12f))
        .border(.6.dp, Color.White.copy(alpha = .24f), RoundedCornerShape(12.dp))
        .clickable(interactionSource = null, indication = null, enabled = enabled, role = Role.Button, onClick = videoAction(click))
        .semantics { contentDescription = description }.padding(horizontal = 10.dp, vertical = 4.dp),
        color = Color.White.copy(alpha = if (enabled) 1f else .38f), fontSize = 12.sp, lineHeight = 16.8.sp,
        fontWeight = FontWeight.SemiBold, maxLines = 1)
}

@Composable
internal fun ReviewVideoChoices(title: String, choices: List<String>, selected: String, dismiss: () -> Unit, choose: (String) -> Unit) {
    ModalBottomSheet(onDismissRequest = dismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        scrimColor = Color.Black.copy(alpha = .54f), tonalElevation = 0.dp,
        dragHandle = { Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.size(38.dp, 4.5.dp).clip(RoundedCornerShape(3.dp))
                .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .4f)))
        } }, shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp),
        containerColor = Color(0xFF212121), contentColor = Color.White) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(vertical = 16.dp).selectableGroup()) {
            Text(title, Modifier.padding(horizontal = 20.dp, vertical = 8.dp), fontSize = 13.sp,
                fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = .7f))
            choices.forEach { label ->
                val checked = label == selected
                Row(Modifier.fillMaxWidth().heightIn(min = 54.dp)
                    .clickable(interactionSource = null, indication = null, role = Role.RadioButton, onClick = videoAction { choose(label); dismiss() })
                    .padding(horizontal = 16.dp).semantics { this.selected = checked }, verticalAlignment = Alignment.CenterVertically) {
                    Text(label, Modifier.weight(1f), fontSize = 15.sp, lineHeight = 20.25.sp,
                        fontWeight = if (checked) FontWeight.Bold else FontWeight.Normal,
                        color = if (checked) MaterialTheme.colorScheme.primary else Color.White)
                    if (checked) VideoGlyph("check", null, 20, MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}

@Composable
private fun ReviewVideoTrack(position: Long, duration: Long, buffered: Long, enabled: Boolean,
    onStart: () -> Unit, onSeek: (Long) -> Unit, onEnd: () -> Unit) {
    var width by remember { mutableIntStateOf(1) }
    val start by rememberUpdatedState(onStart)
    val seek by rememberUpdatedState(onSeek)
    val end by rememberUpdatedState(onEnd)
    val color = MaterialTheme.colorScheme.primary
    val length = duration.coerceAtLeast(1)
    fun seekAt(x: Float) = seek((x / width * length).toLong().coerceIn(0L, length))
    val input = if (enabled && duration > 0) Modifier
        .pointerInput(duration) { detectTapGestures { start(); seekAt(it.x); end() } }
        .pointerInput(duration) { detectDragGestures(onDragStart = { start(); seekAt(it.x) },
            onDragEnd = { end() }, onDragCancel = { end() }) { change, _ -> seekAt(change.position.x); change.consume() } }
        else Modifier
    Canvas(Modifier.fillMaxWidth().height(16.dp).testTag("video-progress").onSizeChanged { width = it.width.coerceAtLeast(1) }
        .semantics {
            contentDescription = "播放进度"
            progressBarRangeInfo = ProgressBarRangeInfo(position.coerceIn(0L, length).toFloat(), 0f..length.toFloat())
            if (enabled && duration > 0) setProgress { start(); seek(it.toLong().coerceIn(0L, length)); end(); true }
        }.then(input)) {
        val track = 4.dp.toPx(); val top = (size.height - track) / 2
        fun line(fraction: Float, tint: Color) = drawRect(tint, Offset(0f, top), Size(size.width * fraction.coerceIn(0f, 1f), track))
        line(1f, Color.White.copy(alpha = .12f))
        if (duration > 0) { line(buffered.toFloat() / length, Color.White.copy(alpha = .3f)); line(position.toFloat() / length, color) }
    }
}

private fun standardVideoTime(ms: Long): String {
    val seconds = ms.coerceAtLeast(0) / 1000
    return if (seconds >= 3600) "%d:%02d:%02d".format(java.util.Locale.ROOT, seconds / 3600, seconds / 60 % 60, seconds % 60)
        else "%02d:%02d".format(java.util.Locale.ROOT, seconds / 60, seconds % 60)
}
