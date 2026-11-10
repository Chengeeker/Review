@file:OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)

package com.review.compose

import android.graphics.Bitmap
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.key.*
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.layout.*
import androidx.compose.ui.platform.*
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.*
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlin.math.*
import kotlinx.coroutines.*

@Composable
internal fun navigationGlassMotion(
    selected: Int,
    touching: Boolean,
    dragging: Boolean,
    target: Float,
    longPressed: Boolean,
): Pair<Float, Float> {
    val held = touching && dragging
    val water = touching && longPressed
    val lens by
        animateFloatAsState(
            if (held) target else selected.toFloat(),
            glassSpring(if (held) 150 else 350, if (held) .14f else .15f),
            label = "glass-position",
        )
    val press by
        animateFloatAsState(
            if (water) 1f else 0f,
            if (water) glassSpring(300, .15f) else tween(240, easing = FastOutSlowInEasing),
            label = "glass-thickness",
        )
    return lens to press.coerceIn(0f, 1f)
}

@Composable
fun GlassNavigation(model: ReviewModel, width: Dp, icons: List<ImageVector>, activeIcons: List<ImageVector>, names: List<String>, choose: (Int) -> Unit) {
    val backdrop = LocalBackdrop.current ?: return
    val selected = model.tab
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val context = LocalContext.current
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    val owner = LocalLifecycleOwner.current
    val labelsLayer = rememberGraphicsLayer()
    val selectedLayer = rememberGraphicsLayer()
    val sceneColor = MaterialTheme.colorScheme.background
    val selectedColor = MaterialTheme.colorScheme.primary
    val unselectedColor =
        if (sceneColor.luminance() < .5f) Color.White
        else MaterialTheme.colorScheme.onSurfaceVariant
    val appFontScale = density.fontScale
    val selectedIndex by rememberUpdatedState(selected)
    val weightAdjustment = LocalWeightAdjustment.current
    var position by remember { mutableStateOf(Offset.Zero) }
    var dimensions by remember { mutableStateOf(IntSize.Zero) }
    var touching by remember { mutableStateOf(false) }
    var dragging by remember { mutableStateOf(false) }
    var longPressed by remember { mutableStateOf(false) }
    var target by remember { mutableFloatStateOf(selected.toFloat()) }
    val (logicalLens, press) = navigationGlassMotion(selected, touching, dragging, target, longPressed)
    val lens = if (rtl) 2f - logicalLens else logicalLens
    val dark = MaterialTheme.colorScheme.surface.luminance() < .5f
    val pulse = reviewPulse()
    val onChoose by rememberUpdatedState(choose)
    val labelNames = names



    Box(Modifier.width(width).height(56.dp).pointerInput(rtl, density.density) {
        coroutineScope {
            val gestureScope = this
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                val start = selectedIndex
                val tracker = VelocityTracker().apply { addPosition(down.uptimeMillis, down.position) }
                var moved = false
                var cancelled = false
                fun slot(x: Float) = (x / size.width * 3 - .5f).coerceIn(0f, 2f).let { if (rtl) 2f - it else it }
                target = slot(down.position.x)
                touching = true
                dragging = false
                longPressed = false
                val timer = gestureScope.launch {
                    delay(220)
                    longPressed = true
                    dragging = true
                    pulse()
                }
                down.consume()
                try {
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: run { cancelled = true; break }
                        if (event.changes.any { it.id != down.id && it.pressed }) {
                            cancelled = true
                            timer.cancel()
                            longPressed = false
                        }
                        tracker.addPosition(change.uptimeMillis, change.position)
                        val delta = change.position - down.position
                        if (delta.getDistance() > viewConfiguration.touchSlop) {
                            timer.cancel()
                            moved = true
                            if (abs(delta.x) > abs(delta.y)) dragging = true
                        }
                        target = slot(change.position.x)
                        change.consume()
                        if (!change.pressed) break
                    }
                    val velocity = tracker.calculateVelocity().x / density.density * if (rtl) -1 else 1
                    glassReleaseTarget(start, target.roundToInt(), velocity, longPressed, dragging, moved, cancelled)?.let { index ->
                        if (!longPressed) pulse()
                        onChoose(index)
                    }
                } finally {
                    timer.cancel()
                    touching = false
                    dragging = false
                    longPressed = false
                }
            }
        }
    }) {
        Box(Modifier.requiredSize(width + 40.dp, 86.dp).align(Alignment.Center).onGloballyPositioned {
            position = it.positionInRoot()
            dimensions = it.size
        }) {
            GlassTabLabels(width, labelNames, icons, unselectedColor, labelsLayer, false); GlassTabLabels(width, labelNames, activeIcons, selectedColor, selectedLayer, true)
            NavigationGlassMaterial(backdrop.layer, { backdrop.origin }, { backdrop.revision },
                labelsLayer, selectedLayer, lens, press, dark, sceneColor,
                model.bool("translucentNavigationGlass", false), names.size, Modifier.fillMaxSize())
        }
        Row(Modifier.fillMaxSize()) {
            names.forEachIndexed { index, label ->
                Box(Modifier.weight(1f).fillMaxHeight().semantics {
                    text = AnnotatedString(label)
                    role = Role.Tab
                    this.selected = selected == index
                    onClick { pulse(); onChoose(index); true }
                }.onKeyEvent { event ->
                    if (event.key == Key.Enter || event.key == Key.Spacebar || event.key == Key.DirectionCenter) {
                        if (event.type == KeyEventType.KeyUp) {
                            pulse()
                            onChoose(index)
                        }
                        true
                    } else false
                }.focusable())
            }
        }
    }
}

@Composable
private fun GlassTabLabels(width: Dp, names: List<String>, icons: List<ImageVector>, color: Color, layer: GraphicsLayer, selected: Boolean) {
    Box(Modifier.fillMaxSize().drawWithContent { layer.record { this@drawWithContent.drawContent() } }.clearAndSetSemantics {}) {
        Row(Modifier.align(Alignment.Center).size(width, 56.dp).padding(horizontal = 4.dp)) {
            names.forEachIndexed { index, name ->
                Column(Modifier.weight(1f).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                    Icon(icons[index], null, Modifier.size(24.dp), tint = color)
                    Spacer(Modifier.height(4.dp))
                    Text(name, fontSize = 11.sp, lineHeight = 13.sp, fontWeight = reviewWeight(if (selected) FontWeight.SemiBold else FontWeight.Medium), color = color)
                }
            }
        }
    }
}

internal suspend fun GraphicsLayer.readGlassBitmap(): Bitmap {
    val bitmap = toImageBitmap().asAndroidBitmap()
    if (bitmap.config == Bitmap.Config.ARGB_8888) return bitmap
    return try {
        withContext(Dispatchers.Default) { checkNotNull(bitmap.copy(Bitmap.Config.ARGB_8888, false)) }
    } finally { bitmap.recycle() }
}
