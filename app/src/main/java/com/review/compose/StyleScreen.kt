package com.review.compose

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import coil.compose.SubcomposeAsyncImage

val cardLayouts = linkedMapOf("normal" to "普通布局", "floating_rect" to "浮动直角卡片布局", "floating_rounded" to "浮动圆角卡片布局", "normal_thin_divider" to "普通布局（微博间距细小分割线）", "card_rounded" to "卡片圆角布局")
private val ipLabels = linkedMapOf("all" to "列表和详情都显示", "detail_only" to "仅详情显示", "none" to "不显示")

@Composable
fun StyleScreen() {
    val model = LocalReview.current; val colors = MaterialTheme.colorScheme
    var expanded by remember { mutableStateOf(false) }
    var dialog by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxWidth().background(if (colors.background.luminance() < .5f) Color(0xFF141416) else colors.surfaceContainerHighest.copy(alpha = .4f)).padding(horizontal = 16.dp, vertical = 12.dp)) { StylePreview() }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp)) {
            StyleSection("卡片与时间显示") {
                SettingsCard {
                    ReviewListItem(headlineContent = { Text("时间显示模式", fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.SemiBold)) }, supportingContent = { Text(if (model.option("timeMode", "relative") == "relative") "智能相对时间 (如3分钟前)" else "绝对时间 (如 2026-08-29 10:30)", fontSize = 14.sp) }, leadingContent = { Icon(Icons.Outlined.Schedule, null, tint = colors.primary) }, trailingContent = { Icon(if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, null) }, colors = ListItemDefaults.colors(containerColor = Color.Transparent), modifier = Modifier.reviewClickable { expanded = !expanded })
                    AnimatedVisibility(expanded) { Column {
                        listOf(Triple("relative", "智能相对时间", "显示“刚刚”、“3分钟前”、“昨天 15:30”等易读时间"), Triple("absolute", "绝对具体时间", "显示“2026-08-29 10:30”等具体年月日时间")).forEach { (value, title, subtitle) ->
                            ReviewListItem(headlineContent = { Text(title, fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.SemiBold)) }, supportingContent = { Text(subtitle, fontSize = 14.sp, lineHeight = 19.6.sp) }, leadingContent = { RadioButton(model.option("timeMode", "relative") == value, null) }, colors = ListItemDefaults.colors(containerColor = Color.Transparent), modifier = Modifier.reviewClickable { model.setOption("timeMode", value) }.padding(vertical = 2.dp))
                        }
                        StyleSwitch("显示星期几 (如周五 / Friday)", "weekday")
                        StyleSwitch("显示具体年份 (跨年/强制显示)", "year")
                        StyleSwitch("显示时区标识 (+0800)", "timezone")
                        StyleSwitch("显示秒数 (HH:mm:ss)", "seconds")
                        StyleSwitch("显示发布设备 / 来自...", "source", true)
                    } }
                }
            }
            StyleSection("排版与视觉布局") {
                SettingsCard {
                    StyleOption("微博背景布局", cardLayouts[model.option("cardLayout", "card_rounded")].orEmpty(), Icons.Outlined.DashboardCustomize) { dialog = "layout" }
                    StyleOption("正文字体大小", "${model.number("postFont", 16f).toInt()} pt", Icons.Outlined.FormatSize) { dialog = "font" }
                    StyleOption("正文字体行间距倍数", "${model.number("postLine", 1.3f)} 倍", Icons.Outlined.FormatLineSpacing) { dialog = "line" }
                    StyleOption("显示微博发送的 IP 属地", ipLabels[model.option("ip", "all")].orEmpty(), Icons.Outlined.LocationOn) { dialog = "ip" }
                }
            }
            StyleSection("功能开关与视觉控制") {
                SettingsCard {
                    StyleSwitch("链接颜色跟随主题", "linkTheme", true, "使用当前个性化主题强调色作为超链接颜色")
                    StyleSwitch("同时显示备注和名字", "remark", subtitle = "如果存在好友备注，在名称旁标注备注")
                    StyleSwitch("显示个人主页背景图", "postBackground", subtitle = "在个人主页顶部渲染博主自定义背景封面")
                    StyleSwitch("显示微博用户活动图标", "activityIcon", true, "在博主名称右侧展示认证徽章与活动标识")
                    StyleSwitch("大图片九宫格模式", "largeImages", true, "以大画幅高清展现九宫格图片")
                    StyleSwitch("微博内图片圆角显示", "roundImages", true, "为正文中的九宫格图片与单图添加精致圆角")
                    StyleSwitch("菜单键显示在底部", "menuBottom", true, "将卡片操作菜单（复制/收藏/屏蔽）置于底栏")
                    StyleSwitch("主页显示赞过的微博", "profileLikes", subtitle = "在个人中心标签页展示点赞历史记录")
                }
            }
        }
    }
    if (dialog.isNotEmpty()) Dialog(onDismissRequest = { dialog = "" }) {
        Surface(shape = RoundedCornerShape(28.dp), color = colors.surfaceContainerHigh) {
            Column(Modifier.verticalScroll(rememberScrollState()).padding(vertical = 24.dp)) {
                Text(when (dialog) { "layout" -> "选择微博背景布局"; "font" -> "选择正文字体大小"; "line" -> "选择字体间距(倍数)"; else -> "显示微博发送的 IP 位置" }, Modifier.padding(start = 24.dp, end = 24.dp, bottom = 12.dp), style = MaterialTheme.typography.headlineSmall)
                val options = when (dialog) { "layout" -> cardLayouts; "font" -> (13..20).associate { "$it" to "$it pt" }; "line" -> (11..17).associate { "${it / 10f}" to "${it / 10f} 倍" }; else -> ipLabels }
                val current = when (dialog) { "layout" -> model.option("cardLayout", "card_rounded"); "font" -> model.number("postFont", 16f).toInt().toString(); "line" -> model.number("postLine", 1.3f).toString(); else -> model.option("ip", "all") }
                options.forEach { (key, label) -> Row(Modifier.fillMaxWidth().reviewClickable {
                    when (dialog) { "layout" -> model.setOption("cardLayout", key); "font" -> model.setOption("postFont", key.toFloat()); "line" -> model.setOption("postLine", key.toFloat()); else -> model.setOption("ip", key) }; dialog = ""
                }.padding(horizontal = 24.dp, vertical = if (dialog == "layout") 14.dp else 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(label, Modifier.weight(1f), fontWeight = reviewWeight(if (current == key) FontWeight.Bold else FontWeight.Normal), color = if (dialog == "layout" && current == key) colors.primary else colors.onSurface)
                    if (dialog == "layout" && current == key) Icon(Icons.Outlined.Check, null, tint = colors.primary)
                } }
            }
        }
    }
}

