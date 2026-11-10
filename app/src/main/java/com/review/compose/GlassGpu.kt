package com.review.compose

import android.content.Context
import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import androidx.annotation.RequiresApi
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

@RequiresApi(33)
internal class GlassOptics(context: Context) {
    val shader =
        RuntimeShader(
            context.assets.open("glass/liquid_glass.agsl").bufferedReader().use { it.readText() }
        )

    fun configure(
        size: Size,
        shape: Rect,
        density: Float,
        dark: Boolean,
        lens: Boolean = false,
        pressed: Float = 0f,
        dragging: Boolean = false,
        kind: Int = 0,
        touch: Float = 0f,
    ) {
        val fade = if (lens) pressed.coerceIn(.001f, 1f) else 1f
        val dpr = density / 3f
        val ri = if (lens) 1f + .18f * fade else if (kind == 1) 1.24f else 1.16f
        val thickness = (if (lens) 20f * fade else if (kind == 1) 32f else 10f) * dpr
        val rgb =
            if (lens) {
                if (dark) 1f else 0f
            } else {
                if (dark || kind == 1) 0f else 1f
            }
        shader.apply {
            setFloatUniform("uSize", size.width, size.height)
            setFloatUniform("shape", shape.center.x, shape.center.y, shape.width, shape.height)
            setFloatUniform("uGeometryOffset", shape.left, shape.top)
            setFloatUniform("uGeometrySize", shape.width, shape.height)
            setFloatUniform(
                "uGlassColor",
                rgb,
                rgb,
                rgb,
                (if (lens) {
                    if (dark) 38f / 255 else 24f / 255
                } else {
                    if (dark || kind == 1) .4f else 240f / 255
                }) * fade,
            )
            setFloatUniform(
                "uOpticalProps",
                ri,
                if (lens || kind == 1) .025f * fade else .008f,
                thickness,
                1f,
            )
            setFloatUniform(
                "uLightConfig",
                (if (lens) 2f else .25f) * fade,
                0f,
                if (lens || kind == 1) 1.5f else 1f,
            )
            setFloatUniform("uLightDirection", -.7071068f, .7071068f)
            setFloatUniform("uWhiten", 0f)
            setFloatUniform("uWhitenGated", 1f)
            setFloatUniform(
                "uPinchStrength",
                if (lens && dragging) .7f * (1 - (1 - fade) * (1 - fade)) else 0f,
            )
            setFloatUniform("uBackgroundFallback", 0f, 0f, 0f, 0f)
            setFloatUniform("uCaptureOffset", 0f, 0f)
            setFloatUniform("uEdgeConfig", 0f, fade, dpr, 0f)
            setFloatUniform("uPlatformViewMode", 0f)
            setFloatUniform("uBodyMode", 1f)
            setFloatUniform("uTouchPosition", shape.center.x, shape.center.y)
            setFloatUniform("uTouchIntensity", (if (kind == 1) touch else pressed) * .125f)
            setFloatUniform(
                "uRimConfig",
                if (lens && !dark) .12f * fade else 0f,
                (if (kind == 1) 0f
                else if (dark) {
                    if (lens || kind == 3) 0f else .12f
                } else {
                    if (lens) .35f else 1f
                }) * fade,
                .2f,
            )
            setFloatUniform("uLensModel", 0f)
            setFloatUniform("uFrost", 0f, 0f, 0f, 1f)
            setFloatUniform("uBodyShade", 0f)
            setFloatUniform("uNativeEdge", if (!dark && lens) 1f else 0f)
        }
    }

    fun effect(): androidx.compose.ui.graphics.RenderEffect =
        RenderEffect.createRuntimeShaderEffect(shader, "background").asComposeRenderEffect()
}

