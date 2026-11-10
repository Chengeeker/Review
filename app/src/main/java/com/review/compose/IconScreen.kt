package com.review.compose

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val iconResources = listOf(R.mipmap.ic_launcher, R.mipmap.ic_launcher_alias1, R.mipmap.ic_launcher_alias2)
private val iconNames = listOf("官方默认", "质感经典", "活力新潮")
fun appIconName(index: Int) = iconNames[index.coerceIn(0, 2)]
private val iconDescriptions = listOf("Review 官方标准应用图标", "深邃内敛，经典雅致视觉", "灵动纯粹，现代美学设计")
private fun iconComponents(context: Context) = listOf(".MainActivity", ".MainActivityAlias1", ".MainActivityAlias2").map { ComponentName(context.packageName, context.packageName + it) }

fun switchAppIcon(context: Context, index: Int) {
    require(index in 0..2)
    val pm = context.packageManager
    val components = iconComponents(context)
    val before = components.map(pm::getComponentEnabledSetting)
    try {
        pm.setComponentEnabledSetting(components[index], PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        components.forEachIndexed { i, component -> if (i != index) pm.setComponentEnabledSetting(component, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP) }
        check(context.getSharedPreferences("preferences", 0).edit().putFloat("icon", index.toFloat()).commit()) { "图标设置保存失败" }
    } catch (failure: Exception) {
        components.forEachIndexed { i, component -> runCatching { pm.setComponentEnabledSetting(component, before[i], PackageManager.DONT_KILL_APP) } }
        throw failure
    }
}

@Composable
fun IconScreen() {
    val model = LocalReview.current
    val context = LocalContext.current; val activity = LocalActivity.current
    val colors = MaterialTheme.colorScheme; val scope = rememberCoroutineScope()
    var chosen by remember { mutableIntStateOf(-1) }
    var busy by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        val actual = iconComponents(context).indexOfFirst { context.packageManager.getComponentEnabledSetting(it) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED }.coerceAtLeast(0)
        if (model.number("icon", 0f).toInt() != actual) model.setOption("icon", actual.toFloat())
    }
    val active = model.number("icon", 0f).toInt().coerceIn(0, 2)
    fun select(index: Int) { chosen = index }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 12.dp + LocalContentTop.current, bottom = 36.dp)) {
        SettingsCard {
            Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Image(painterResource(iconResources[active]), null, Modifier.size(64.dp).shadow(3.dp, RoundedCornerShape(16.dp)).clip(RoundedCornerShape(16.dp)))
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Review", fontSize = 18.sp, fontWeight = reviewWeight(FontWeight.Bold), letterSpacing = .2.sp); Spacer(Modifier.width(8.dp))
                        Text(iconNames[active], Modifier.background(colors.primaryContainer, RoundedCornerShape(6.dp)).padding(horizontal = 7.dp, vertical = 2.dp), color = colors.onPrimaryContainer, fontSize = 11.sp, fontWeight = reviewWeight(FontWeight.Bold))
                    }
                    Spacer(Modifier.height(4.dp)); Text(iconDescriptions[active], fontSize = 14.sp, lineHeight = 18.2.sp, color = colors.onSurfaceVariant)
                }
            }
        }
        Spacer(Modifier.height(16.dp)); Text("可选预设图标", Modifier.padding(start = 16.dp, bottom = 8.dp), fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.Bold), color = colors.onSurfaceVariant)
        iconResources.forEachIndexed { index, resource ->
            val selected = active == index
            Surface(Modifier.padding(bottom = 10.dp), color = colors.surfaceContainerLow, shape = RoundedCornerShape(24.dp), border = if (selected) BorderStroke(1.5.dp, colors.primary) else null) {
                Row(Modifier.fillMaxWidth().heightIn(min = 84.dp).reviewClickable(enabled = !selected && !busy) { select(index) }.padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Image(painterResource(resource), null, Modifier.size(48.dp).shadow(2.dp, RoundedCornerShape(12.dp)).clip(RoundedCornerShape(12.dp))); Spacer(Modifier.width(16.dp))
                    Column(Modifier.weight(1f)) { Text(iconNames[index], fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.SemiBold)); Text(iconDescriptions[index], fontSize = 14.sp, color = colors.onSurfaceVariant) }
                    Spacer(Modifier.width(12.dp))
                    if (selected) Row(Modifier.background(colors.primaryContainer, RoundedCornerShape(8.dp)).padding(horizontal = 10.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Check, null, Modifier.size(14.dp), tint = colors.primary); Spacer(Modifier.width(4.dp)); Text("使用中", fontSize = 12.sp, fontWeight = reviewWeight(FontWeight.Bold), color = colors.primary)
                    } else FilledTonalButton(onClick = hapticClick { select(index) }, enabled = !busy, contentPadding = PaddingValues(horizontal = 14.dp, vertical = 4.dp), modifier = Modifier.defaultMinSize(minWidth = 60.dp, minHeight = 32.dp)) { Text("应用", fontSize = 13.sp) }
                }
            }
        }
        Spacer(Modifier.height(12.dp)); Text("💡 提示：内置官方预设图标不可删除，随时支持自由切换。切换后应用将一并同步关于页面等各处的应用图标展示。", Modifier.padding(horizontal = 8.dp), fontSize = 12.sp, lineHeight = 16.8.sp, color = colors.onSurfaceVariant.copy(alpha = .8f))
    }
    if (chosen in 0..2) ReviewAlertDialog(onDismissRequest = { if (!busy) chosen = -1 }, title = { Text("应用“${iconNames[chosen]}”") }, text = {
        Text("确定切换为“${iconNames[chosen]}”吗？\n\n⚠️ 提示：应用新图标需要结束应用进程以使手机桌面刷新图标。点击确认后将退出应用，请返回桌面查看全新图标。", fontSize = 13.5.sp, lineHeight = 19.575.sp)
    }, dismissButton = { TextButton(onClick = hapticClick { chosen = -1 }, enabled = !busy) { Text("取消") } }, confirmButton = {
        Button(enabled = !busy, onClick = hapticClick {
            val target = chosen; busy = true
            scope.launch {
                model.notice = "正在应用“${iconNames[target]}”并同步桌面与抽屉..."; delay(300)
                try { switchAppIcon(context, target); activity?.finishAndRemoveTask(); android.os.Process.killProcess(android.os.Process.myPid()) }
                catch (_: Exception) { model.notice = "图标切换失败，请稍后重试"; chosen = -1; busy = false }
            }
        }) { Text("应用并退出") }
    })
}
