@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.pullToRefresh
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import java.time.LocalTime
import java.time.format.DateTimeFormatter

@Composable
fun ReviewRefresh(isRefreshing: Boolean, onRefresh: () -> Unit, modifier: Modifier = Modifier,
    failed: Boolean = false, topInset: Dp = LocalContentTop.current, enabled: Boolean = true, content: @Composable BoxScope.() -> Unit) {
    val state = rememberPullToRefreshState()
    var wasRefreshing by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<String?>(null) }
    var updated by remember { mutableStateOf(LocalTime.now()) }
    LaunchedEffect(isRefreshing) {
        if (isRefreshing) { wasRefreshing = true; result = null }
        else if (wasRefreshing) {
            wasRefreshing = false
            result = if (failed) "刷新失败" else "刷新成功"
            if (!failed) updated = LocalTime.now()
            delay(1000)
            result = null
        }
    }
    val density = LocalDensity.current
    val height = with(density) { 70.dp.toPx() }
    val armed = state.distanceFraction >= 1f
    val rotation by animateFloatAsState(if (armed) -180f else 0f, tween(200), label = "refresh-arrow")
    Box(modifier.clipToBounds().pullToRefresh(isRefreshing || result != null, state, enabled = enabled, threshold = 70.dp, onRefresh = hapticClick(onRefresh))) {
        Box(Modifier.graphicsLayer { translationY = state.distanceFraction * height }, content = content)
        if (state.distanceFraction > 0f || isRefreshing || result != null) {
            Box(Modifier.fillMaxWidth().padding(top = topInset).height(70.dp).graphicsLayer {
                translationY = (state.distanceFraction * height - height).coerceAtMost(0f) / 2f
                alpha = state.distanceFraction.coerceIn(0f, 1f)
            }, contentAlignment = Alignment.Center) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.width(24.dp), contentAlignment = Alignment.Center) {
                        AnimatedContent(if (isRefreshing) "loading" else result ?: "arrow", transitionSpec = {
                            (fadeIn(tween(300)) + scaleIn(tween(300))).togetherWith(fadeOut(tween(200)) + scaleOut(tween(200)))
                        }, contentAlignment = Alignment.Center, label = "refresh-state") { phase ->
                            when (phase) {
                                "loading" -> CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onSurface)
                                "arrow" -> Icon(Icons.Outlined.ArrowDownward, null, Modifier.graphicsLayer { rotationZ = rotation })
                                else -> Icon(if (phase == "刷新失败") Icons.Outlined.ErrorOutline else Icons.Outlined.Check, null)
                            }
                        }
                    }
                    Spacer(Modifier.width(16.dp))
                    Column {
                        Text(if (isRefreshing) "正在刷新..." else result ?: if (armed) "释放立即刷新" else "下拉刷新", style = MaterialTheme.typography.titleMedium)
                        Text("最后更新于 ${updated.format(DateTimeFormatter.ofPattern("H:mm"))}", Modifier.padding(top = 4.dp), style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
}