@RequiresApi(33)
@Composable
internal fun GlassNavigationGpu(
    backdrop: ReviewBackdrop,
    labels: GraphicsLayer,
    activeLabels: GraphicsLayer,
    lens: Float,
    pressed: Float,
    dark: Boolean,
    sceneColor: Color,
    modifier: Modifier,
    onFailure: () -> Unit,
) {
    val context = LocalContext.current
    val optics = remember {
        runCatching { GlassOptics(context) to GlassOptics(context) }.getOrNull()
    }
    if (optics == null) {
        LaunchedEffect(Unit) { onFailure() }
        return
    }
    val crop = rememberGraphicsLayer()
    val blurred = rememberGraphicsLayer()
    val body = rememberGraphicsLayer()
    val underPill = rememberGraphicsLayer()
    val pillBlur = rememberGraphicsLayer()
    val combined = rememberGraphicsLayer()
    val water = rememberGraphicsLayer()
    var origin by remember { mutableStateOf(Offset.Zero) }
    var velocity by remember { mutableFloatStateOf(0f) }
    val currentLens by rememberUpdatedState(lens)
    val hasWater = pressed > .001f
    LaunchedEffect(hasWater) {
        if (!hasWater) velocity = 0f
        else {
            var lastFrame = withFrameNanos { it }
            var lastLens = currentLens
            while (true) {
                val frame = withFrameNanos { it }
                velocity = (currentLens - lastLens) * 1_000_000_000f / (frame - lastFrame)
                lastFrame = frame
                lastLens = currentLens
            }
        }
    }
    val density = androidx.compose.ui.platform.LocalDensity.current.density
    val bodyBlur = remember(density) { navBlurEffect(1.5f * density) }
    val frostBlur = remember(density) { navBlurEffect(6f * density) }
    val bodyEffects =
        remember(dark, density) { mutableMapOf<Size, androidx.compose.ui.graphics.RenderEffect>() }
    Box(
        modifier
            .onGloballyPositioned { origin = it.positionInRoot() }
            .drawWithCache {
                val w = size.width
                val h = size.height
                val d = density
                val dimensions = IntSize(w.roundToInt(), h.roundToInt())
                val bar = Rect(20 * d, 15 * d, w - 20 * d, h - 15 * d)
                val slot = (bar.width - 8 * d) / 3f
                val cx = 24 * d + slot * (lens + .5f)
                val jelly = jellyScale(velocity, pressed)
                val lw = (slot * (1 + .06f * pressed) + 24 * d * pressed) * jelly[0]
                val lh = (48 * d * (1 + .06f * pressed) + 16 * d * pressed) * jelly[1]
                val pill = Rect(cx - lw / 2, h / 2 - lh / 2, cx + lw / 2, h / 2 + lh / 2)
                val mask =
                    Path().apply { addRoundRect(RoundRect(pill, CornerRadius(minOf(lw, lh) / 2))) }
                val resting = 1f - pressed
                blurred.renderEffect = bodyBlur
                pillBlur.renderEffect = frostBlur
                pillBlur.alpha = resting
                body.renderEffect =
                    bodyEffects[size]
                        ?: run {
                            bodyEffects.clear()
                            optics.first.configure(size, bar, d, dark)
                            optics.first.effect().also { bodyEffects[size] = it }
                        }
                water.alpha = pressed
                if (hasWater) {
                    optics.second.configure(
                        size,
                        pill,
                        d,
                        dark,
                        lens = true,
                        pressed = pressed,
                        dragging = true,
                    )
                    water.renderEffect = optics.second.effect()
                }
                onDrawBehind {
                    // Retain GPU display lists; never read these layers into CPU bitmaps.
                    crop.record(this, layoutDirection, dimensions) {
                        drawRect(sceneColor)
                        translate(backdrop.origin.x - origin.x, backdrop.origin.y - origin.y) {
                            drawLayer(backdrop.layer)
                        }
                    }
                    blurred.record(this, layoutDirection, dimensions) { drawLayer(crop) }
                    body.record(this, layoutDirection, dimensions) { drawLayer(blurred) }
                    underPill.record(this, layoutDirection, dimensions) {
                        drawLayer(crop)
                        drawLayer(body)
                    }
                    pillBlur.record(this, layoutDirection, dimensions) { drawLayer(underPill) }
                    combined.record(this, layoutDirection, dimensions) {
                        drawLayer(body)
                        if (resting > .001f)
                            clipPath(mask) {
                                drawLayer(pillBlur)
                                drawRect(
                                    (if (dark) Color.White else Color.Black).copy(
                                        alpha = 38f / 255 * resting
                                    )
                                )
                            }
                        clipPath(mask, ClipOp.Difference) { drawLayer(labels) }
                        clipPath(mask) { drawLayer(activeLabels) }
                    }
                    drawLayer(combined)
                    if (hasWater) {
                        water.record(this, layoutDirection, dimensions) {
                            drawLayer(crop)
                            drawLayer(combined)
                        }
                        drawLayer(water)
                    }
                }
            }
    )
}

private fun navBlurEffect(sigma: Float): BlurEffect {
    val radius = maxOf(.01f, (sigma - .5f) / .57735f)
    return BlurEffect(radius, radius, TileMode.Clamp)
}