@Composable private fun StyleSection(title: String, content: @Composable () -> Unit) {
    Text(title, Modifier.padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 6.dp), fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.Bold), color = MaterialTheme.colorScheme.onSurfaceVariant)
    content(); Spacer(Modifier.height(16.dp))
}
@Composable private fun StyleOption(title: String, subtitle: String, icon: ImageVector, click: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    ReviewListItem(headlineContent = { Text(title, fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.SemiBold), lineHeight = 21.6.sp) }, supportingContent = { Text(subtitle, fontSize = 14.sp, lineHeight = 19.6.sp, fontWeight = reviewWeight(FontWeight.Medium), color = colors.primary) }, leadingContent = { Icon(icon, null, tint = colors.primary) }, trailingContent = { Icon(Icons.Outlined.ChevronRight, null) }, colors = ListItemDefaults.colors(containerColor = Color.Transparent), modifier = Modifier.reviewClickable(onClick = click))
}
@Composable private fun StyleSwitch(title: String, key: String, default: Boolean = false, subtitle: String = "") {
    val model = LocalReview.current
    val value = model.bool(key, default)
    val change = { next: Boolean -> model.setOption(key, next) }
    ReviewListItem(headlineContent = { Text(title, fontSize = 16.sp, fontWeight = reviewWeight(if (subtitle.isBlank()) FontWeight.Medium else FontWeight.SemiBold), lineHeight = 21.6.sp) }, supportingContent = if (subtitle.isBlank()) null else { { Text(subtitle, fontSize = 14.sp, lineHeight = 19.6.sp) } }, trailingContent = { Switch(value, null, thumbContent = if (subtitle.isBlank()) null else { { Icon(if (value) Icons.Outlined.Check else Icons.Outlined.Close, null, Modifier.size(if (value) 14.dp else 12.dp)) } }) }, colors = ListItemDefaults.colors(containerColor = Color.Transparent), modifier = Modifier.reviewToggleable(value, change = change).padding(vertical = 2.dp))
}

