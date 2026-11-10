package com.review.compose

import android.app.Activity
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.imageLoader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.abs

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StorageScreen() {
    val model = LocalReview.current
    val colors = MaterialTheme.colorScheme
    var selecting by remember { mutableStateOf("") }
    fun label(key: String) = when (key) { "self" -> "Picture/Review/${model.me?.name?.takeIf(String::isNotBlank) ?: "MyProfile"}/"; "author" -> "Picture/Review/该条微博发布用户昵称/"; else -> "Picture/Review/" }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 12.dp + LocalContentTop.current, bottom = 26.dp)) {
        SettingsCard {
            listOf("image" to "图片存储路径", "video" to "视频存储路径").forEach { (kind, title) -> ReviewListItem(headlineContent = { Text(title, fontSize = 16.sp, fontWeight = reviewWeight(androidx.compose.ui.text.font.FontWeight.SemiBold)) }, supportingContent = { Text(label(model.option(kind + "Path", "review")), style = MaterialTheme.typography.bodyMedium) }, leadingContent = { Icon(if (kind == "image") Icons.Outlined.Image else Icons.Outlined.VideoLibrary, null, tint = colors.primary) }, trailingContent = { Icon(Icons.Outlined.ChevronRight, null) }, colors = ListItemDefaults.colors(containerColor = androidx.compose.ui.graphics.Color.Transparent), modifier = Modifier.reviewClickable { selecting = kind }) }
        }
    }
    if (selecting.isNotBlank()) ModalBottomSheet(onDismissRequest = { selecting = "" }) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) { Text(if (selecting == "image") "图片存储路径" else "视频存储路径", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontWeight = reviewWeight(androidx.compose.ui.text.font.FontWeight.Bold)); IconButton(onClick = hapticClick { selecting = "" }) { Icon(Icons.Outlined.Close, "关闭") } }
            Text("保存${if (selecting == "image") "图片" else "视频"}时，文件将自动归类并存储至相册对应文件夹下。", Modifier.padding(top = 6.dp, bottom = 12.dp), style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
            listOf("review" to "默认路径", "self" to "按本人昵称前缀归类", "author" to "按博主昵称前缀归类").forEach { (key, title) ->
                ReviewListItem(headlineContent = { Text(title, fontWeight = reviewWeight(androidx.compose.ui.text.font.FontWeight.SemiBold)) }, supportingContent = { Text(label(key), style = MaterialTheme.typography.bodyMedium) }, leadingContent = { RadioButton(model.option(selecting + "Path", "review") == key, null) }, colors = ListItemDefaults.colors(containerColor = androidx.compose.ui.graphics.Color.Transparent), modifier = Modifier.reviewClickable { model.setOption(selecting + "Path", key); selecting = "" })
            }
        }
    }
}
@Composable
fun CacheScreen() {
    val model = LocalReview.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var bytes by remember { mutableLongStateOf(0L) }
    var loading by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var clear by remember { mutableStateOf(false) }
    var threshold by remember { mutableStateOf(false) }
    val colors = MaterialTheme.colorScheme
    suspend fun measure() {
        loading = true; error = null
        try { bytes = imageCacheSize(context) }
        catch (e: kotlinx.coroutines.CancellationException) { throw e }
        catch (_: Exception) { error = "暂时无法读取图片缓存" }
        finally { loading = false }
    }
    LaunchedEffect(Unit) { measure() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 32.dp)) {
        Surface(shape = androidx.compose.foundation.shape.RoundedCornerShape(24.dp), color = colors.settingsCardColor()) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 24.dp), horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally) {
                Surface(Modifier.size(56.dp), shape = androidx.compose.foundation.shape.CircleShape, color = colors.primaryContainer) {
                    Box(contentAlignment = androidx.compose.ui.Alignment.Center) { Icon(Icons.Outlined.CleaningServices, null, Modifier.size(30.dp), tint = colors.onPrimaryContainer) }
                }
                Spacer(Modifier.height(16.dp))
                if (loading) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.5.dp)
                else Text(error ?: cacheSizeLabel(bytes), style = MaterialTheme.typography.headlineMedium, fontWeight = reviewWeight(androidx.compose.ui.text.font.FontWeight.Bold), color = if (error == null) colors.onSurface else colors.error)
                Spacer(Modifier.height(4.dp)); Text("可管理的图片磁盘缓存", color = colors.onSurfaceVariant)
                Spacer(Modifier.height(8.dp)); Text("只统计临时目录中的图片缓存文件", style = MaterialTheme.typography.bodySmall, color = colors.onSurfaceVariant)
            }
        }
        Spacer(Modifier.height(16.dp))
        Surface(shape = androidx.compose.foundation.shape.RoundedCornerShape(24.dp), color = colors.settingsCardColor()) {
            Button(enabled = !loading && !busy && error == null, onClick = hapticClick { if (bytes == 0L) model.notice = "当前没有可清理的图片缓存" else clear = true },
                modifier = Modifier.padding(16.dp).fillMaxWidth().height(48.dp), shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp)) {
                if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Icon(Icons.Outlined.DeleteSweep, null)
                Spacer(Modifier.width(8.dp)); Text(if (busy) "正在清理..." else "清理图片缓存")
            }
        }
        Spacer(Modifier.height(24.dp)); Text("自动清理规则", Modifier.padding(horizontal = 16.dp), style = MaterialTheme.typography.titleMedium, fontWeight = reviewWeight(androidx.compose.ui.text.font.FontWeight.Bold))
        Spacer(Modifier.height(12.dp))
        Surface(shape = androidx.compose.foundation.shape.RoundedCornerShape(24.dp), color = colors.settingsCardColor()) {
            ReviewListItem(headlineContent = { Text("自动清理缓存阈值") }, supportingContent = { Text("达到阈值时在启动阶段自动清理；更改后也会立即检查一次") },
                leadingContent = { Icon(Icons.Outlined.AutoDelete, null) }, trailingContent = { Text(cacheThresholdLabel(model.number("cacheLimit", 200f).toInt()), color = colors.primary) },
                modifier = Modifier.reviewClickable { threshold = true }, colors = ListItemDefaults.colors(containerColor = androidx.compose.ui.graphics.Color.Transparent))
        }
        Spacer(Modifier.height(24.dp))
        Surface(shape = androidx.compose.foundation.shape.RoundedCornerShape(24.dp), color = colors.settingsCardColor()) {
            Text("清理仅针对 Review 图片加载生成的磁盘缓存；最近 1 分钟内写入的文件会暂时保留。已保存到相册的图片和视频、账号资料及其他临时文件不会被删除。", Modifier.padding(16.dp), color = colors.onSurfaceVariant)
        }
        Spacer(Modifier.height(16.dp))
        TextButton(enabled = !loading && !busy, onClick = hapticClick { scope.launch { measure() } }, modifier = Modifier.align(androidx.compose.ui.Alignment.CenterHorizontally)) { Icon(Icons.Outlined.Refresh, null); Text("刷新缓存占用") }
    }
    if (clear) ReviewAlertDialog(onDismissRequest = { clear = false }, title = { Text("清理图片缓存？") }, text = { Text("将清理 ${cacheSizeLabel(bytes)} 的可再生成图片磁盘缓存。正在写入的文件会保留；已保存到相册的图片、视频和账号数据不会受影响。") }, confirmButton = { TextButton(onClick = hapticClick {
        clear = false; busy = true; scope.launch {
            try { val removed = maintainImageCache(context, clear = true); measure(); model.notice = if (removed > 0) "已清理 ${cacheSizeLabel(removed)} 图片缓存" else "没有可清理的缓存文件，正在写入的文件已保留" }
            catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (_: Exception) { model.notice = "清理失败，请稍后重试" }
            finally { busy = false }
        }
    }) { Text("立即清理") } }, dismissButton = { TextButton(onClick = hapticClick { clear = false }) { Text("取消") } })
    if (threshold) ReviewAlertDialog(onDismissRequest = { threshold = false }, title = { Text("自动清理阈值") }, text = { Column(Modifier.verticalScroll(rememberScrollState())) {
        cacheThresholds.forEach { n -> ReviewListItem(headlineContent = { Text(cacheThresholdLabel(n)) }, leadingContent = { RadioButton(model.number("cacheLimit", 200f).toInt() == n, null) }, modifier = Modifier.reviewClickable {
            model.setOption("cacheLimit", n.toFloat()); threshold = false
            scope.launch { try { maintainImageCache(context, n); measure() } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (_: Exception) { model.notice = "清理失败，请稍后重试" } }
        }) }
    } }, confirmButton = { TextButton(onClick = hapticClick { threshold = false }) { Text("取消") } })
}
suspend fun clearMediaCache(context: android.content.Context) { maintainImageCache(context, clear = true) }
fun applyRefreshRate(activity: Activity, mode: Int) {
    val params = activity.window.attributes
    if (mode == 0) { params.preferredDisplayModeId = 0; params.preferredRefreshRate = 0f }
    else {
        val rates = listOf(120f, 90f, 72f, 60f)
        val fps = rates[(mode - 1).coerceIn(0, 7) % 4]
        val modes = activity.windowManager.defaultDisplay.supportedModes
        val width = if (mode > 4) 1080 else modes.maxOf { minOf(it.physicalWidth, it.physicalHeight) }
        val matched = modes.firstOrNull { minOf(it.physicalWidth, it.physicalHeight) == width && abs(it.refreshRate - fps) < 2 } ?: modes.firstOrNull { abs(it.refreshRate - fps) < 2 }
        params.preferredDisplayModeId = matched?.modeId ?: 0; params.preferredRefreshRate = fps
    }
    activity.window.attributes = params
}
