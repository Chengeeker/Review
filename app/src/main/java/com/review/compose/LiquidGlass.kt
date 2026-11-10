package com.review.compose

import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.abs

@RequiresApi(33)
fun glassShader(context: android.content.Context) = RuntimeShader(context.assets.open("glass/premium_glass.agsl").bufferedReader().use { it.readText() })

@RequiresApi(33)
fun configureGlass(shader: RuntimeShader, size: androidx.compose.ui.geometry.Size, shape: androidx.compose.ui.geometry.Rect,
    density: Float, tint: Color, dark: Boolean, indicator: Boolean, pressed: Float, opacity: Float, fallback: Color,
    pinchSize: androidx.compose.ui.geometry.Size = size, button: Boolean = false, plainButton: Boolean = false) {
    val fade = pressed.coerceIn(0f, 1f)
    shader.setFloatUniform("uSize", size.width, size.height)
    shader.setFloatUniform("uShapeRect", shape.left, shape.top, shape.width, shape.height)
    shader.setFloatUniform("uGeometryOffset", shape.left, shape.top)
    shader.setFloatUniform("uGeometrySize", shape.width, shape.height)
    shader.setFloatUniform("uGlassColor", tint.red, tint.green, tint.blue, tint.alpha)
    shader.setFloatUniform("uOpticalProps", if (button) 1.24f else if (indicator) 1.18f else 1.19f, if (indicator || button) .025f else .008f, (if (button) 32f else if (indicator) 20f else 10f) * density / 3f, 1f)
    shader.setFloatUniform("uLightConfig", if (indicator) 2f else .25f, 0f, 1.5f)
    shader.setFloatUniform("uLightDirection", -.7071068f, -.7071068f)
    shader.setFloatUniform("uEdgeConfig", 0f, 1f, density / 3f, 0f)
    shader.setFloatUniform("uRimConfig", if (indicator && !dark) .12f else 0f, if (dark || button) 0f else if (indicator) .35f else 1f, .2f)
    shader.setFloatUniform("uPinchStrength", if (indicator) (1f - (1f - fade) * (1f - fade)) * .7f else 0f)
    shader.setFloatUniform("uPinchSize", pinchSize.width, pinchSize.height)
    shader.setFloatUniform("uBackgroundFallback", fallback.red, fallback.green, fallback.blue, fallback.alpha)
    shader.setFloatUniform("uCaptureOffset", 0f, 0f)
    shader.setFloatUniform("uBodyMode", 1f)
    shader.setFloatUniform("uWhiten", 0f)
    shader.setFloatUniform("uWhitenGated", if (dark) 0f else 1f)
    shader.setFloatUniform("uTouchPosition", shape.center.x, shape.center.y)
    shader.setFloatUniform("uTouchIntensity", fade * (32f / 255f))
    shader.setFloatUniform("uPlatformViewMode", 0f)
    shader.setFloatUniform("uLensModel", 0f)
    shader.setFloatUniform("uFrost", 0f, 0f, 0f, 1f)
    shader.setFloatUniform("uBodyShade", 0f)
    shader.setFloatUniform("uOpacity", opacity.coerceIn(0f, 1f))
    shader.setFloatUniform("uPlainButton", if (plainButton) 1f else 0f)
}

@Composable
fun Modifier.liquidBackdrop(tint: Color, indicator: Boolean = false, pressed: Float = 0f,
    blur: Dp = if (indicator) 0.dp else 2.dp, opacity: Float = 1f, source: ReviewBackdrop? = LocalBackdrop.current,
    button: Boolean = false, plainButton: Boolean = false): Modifier {
    val context = LocalContext.current
    val shader = remember { if (Build.VERSION.SDK_INT >= 33) runCatching { glassShader(context) }.getOrNull() else null }
    if (shader == null) return clip(RoundedCornerShape(50)).frostedBackdrop(tint.copy(alpha = tint.alpha * opacity), panel = true, blur = blur, panelAlpha = tint.alpha * opacity)
    val root = LocalBackdrop.current
    val sample = rememberGraphicsLayer()
    var position by remember { mutableStateOf(Offset.Zero) }
    val fallback = if (button || plainButton) Color.Black else MaterialTheme.colorScheme.background
    val dark = fallback.luminance() < .5f
    return onGloballyPositioned { position = it.positionInRoot() }.drawWithContent {
        if (source != null && Build.VERSION.SDK_INT >= 33 && size.width > 0 && size.height > 0 && opacity > 0f) {
            // Capture beyond the silhouette so blur/refraction never clamp against a cropped pill edge.
            val pad = 20.dp.toPx()
            val captureSize = androidx.compose.ui.unit.IntSize(kotlin.math.ceil(size.width + pad * 2).toInt(), kotlin.math.ceil(size.height + pad * 2).toInt())
            configureGlass(shader, androidx.compose.ui.geometry.Size(captureSize.width.toFloat(), captureSize.height.toFloat()),
                androidx.compose.ui.geometry.Rect(pad, pad, pad + size.width, pad + size.height), density, tint, dark, indicator, pressed, opacity, fallback,
                androidx.compose.ui.geometry.Size(source.layer.size.width + 40.dp.toPx(), source.layer.size.height + 30.dp.toPx()), button, plainButton)
            val refract = RenderEffect.createRuntimeShaderEffect(shader, "background")
            sample.renderEffect = (if (blur.value > 0) RenderEffect.createChainEffect(refract, RenderEffect.createBlurEffect(blur.toPx(), blur.toPx(), Shader.TileMode.CLAMP)) else refract).asComposeRenderEffect()
            sample.record(size = captureSize) {
                drawRect(fallback)
                if (root != null && root !== source) translate(root.origin.x - position.x + pad, root.origin.y - position.y + pad) { drawLayer(root.layer) }
                translate(source.origin.x - position.x + pad, source.origin.y - position.y + pad) { drawLayer(source.layer) }
            }
            translate(-pad, -pad) { drawLayer(sample) }
        }
        drawContent()
    }
}
fun glassReleaseTarget(start: Int, proposed: Int, velocity: Float, longPress: Boolean, dragged: Boolean, vertical: Boolean, cancelled: Boolean): Int? {
    if (cancelled || (vertical && !dragged)) return null
    val target = if (dragged && abs(velocity) >= 1000f) (start + if (velocity > 0) 1 else -1).coerceIn(0, 2) else proposed.coerceIn(0, 2)
    return if ((longPress || dragged) && target == start) null else target
}
