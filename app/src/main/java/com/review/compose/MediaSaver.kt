package com.review.compose

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable
fun rememberMediaSaver(result: (String) -> Unit): Pair<Boolean, (List<Media>) -> Unit> {
    val context = LocalContext.current
    val model = LocalReview.current
    val scope = rememberCoroutineScope()
    val report by rememberUpdatedState(result)
    var busy by remember { mutableStateOf(false) }
    var pending by remember { mutableStateOf<List<Media>>(emptyList()) }
    fun save(items: List<Media>) {
        scope.launch {
            var saved = 0
            try {
                items.forEach { MediaFiles.save(context, it, model); saved++ }
                report(if (items.size > 1) "已全部保存" else "已保存")
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { report(if (saved > 0) "已保存 $saved 项，其余保存失败：${e.message.orEmpty()}" else e.message ?: "保存失败") }
            finally { busy = false }
        }
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val items = pending; pending = emptyList()
        if (granted && items.isNotEmpty()) save(items)
        else { busy = false; if (!granted) report("请授予存储权限后重试") }
    }
    return busy to { items ->
        if (!busy && items.isNotEmpty()) {
            busy = true
            if (Build.VERSION.SDK_INT < 29 && context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                pending = items; permission.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            } else save(items)
        }
    }
}
