package com.review.compose

import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.RadioButtonChecked
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

fun refreshRateTitles(width: Int, height: Int): List<String> {
    val native = if (width > 0 && height > 0) "${width}x$height" else "1260x2800"
    val fhd = if (width > 0 && height > 0) "1080x${(height * 1080f / width).roundToInt()}" else "1080x2400"
    return listOf("自动") + (1..8).map { "#$it ${if (it <= 4) native else fhd} @ ${listOf(120, 90, 72, 60)[(it - 1) % 4]}Hz" }
}

@Composable
fun RefreshRateScreen() {
    val model = LocalReview.current
    val activity = LocalActivity.current ?: return
    val colors = MaterialTheme.colorScheme
    val mode = remember(activity) { activity.windowManager.defaultDisplay.supportedModes.maxByOrNull { it.physicalWidth } }
    val titles = remember(mode) { refreshRateTitles(mode?.physicalWidth ?: 0, mode?.physicalHeight ?: 0) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 12.dp + LocalContentTop.current, bottom = 36.dp)) {
        Text("没有生效？重启app试试", Modifier.padding(start = 8.dp, top = 4.dp, bottom = 12.dp), fontSize = 13.sp, color = colors.primary.copy(alpha = .85f), fontWeight = reviewWeight(FontWeight.Medium))
        SettingsCard { titles.forEachIndexed { index, title ->
            val selected = model.number("refreshRate", 0f).toInt() == index
            Row(Modifier.fillMaxWidth().reviewClickable {
                model.setOption("refreshRate", index.toFloat()); applyRefreshRate(activity, index); model.notice = "已应用: $title"
            }.padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(title, Modifier.weight(1f), fontSize = 16.sp, color = if (selected) colors.primary else colors.onSurface, fontWeight = reviewWeight(if (selected) FontWeight.Bold else FontWeight.Medium))
                Icon(if (selected) Icons.Rounded.RadioButtonChecked else Icons.Rounded.RadioButtonUnchecked, if (selected) "已选中" else null, Modifier.size(22.dp), tint = if (selected) colors.primary else colors.onSurfaceVariant.copy(alpha = .6f))
            }
        } }
    }
}
