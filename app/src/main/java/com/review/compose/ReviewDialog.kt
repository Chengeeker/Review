@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package com.review.compose

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider

@Composable
fun ReviewDialog(onDismissRequest: () -> Unit, content: @Composable () -> Unit) {
    val configuration = LocalConfiguration.current
    Dialog(onDismissRequest, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        val view = LocalView.current
        SideEffect {
            (view.parent as? DialogWindowProvider)?.window?.apply {
                setWindowAnimations(R.style.ReviewDialogAnimation)
                setDimAmount(.5f)
            }
        }
        Box(Modifier.width((configuration.screenWidthDp - 80).coerceIn(1, 560).dp).heightIn(max = (configuration.screenHeightDp - 48).coerceAtLeast(1).dp)) { content() }
    }
}

@Composable
fun ReviewAlertDialog(onDismissRequest: () -> Unit, confirmButton: @Composable () -> Unit,
    dismissButton: (@Composable () -> Unit)? = null, title: (@Composable () -> Unit)? = null,
    text: (@Composable () -> Unit)? = null, shape: Shape = RoundedCornerShape(28.dp),
    contentPadding: PaddingValues = PaddingValues(start = 24.dp, top = 16.dp, end = 24.dp, bottom = 24.dp)) {
    val colors = MaterialTheme.colorScheme
    ReviewDialog(onDismissRequest) {
        Surface(shape = shape, color = colors.surfaceContainerHigh) {
            Column {
                if (title != null) Box(Modifier.padding(start = 24.dp, top = 24.dp, end = 24.dp, bottom = if (text == null) 20.dp else 0.dp)) {
                    ProvideTextStyle(MaterialTheme.typography.titleLarge.copy(fontSize = 18.sp, fontWeight = reviewWeight(FontWeight.Bold), color = colors.onSurface), title)
                }
                if (text != null) Box(Modifier.weight(1f, fill = false).padding(contentPadding)) {
                    ProvideTextStyle(MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp, color = colors.onSurfaceVariant), text)
                }
                FlowRow(Modifier.fillMaxWidth().padding(start = 24.dp, end = 24.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, androidx.compose.ui.Alignment.End)) {
                    dismissButton?.invoke(); confirmButton()
                }
            }
        }
    }
}
