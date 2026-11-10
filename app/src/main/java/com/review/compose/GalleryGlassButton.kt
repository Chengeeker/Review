package com.review.compose

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.*
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import kotlin.math.abs

// Same 48dp button resistance and anchored stretch as LiquidStretch (MIT, bundled library).
fun glassButtonStretch(drag: Offset): FloatArray {
    val offset = drag / (1f + drag.getDistance() * .01f) * .8f
    val x = abs(offset.x) / 48f; val y = abs(offset.y) / 48f
    fun pivot(value: Float): Float {
        val t = (abs(value) / 20f).coerceIn(0f, 1f)
        return .5f - kotlin.math.sign(value) * t * t * (3f - 2f * t) * .5f
    }
    return floatArrayOf((1f + (x * .8f).coerceAtMost(.3f)) * (1f - (y * .3f).coerceAtMost(.15f)),
        (1f + (y * .8f).coerceAtMost(.3f)) * (1f - (x * .3f).coerceAtMost(.15f)),
        pivot(offset.x), pivot(offset.y), offset.x * .15f, offset.y * .15f)
}

@Composable
fun GalleryGlassButton(icon: ImageVector, label: String, enabled: Boolean = true, busy: Boolean = false, click: () -> Unit) {
    val model = LocalReview.current
    val liquid = model.bool("liquidGlass")
    if (!liquid) {
        PlainGalleryControl(label, enabled, hapticClick(click)) {
            if (busy) CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
            else Icon(icon, null, Modifier.size(24.dp), tint = Color.White.copy(alpha = if (enabled) 1f else .38f))
        }
        return
    }
    val density = LocalDensity.current.density
    var pressed by remember { mutableStateOf(false) }
    var drag by remember { mutableStateOf(Offset.Zero) }
    val invoke by rememberUpdatedState(hapticClick(click))
    val growth by animateFloatAsState(if (pressed && liquid) 1f else 0f, spring(dampingRatio = .65f, stiffness = 450f), label = "gallery-glass-press")
    val x by animateFloatAsState(drag.x, spring(dampingRatio = .8f, stiffness = 550f), label = "gallery-glass-x")
    val y by animateFloatAsState(drag.y, spring(dampingRatio = .8f, stiffness = 550f), label = "gallery-glass-y")
    Box(Modifier.size(48.dp).semantics {
        contentDescription = label; role = Role.Button
        if (!enabled) disabled()
        onClick { if (enabled) invoke(); enabled }
    }.onKeyEvent { event ->
        if (enabled && event.key in listOf(Key.Enter, Key.Spacebar, Key.DirectionCenter)) {
            if (event.type == KeyEventType.KeyUp) invoke()
            true
        } else false
    }.focusable(enabled).pointerInput(enabled, liquid, density) {
        if (!enabled) return@pointerInput
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            down.consume(); pressed = true
            var moved = false; var cancelled = false
            try {
                while (true) {
                    val event = awaitPointerEvent()
                    val pointer = event.changes.firstOrNull { it.id == down.id } ?: break
                    if (event.changes.any { it.id != down.id && it.pressed }) cancelled = true
                    val delta = pointer.position - down.position
                    moved = moved || delta.getDistance() > viewConfiguration.touchSlop
                    if (liquid) drag = delta / density
                    pointer.consume()
                    if (!pointer.pressed) {
                        if (!cancelled && !moved && (!liquid || pointer.uptimeMillis - down.uptimeMillis < viewConfiguration.longPressTimeoutMillis)) {
                            invoke()
                        }
                        break
                    }
                }
            } finally { pressed = false; drag = Offset.Zero }
        }
    }, contentAlignment = Alignment.Center) {
        Box(Modifier.size(48.dp).graphicsLayer {
            val stretch = glassButtonStretch(Offset(x, y))
            val scale = 1f + 17f / 48f * growth
            scaleX = scale * stretch[0]; scaleY = scale * stretch[1]
            transformOrigin = TransformOrigin(stretch[2], stretch[3])
            translationX = stretch[4] * density; translationY = stretch[5] * density
        }.liquidBackdrop(Color(0x66000000), pressed = growth, button = true), contentAlignment = Alignment.Center) {
            if (busy) CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
            else Icon(icon, null, Modifier.size(22.dp), tint = Color.White)
        }
    }
}
