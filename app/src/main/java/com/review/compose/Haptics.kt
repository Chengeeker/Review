package com.review.compose

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role

internal object SilentComposeHaptics : HapticFeedback {
    override fun performHapticFeedback(hapticFeedbackType: HapticFeedbackType) = Unit
}

internal val LocalReviewHapticsEnabled = staticCompositionLocalOf<() -> Boolean> { { false } }

@Composable
internal fun reviewPulse(): () -> Unit {
    val view = LocalView.current
    val enabled = LocalReviewHapticsEnabled.current
    return remember(view, enabled) {
        { if (enabled()) view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP) }
    }
}

@Composable
internal fun hapticClick(action: () -> Unit): () -> Unit {
    val pulse = reviewPulse()
    return { pulse(); action() }
}

@Composable
internal fun <T> hapticChange(action: (T) -> Unit): (T) -> Unit {
    val pulse = reviewPulse()
    return { value -> pulse(); action(value) }
}

@Composable
internal fun Modifier.reviewClickable(enabled: Boolean = true, onClickLabel: String? = null, role: Role? = null, onClick: () -> Unit): Modifier =
    clickable(enabled = enabled, onClickLabel = onClickLabel, role = role, onClick = hapticClick(onClick))

@Composable
internal fun Modifier.reviewToggleable(value: Boolean, enabled: Boolean = true, change: (Boolean) -> Unit): Modifier =
    toggleable(value = value, enabled = enabled, role = Role.Switch, onValueChange = hapticChange(change))
