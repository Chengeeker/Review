package com.review.compose

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import kotlinx.coroutines.delay

@Composable
fun ReviewToast(message: String?, revision: Int, dark: Boolean, dismiss: () -> Unit) {
    if (message == null) return
    val alpha = remember { Animatable(0f) }
    val latestDismiss by rememberUpdatedState(dismiss)
    LaunchedEffect(message, revision) {
        alpha.snapTo(0f)
        alpha.animateTo(1f, tween(100, easing = CubicBezierEasing(0f, 0f, .58f, 1f)))
        delay(2500)
        alpha.animateTo(0f, tween(100, easing = CubicBezierEasing(0f, 0f, .58f, 1f)))
        latestDismiss()
    }
    val density = LocalDensity.current
    val bottom = maxOf(WindowInsets.navigationBars.getBottom(density), WindowInsets.ime.getBottom(density)) + with(density) { 84.dp.roundToPx() }
    Popup(alignment = Alignment.BottomCenter, offset = IntOffset(0, -bottom), properties = PopupProperties(focusable = false, dismissOnBackPress = false, dismissOnClickOutside = false, clippingEnabled = false)) {
        Box(Modifier.fillMaxWidth().padding(horizontal = 24.dp), contentAlignment = Alignment.Center) {
            val shape = RoundedCornerShape(24.dp)
            Text(message, Modifier.widthIn(max = 340.dp).graphicsLayer { this.alpha = alpha.value }
                .dropShadow(shape, Shadow(radius = 16.dp, color = Color.Black.copy(alpha = .3f), offset = DpOffset(0.dp, 4.dp)))
                .background(if (dark) Color(0xFF2C2D35).copy(alpha = .96f) else Color(0xFF1E1E24).copy(alpha = .94f), shape)
                .padding(horizontal = 18.dp, vertical = 10.dp).semantics { liveRegion = LiveRegionMode.Polite },
                color = Color.White, fontSize = 13.5.sp, lineHeight = 16.875.sp, fontWeight = reviewWeight(FontWeight.Medium), textAlign = TextAlign.Center)
        }
    }
}
