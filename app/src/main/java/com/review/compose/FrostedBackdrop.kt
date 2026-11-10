package com.review.compose

import android.os.Build
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.Dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay

class ReviewBackdrop(val layer: GraphicsLayer) { var origin = Offset.Zero; var revision = 0L }
val LocalBackdrop = staticCompositionLocalOf<ReviewBackdrop?> { null }
val LocalContentTop = staticCompositionLocalOf { 0.dp }

fun Modifier.recordBackdrop(backdrop: ReviewBackdrop) = onGloballyPositioned { backdrop.origin = it.positionInRoot() }.drawWithContent {
    backdrop.layer.record { this@drawWithContent.drawContent() }
    backdrop.revision++
    drawLayer(backdrop.layer)
}

@Composable
fun Modifier.frostedBackdrop(color: Color, panel: Boolean = false, blur: Dp = 20.dp, panelAlpha: Float = .82f, showBorder: Boolean = true): Modifier {
    val border = androidx.compose.material3.MaterialTheme.colorScheme.outlineVariant.copy(alpha = .24f)
    val backdrop = LocalBackdrop.current
    val sample = rememberGraphicsLayer()
    var position by remember { mutableStateOf(Offset.Zero) }
    var legacyImage by remember { mutableStateOf<ImageBitmap?>(null) }
    val capture = remember { LegacyBlurCapture() }
    val active = LocalPageActive.current
    if (Build.VERSION.SDK_INT < 31 && backdrop != null) LaunchedEffect(backdrop, active) {
        if (!active) return@LaunchedEffect
        var rendered = -1L
        while (true) {
            withFrameNanos { }
            val version = capture.revision
            if (version != rendered && capture.size.width > 0 && capture.size.height > 0) {
                val bitmap = sample.toImageBitmap()
                val blurred = withContext(Dispatchers.Default) {
                    val android = bitmap.asAndroidBitmap().copy(android.graphics.Bitmap.Config.ARGB_8888, true)
                    val pixels = IntArray(android.width * android.height)
                    android.getPixels(pixels, 0, android.width, 0, 0, android.width, android.height)
                    blurPixels(pixels, android.width, android.height, capture.radius)
                    android.setPixels(pixels, 0, android.width, 0, 0, android.width, android.height)
                    android.asImageBitmap()
                }
                legacyImage = blurred; rendered = version
            }
            delay(32)
        }
    }
    return this.onGloballyPositioned { position = it.positionInRoot() }.clipToBounds().drawWithContent {
        if (backdrop != null && Build.VERSION.SDK_INT >= 31) {
            sample.renderEffect = BlurEffect(blur.toPx(), blur.toPx(), TileMode.Clamp)
            sample.record {
                translate(backdrop.origin.x - position.x, backdrop.origin.y - position.y) { drawLayer(backdrop.layer) }
            }
            drawLayer(sample)
        } else if (backdrop != null) {
            val small = IntSize((size.width / 4).toInt().coerceAtLeast(1), (size.height / 4).toInt().coerceAtLeast(1))
            sample.record(size = small) {
                scale(.25f, .25f, Offset.Zero) { translate(backdrop.origin.x - position.x, backdrop.origin.y - position.y) { drawLayer(backdrop.layer) } }
            }
            capture.size = small; capture.radius = (blur.toPx() / 4).toInt().coerceAtLeast(1); capture.revision = backdrop.revision
            legacyImage?.let { drawImage(it, dstSize = IntSize(size.width.toInt(), size.height.toInt()), filterQuality = FilterQuality.Medium) }
        }
        drawRect(color.copy(alpha = if (panel) panelAlpha else .45f))
        if (!panel) {
            drawRect(Brush.verticalGradient(listOf(color.copy(alpha = .95f), color.copy(alpha = 0f))))
            if (showBorder) drawRect(border, topLeft = Offset(0f, size.height - .5.dp.toPx()), size = androidx.compose.ui.geometry.Size(size.width, .5.dp.toPx()))
        }
        drawContent()
    }
}

private class LegacyBlurCapture { var revision = -1L; var size = IntSize.Zero; var radius = 1 }

fun blurPixels(pixels: IntArray, width: Int, height: Int, radius: Int) {
    require(width > 0 && height > 0 && pixels.size == width * height)
    val r = radius.coerceIn(1, 64)
    val temporary = IntArray(pixels.size)
    // Three sliding box passes approximate the same Gaussian without a full-screen CPU bitmap.
    repeat(3) {
        for (vertical in listOf(false, true)) {
            val source = if (vertical) temporary else pixels
            val target = if (vertical) pixels else temporary
            val lines = if (vertical) width else height
            val length = if (vertical) height else width
            fun index(line: Int, offset: Int) = if (vertical) offset.coerceIn(0, height - 1) * width + line else line * width + offset.coerceIn(0, width - 1)
            for (line in 0 until lines) {
                var a = 0; var red = 0; var green = 0; var blue = 0
                for (n in -r..r) { val c = source[index(line, n)]; a += c ushr 24; red += c shr 16 and 255; green += c shr 8 and 255; blue += c and 255 }
                val count = r * 2 + 1
                for (n in 0 until length) {
                    target[index(line, n)] = (a / count shl 24) or (red / count shl 16) or (green / count shl 8) or (blue / count)
                    val remove = source[index(line, n - r)]; val add = source[index(line, n + r + 1)]
                    a += (add ushr 24) - (remove ushr 24); red += (add shr 16 and 255) - (remove shr 16 and 255)
                    green += (add shr 8 and 255) - (remove shr 8 and 255); blue += (add and 255) - (remove and 255)
                }
            }
        }
    }
}