@Composable
private fun StylePreview() {
    val model = LocalReview.current; val colors = MaterialTheme.colorScheme; val dark = colors.background.luminance() < .5f
    val layout = model.option("cardLayout", "card_rounded"); val floating = layout.startsWith("floating")
    val rounded = layout.endsWith("rounded"); val font = model.number("postFont", 16f)
    val link = if (model.bool("linkTheme", true)) colors.primary else Color(0xFF3366CC)
    Column {
        Surface(Modifier.padding(if (floating) 4.dp else if (layout == "card_rounded") 2.dp else 0.dp), shape = RoundedCornerShape(if (rounded) 16.dp else 0.dp), color = if (dark) Color(0xFF1E1E22) else Color.White, shadowElevation = if (floating) 5.dp else if (layout == "card_rounded") 2.dp else 0.dp) {
            Column(Modifier.padding(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar("Caij", "https://tvax1.sinaimg.cn/crop.0.0.1080.1080.180/006ZdyPily8h1r6z14w3zj30u00u0dhm.jpg", Modifier.size(38.dp), true, 0)
                    Spacer(Modifier.width(10.dp)); Column(Modifier.weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically) { Text("Caij", fontSize = 14.sp, fontWeight = reviewWeight(FontWeight.Bold)); if (model.bool("remark")) Text(" (小蔡)", fontSize = 12.sp, color = colors.onSurfaceVariant); if (model.bool("activityIcon", true)) Icon(Icons.Outlined.Verified, null, Modifier.padding(start = 4.dp).size(14.dp), colors.primary) }
                        Text("刚刚${if (model.option("ip", "all") != "none") " · 北京" else ""}", Modifier.padding(top = 2.dp), fontSize = 11.sp, color = colors.onSurfaceVariant)
                    }
                    if (!model.bool("menuBottom", true)) Icon(Icons.Outlined.MoreHoriz, "预览中的更多菜单", Modifier.size(20.dp), colors.onSurfaceVariant)
                }
                Spacer(Modifier.height(8.dp)); Text("微博内容 哈哈哈哈哈哈哈哈哈哈哈哈哈哈 ✨", fontSize = font.sp, lineHeight = (font * model.number("postLine", 1.3f)).sp)
                Spacer(Modifier.height(4.dp)); Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Outlined.Link, null, Modifier.size(14.dp), link); Spacer(Modifier.width(2.dp)); Text("网页链接 https://weibo.com", fontSize = (font - 1).sp, color = link, fontWeight = reviewWeight(FontWeight.Medium)) }
                Spacer(Modifier.height(8.dp))
                Row(Modifier.height(if (model.bool("largeImages", true)) 140.dp else 100.dp).clip(RoundedCornerShape(if (model.bool("roundImages", true)) 8.dp else 0.dp)), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    PreviewPhoto("https://picsum.photos/id/1015/600/400", Modifier.weight(5f).fillMaxHeight(), true)
                    Column(Modifier.weight(3f), verticalArrangement = Arrangement.spacedBy(4.dp)) { PreviewPhoto("https://picsum.photos/id/1018/400/300", Modifier.weight(1f).fillMaxWidth()); PreviewPhoto("https://picsum.photos/id/1025/400/300", Modifier.weight(1f).fillMaxWidth()) }
                }
                Spacer(Modifier.height(10.dp)); Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceAround) {
                    (listOf(Icons.Outlined.Repeat, Icons.Outlined.ChatBubbleOutline, Icons.Outlined.FavoriteBorder, Icons.Outlined.StarBorder) + if (model.bool("menuBottom", true)) listOf(Icons.Outlined.MoreHoriz) else emptyList()).forEach { Icon(it, null, Modifier.size(18.dp), colors.onSurfaceVariant) }
                }
            }
        }
        if (layout == "normal_thin_divider") Spacer(Modifier.padding(top = 4.dp).fillMaxWidth().height(8.dp).background(if (dark) Color(0xFF0F0F12) else colors.surfaceContainerHighest.copy(alpha = .4f)))
        if (layout == "normal") ReviewDivider(thickness = .8.dp, color = colors.outlineVariant.copy(alpha = .3f))
    }
}
@Composable private fun PreviewPhoto(url: String, modifier: Modifier, large: Boolean = false) {
    val colors = MaterialTheme.colorScheme; val dark = colors.background.luminance() < .5f
    val placeholder: @Composable () -> Unit = { Box(Modifier.fillMaxSize().background(if (dark) Color(0xFF2C2D35) else colors.surfaceContainerHigh), contentAlignment = Alignment.Center) { Icon(Icons.Outlined.Image, null, Modifier.size(if (large) 28.dp else 20.dp), if (large) colors.primary else colors.secondary) } }
    SubcomposeAsyncImage(url, "样式预览图片", modifier.clip(RoundedCornerShape(if (LocalReview.current.bool("roundImages", true)) 6.dp else 0.dp)), contentScale = androidx.compose.ui.layout.ContentScale.Crop, loading = { placeholder() }, error = { placeholder() })
}
