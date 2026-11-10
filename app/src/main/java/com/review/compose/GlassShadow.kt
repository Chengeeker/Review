package com.review.compose

import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp

internal data class GlassShadow(val blur: Float, val offset: Float, val color: Color)

internal fun Modifier.glassEdgeShadow(vararg shadows: GlassShadow, cornerRadius: Dp? = null, clearCenter: Boolean = true): Modifier = drawWithCache {
    val pad = 20.dp.roundToPx()
    val pixels =
        Bitmap.createBitmap(
            size.width.toInt() + 2 * pad,
            size.height.toInt() + 2 * pad,
            Bitmap.Config.ARGB_8888,
        )
    val canvas = android.graphics.Canvas(pixels)
    val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
    val radius = cornerRadius?.toPx() ?: (size.height * .5f)
    shadows.forEach { shadow ->
        val dy = shadow.offset.dp.toPx()
        paint.color = shadow.color.toArgb()
        paint.maskFilter =
            BlurMaskFilter((shadow.blur * .57735f + .5f).dp.toPx(), BlurMaskFilter.Blur.NORMAL)
        canvas.drawRoundRect(
            pad.toFloat(),
            pad + dy,
            pad + size.width,
            pad + size.height + dy,
            radius,
            radius,
            paint,
        )
    }
    paint.maskFilter = null
    if (clearCenter) {
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
        canvas.drawRoundRect(
            pad.toFloat(), pad.toFloat(), pad + size.width, pad + size.height,
            radius, radius, paint,
        )
    }
    val image = pixels.asImageBitmap()
    onDrawBehind { drawImage(image, topLeft = Offset(-pad.toFloat(), -pad.toFloat())) }
}
