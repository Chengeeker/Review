package com.review.compose

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.LayoutDirection
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner

val LocalPageActive = staticCompositionLocalOf { true }
val LocalReviewRoute = staticCompositionLocalOf<ReviewRoute?> { null }

private class PageLifecycle : LifecycleOwner {
    override val lifecycle = LifecycleRegistry(this)
}

@Composable
fun PageStack(routes: List<ReviewRoute>, content: @Composable (ReviewRoute) -> Unit) {
    val mounted = remember(routes.firstOrNull()?.key) { mutableStateListOf<ReviewRoute>().apply { addAll(routes) } }
    val liveKeys = routes.map { it.key }
    SideEffect { routes.forEach { if (it !in mounted) mounted.add(it) } }
    val host = LocalLifecycleOwner.current
    val direction = if (LocalLayoutDirection.current == LayoutDirection.Rtl) -1 else 1
    BoxWithConstraints(Modifier.fillMaxSize().clipToBounds()) {
        val width = constraints.maxWidth.toFloat()
        mounted.toList().forEach { route -> key(route.key) {
            val live = route.key in liveKeys
            val active = live && route.key == liveKeys.lastOrNull()
            val offset = remember { Animatable(if (route.name == "root") 0f else 1f) }
            val owner = remember { PageLifecycle() }
            val currentActive by rememberUpdatedState(active)
            DisposableEffect(host, owner) {
                fun sync() { owner.lifecycle.currentState = if (currentActive) host.lifecycle.currentState else minOf(host.lifecycle.currentState, Lifecycle.State.CREATED) }
                val observer = LifecycleEventObserver { _, _ -> sync() }
                host.lifecycle.addObserver(observer); sync()
                onDispose { host.lifecycle.removeObserver(observer); owner.lifecycle.currentState = Lifecycle.State.DESTROYED }
            }
            SideEffect { owner.lifecycle.currentState = if (active) host.lifecycle.currentState else minOf(host.lifecycle.currentState, Lifecycle.State.CREATED) }
            LaunchedEffect(live, route.backProgress) {
                if (live && route.backProgress != null) offset.snapTo(route.backProgress!!.coerceIn(0f, 1f))
                else if (live) offset.animateTo(0f, tween(320, easing = CubicBezierEasing(.215f, .61f, .355f, 1f)))
                else { offset.animateTo(1f, tween(220, easing = CubicBezierEasing(.55f, .055f, .675f, .19f))); mounted.remove(route) }
            }
            Box(Modifier.fillMaxSize().graphicsLayer { translationX = offset.value * width * direction }
                .then(if (active) Modifier else Modifier.clearAndSetSemantics {})) {
                CompositionLocalProvider(LocalLifecycleOwner provides owner, LocalPageActive provides active, LocalReviewRoute provides route) { content(route) }
            }
        } }
    }
}
