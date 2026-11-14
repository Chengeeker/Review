@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package com.review.compose

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun SettingsSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Text(title, Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
    SettingsCard(content)
    Spacer(Modifier.height(16.dp))
}
@Composable
fun SettingsCard(content: @Composable ColumnScope.() -> Unit) {
    Surface(shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.settingsCardColor()) { Column(content = content) }
}

@Composable
fun SettingsTile(headlineContent: @Composable () -> Unit, modifier: Modifier = Modifier,
    supportingContent: (@Composable () -> Unit)? = null, leadingContent: (@Composable () -> Unit)? = null,
    trailingContent: (@Composable () -> Unit)? = null) {
    val colors = MaterialTheme.colorScheme
    Row(modifier.fillMaxWidth().padding(horizontal = 16.dp).heightIn(min = if (supportingContent == null) 56.dp else 72.dp), verticalAlignment = Alignment.CenterVertically) {
        if (leadingContent != null) { leadingContent(); Spacer(Modifier.width(16.dp)) }
        Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
            ProvideTextStyle(MaterialTheme.typography.bodyLarge.copy(fontWeight = reviewWeight(FontWeight.SemiBold), lineHeight = 21.6.sp, color = colors.onSurface), headlineContent)
            if (supportingContent != null) ProvideTextStyle(MaterialTheme.typography.bodyMedium.copy(lineHeight = 19.6.sp, color = colors.onSurfaceVariant), supportingContent)
        }
        if (trailingContent != null) { Spacer(Modifier.width(16.dp)); trailingContent() }
    }
}

@Composable
private fun ThemeToggle(title: String, summary: String, icon: ImageVector, value: Boolean, enabled: Boolean = true, change: (Boolean) -> Unit) {
    SettingsTile(headlineContent = { Text(title, fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.SemiBold)) }, supportingContent = if (summary.isBlank()) null else { { Text(summary, fontSize = 14.sp, lineHeight = 19.6.sp) } },
        leadingContent = { Icon(icon, null, tint = MaterialTheme.colorScheme.primary) }, trailingContent = { Switch(value, null, modifier = Modifier.padding(horizontal = 4.dp), enabled = enabled) },
        modifier = Modifier.reviewToggleable(value, enabled, change).padding(vertical = 3.dp))
}

fun fontWeightLabel(delta: Int) = when (delta) { -100 -> "偏细"; 100 -> "中等"; 200 -> "偏粗"; 300 -> "加粗"; else -> "默认" }
fun refreshModeLabel(mode: Int) = if (mode == 0) "自动" else "${if (mode <= 4) "原生分辨率" else "1080P"} ${listOf(120, 90, 72, 60)[(mode - 1).coerceIn(0, 7) % 4]}Hz"

@Composable
fun ThemeScreen() {
    val model = LocalReview.current
    val colors = MaterialTheme.colorScheme
    val weight = model.number("weight", 0f).toInt()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 12.dp + LocalContentTop.current, bottom = 24.dp)) {
        AppearanceModes(model.theme, model::updateTheme, model.bool("pureBlack"), { model.setOption("pureBlack", it) })
        Spacer(Modifier.height(16.dp))
        AppearancePalette(model.dynamicColor, model::setDynamic, model.number("palette", 0f).toInt(),
            { model.setOption("palette", it.toFloat()) })
        Spacer(Modifier.height(16.dp))
        FontWeightSetting(model.bool("customWeight"), weight, "Review", hapticsEnabled = model.bool("haptics", true),
            onReset = { model.setOption("customWeight", false) },
            onCommit = { model.setOption("weight", it.toFloat()); model.setOption("customWeight", true) })
        Spacer(Modifier.height(16.dp))
        FontSizeSetting(model.textScale, onCommit = model::updateTextScale)
        Spacer(Modifier.height(16.dp))
        SettingsSection("底部导航") { ThemeToggle("使用悬浮底栏", "居中显示悬浮式导航栏", Icons.Outlined.Dock, model.bool("floating", true)) { model.setOption("floating", it) } }
        SettingsSection("显示效果") { ThemeToggle("使用液态玻璃效果", "控制液态玻璃控件；当前应用于悬浮底栏", Icons.Outlined.BlurOn, model.bool("liquidGlass")) { model.setOption("liquidGlass", it) }
            if(model.bool("liquidGlass") && model.bool("floating", true)) NavigationGlassChoice(model.bool("translucentNavigationGlass", false), hapticsEnabled = model.bool("haptics", true)) { model.setOption("translucentNavigationGlass", it) }
        }
        SettingsSection("应用图标") { Preference("自定义应用图标", Icons.Outlined.AppShortcut, appIconName(model.number("icon", 0f).toInt())) { model.navigate("icons") } }
        SettingsSection("屏幕显示") { Preference("屏幕帧率设置", Icons.Outlined.Speed, refreshModeLabel(model.number("refreshRate", 0f).toInt())) { model.navigate("refreshRate") } }
        if (Build.VERSION.SDK_INT >= 34) SettingsSection("手势与动效") {
            ThemeToggle("可预测性返回", "应用内页面随系统返回手势预览上一页", Icons.Outlined.Swipe, model.bool("predictiveBack")) { model.setOption("predictiveBack", it) }
        }
        SettingsSection("触感与震动") { ThemeToggle("触感与震动反馈", "点击、长按和完成指定手势时轻振一次", Icons.Outlined.Vibration, model.bool("haptics", true)) { model.setOption("haptics", it) } }
    }
}
