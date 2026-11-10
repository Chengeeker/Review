package com.review.compose

import android.graphics.Bitmap
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.unit.Dp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.abs

internal data class GalleryAnchor(val bounds: Rect, val visible: Rect)
internal data class GalleryPlane(val bitmap: Bitmap, val rect: Rect, val viewport: Rect)
internal data class GalleryFlight(val source: GalleryOrigin, val anchor: GalleryAnchor, val plane: GalleryPlane)

internal class GalleryOrigin(val radius: Dp, val crop: Boolean = true) {
    var coordinates: LayoutCoordinates? = null
    var bitmap: Bitmap? = null
    var covered by mutableStateOf(false)

    fun anchor(): GalleryAnchor? {
        val layout = coordinates?.takeIf { it.isAttached } ?: return null
        val screen = layout.positionOnScreen().takeIf { it.isSpecified } ?: return null
        val visible = layout.boundsInWindow().translate(screen - layout.positionInWindow())
        return GalleryAnchor(Rect(screen, Size(layout.size.width.toFloat(), layout.size.height.toFloat())), visible)
            .takeUnless { it.visible.isEmpty }
    }
}

internal fun galleryImagePlane(bounds: Rect, image: Size, crop: Boolean): Rect {
    if (bounds.isEmpty || image.width <= 0 || image.height <= 0) return bounds
    val x = bounds.width / image.width
    val y = bounds.height / image.height
    val scale = if (crop) maxOf(x, y) else minOf(x, y)
    val half = Offset(image.width * scale / 2, image.height * scale / 2)
    return Rect(bounds.center - half, bounds.center + half)
}

@Composable
internal fun GalleryFlightImage(flight: GalleryFlight, screenOrigin: Offset, position: Float) {
    val bitmap = remember(flight.plane.bitmap) { flight.plane.bitmap.asImageBitmap() }
    Canvas(Modifier.fillMaxSize()) {
        val fraction = FastOutSlowInEasing.transform(position)
        val source = flight.anchor.bounds.translate(-screenOrigin)
        val visible = flight.anchor.visible.translate(-screenOrigin)
        val destination = flight.plane.rect.translate(-screenOrigin)
        val viewport = flight.plane.viewport.translate(-screenOrigin)
        val destinationClip = destination.intersect(viewport).takeUnless { it.isEmpty } ?: viewport
        val sourcePlane = galleryImagePlane(source, Size(bitmap.width.toFloat(), bitmap.height.toFloat()), crop = flight.source.crop)
        val image = lerp(sourcePlane, destination, fraction)
        val frame = lerp(source, destinationClip, fraction)
        val clip = lerp(visible, destinationClip, fraction)
        val radius = (flight.source.radius.toPx() * (1f - fraction)).coerceAtMost(minOf(frame.width, frame.height) / 2)
        clipRect(clip.left, clip.top, clip.right, clip.bottom) {
            clipPath(Path().apply { addRoundRect(RoundRect(frame, CornerRadius(radius))) }) {
                translate(image.left, image.top) {
                    scale(image.width / bitmap.width, image.height / bitmap.height, Offset.Zero) { drawImage(bitmap) }
                }
            }
        }
    }
}

// The Lurk motion loop reverses direction without replacing the current frame.
internal class GalleryOpeningMotion(private val scope: CoroutineScope, initial: Float) {
    private var job: Job? = null
    private var onClosed: (() -> Unit)? = null
    var position by mutableFloatStateOf(initial)
        private set
    var returning by mutableStateOf(false)
        private set
    var holdingGesture by mutableStateOf(false)

    fun open() { onClosed = null; returning = false; drive() }
    fun finishOpening() { job?.cancel(); onClosed = null; returning = false; position = 1f }
    fun returnToSource(onClosed: () -> Unit) { this.onClosed = onClosed; returning = true; drive() }

    private fun drive() {
        if (job?.isActive == true) return
        job = scope.launch {
            val durationScale = coroutineContext[MotionDurationScale]
            var previousFrame: Long? = null
            while (isActive) {
                if (position == if (returning) 0f else 1f) {
                    if (!returning) break
                    snapshotFlow { !holdingGesture || !returning }.first { it }
                    if (returning) { onClosed?.invoke(); break }
                    previousFrame = null
                }
                withFrameNanos { frame ->
                    val scale = durationScale?.scaleFactor ?: 1f
                    val duration = (if (returning) 200f else 330f) * 1_000_000f
                    val step = if (scale == 0f) 1f else (frame - (previousFrame ?: frame)) / (duration * scale)
                    position = (position + if (returning) -step else step).coerceIn(0f, 1f)
                    previousFrame = frame
                }
            }
        }
    }
}

internal fun Modifier.galleryOverlayInput(
    target: () -> Rect?, canSwipe: () -> Boolean, hold: (Boolean) -> Unit,
    reopen: () -> Unit, swipe: (Float) -> Unit,
): Modifier = pointerInput(Unit) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        if (down.isConsumed) return@awaitEachGesture
        val landing = target()?.takeIf { it.contains(down.position) }
        var tap = landing != null
        var waitingSwipe = canSwipe()
        if (!tap && !waitingSwipe) return@awaitEachGesture
        down.consume()
        hold(true)
        try {
            do {
                val event = awaitPointerEvent(PointerEventPass.Initial)
                val change = event.changes.firstOrNull { it.id == down.id }
                if (change == null || change.isConsumed || event.changes.any { it.id != down.id && it.pressed }) {
                    tap = false; waitingSwipe = false
                } else {
                    val delta = change.position - down.position
                    val slop = viewConfiguration.touchSlop
                    val dx = abs(delta.x); val dy = abs(delta.y)
                    if (delta.getDistance() > slop || landing?.contains(change.position) != true) tap = false
                    if (waitingSwipe && dx >= slop * 1.5f && dx > dy * 1.25f) {
                        waitingSwipe = false; tap = false; swipe(delta.x)
                    } else if (dy >= slop * 2 && dy > dx) waitingSwipe = false
                    if (tap && change.changedToUpIgnoreConsumed()) { tap = false; reopen() }
                }
                if (!tap && !waitingSwipe) hold(false)
                event.changes.forEach { it.consume() }
            } while (event.changes.any { it.pressed })
        } finally { hold(false) }
    }
}
