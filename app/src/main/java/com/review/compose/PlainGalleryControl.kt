package com.review.compose

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.*
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp

@Composable
internal fun PlainGalleryControl(label: String?, enabled: Boolean, onClick: () -> Unit, content: @Composable () -> Unit) {
    val interaction = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val background by animateColorAsState(
        if (pressed && enabled) Color.Black.copy(alpha = .28f) else Color.Black.copy(alpha = .40f),
        tween(durationMillis = 100, easing = LinearEasing),
        label = "gallery-button-press",
    )
    Box(Modifier.size(48.dp).clip(CircleShape)
        .clickable(interactionSource = interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
        .semantics { if (label != null) contentDescription = label }, contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxSize().background(background, CircleShape)
            .border(.5.dp, Color.White.copy(alpha = .24f), CircleShape))
        content()
    }
}
