package com.review.compose

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun BackupScreen() {
    val model = LocalReview.current
    val context = LocalContext.current
    val store = remember { BackupStore(context, model.nativeAuth) }
    val client = remember { DavClient() }
    val scope = rememberCoroutineScope()
    var server by rememberSaveable { mutableStateOf(model.option("webdav_url")) }
    var username by rememberSaveable { mutableStateOf(model.option("webdav_username")) }
    var password by remember { mutableStateOf("") }
    var directory by rememberSaveable { mutableStateOf(model.option("webdav_directory", "Review")) }
    var full by rememberSaveable { mutableStateOf(false) }
    var busy by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var confirm by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { try { password = withContext(Dispatchers.IO) { store.password() } } catch (_: Exception) { error = "保存的授权密码无法读取，请重新填写" } }
    fun execute(kind: String) {
        if (busy.isNotBlank()) return
        busy = kind; error = null
        scope.launch {
            try {
                val config = DavConfig(server.trim(), username.trim(), password, directory.trim().ifBlank { "Review" })
                config.folder()
                withContext(Dispatchers.IO) { store.savePassword(password) }
                model.setOption("webdav_url", config.server); model.setOption("webdav_username", config.username); model.setOption("webdav_directory", config.directory)
                when (kind) {
                    "test" -> { client.test(config); model.notice = "🎉 WebDAV 服务器连接成功！" }
                    "backup" -> {
                        val historySaved = client.upload(config, store.export(full))
                        model.notice = if (historySaved) "🎉 应用设置已成功备份到 WebDAV 云盘！" else "最新备份已保存，历史副本上传失败"
                    }
                    "restore" -> {
                        val backup = client.download(config)
                        store.restore(backup)
                        model.reloadPreferences(reloadAccount = backup.optString("version") == "2.0" && backup.optString("backup_mode") == "full")
                        server = model.option("webdav_url"); username = model.option("webdav_username"); directory = model.option("webdav_directory", "Review")
                        password = withContext(Dispatchers.IO) { store.password() }
                        model.notice = "🎉 备份已成功恢复！重启应用可应用全部设置，登录有效性以服务端校验为准"
                    }
                }
            } catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "操作未完成，请检查备份与服务器设置" }
            finally { busy = "" }
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 14.dp + LocalContentTop.current, bottom = 14.dp)) {
        Surface(color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = .4f), shape = RoundedCornerShape(16.dp)) {
            Row(Modifier.padding(14.dp)) {
                Icon(Icons.Outlined.CloudSync, null, tint = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(12.dp))
                Column {
                    Text("备份内容", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(4.dp))
                    Text("备份设置、搜索和浏览历史，不含图片和视频缓存。",
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        Surface(shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.surfaceContainerLowest) {
            Column(Modifier.selectableGroup()) {
                listOf(false, true).forEach { include ->
                    Row(
                        Modifier.fillMaxWidth().selectable(full == include, enabled = busy.isBlank(),
                            role = Role.RadioButton, onClick = hapticClick { full = include })
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(if (include) "全量备份" else "全量安全备份", style = MaterialTheme.typography.titleMedium)
                            Text(if (include) "含登录凭据及 WebDAV 密码" else "不含登录凭据及 WebDAV 密码",
                                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            if (include) Text("含明文凭据，请妥善保管",
                                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        RadioButton(full == include, null, Modifier.size(24.dp).testTag("backup-mode-radio-$include"),
                            enabled = busy.isBlank())
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        Surface(shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.surfaceContainerLowest) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("WebDAV 服务器配置", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                OutlinedTextField(server, { server = it }, Modifier.fillMaxWidth(), label = { Text("服务器 URL") }, placeholder = { Text("例如: https://dav.jianguoyun.com/dav/") }, leadingIcon = { Icon(Icons.Outlined.Link, null) }, singleLine = true, enabled = busy.isBlank())
                OutlinedTextField(username, { username = it }, Modifier.fillMaxWidth(), label = { Text("账号 / 邮箱") }, leadingIcon = { Icon(Icons.Outlined.PersonOutline, null) }, singleLine = true, enabled = busy.isBlank())
                OutlinedTextField(password, { password = it }, Modifier.fillMaxWidth(), label = { Text("应用密码 / Token") }, leadingIcon = { Icon(Icons.Outlined.Lock, null) }, visualTransformation = PasswordVisualTransformation(), singleLine = true, enabled = busy.isBlank())
                OutlinedTextField(directory, { directory = it }, Modifier.fillMaxWidth(), label = { Text("备份文件夹名称") }, placeholder = { Text("默认: Review") }, leadingIcon = { Icon(Icons.Outlined.Folder, null) }, singleLine = true, enabled = busy.isBlank())
                OutlinedButton(onClick = hapticClick { execute("test") }, Modifier.fillMaxWidth(), enabled = busy.isBlank()) { Icon(Icons.Outlined.WifiTethering, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text(if (busy == "test") "正在测试连接..." else "测试服务器连接") }
            }
        }
        Spacer(Modifier.height(16.dp))
        Surface(shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.surfaceContainerLowest) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("云端备份与还原操作", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(onClick = hapticClick { execute("backup") }, Modifier.weight(1f), enabled = busy.isBlank(),
                        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 12.dp)) {
                        Icon(Icons.Outlined.CloudUpload, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(if (busy == "backup") "正在上传..." else "立即备份到云端")
                    }
                    FilledTonalButton(onClick = hapticClick { confirm = true }, Modifier.weight(1f), enabled = busy.isBlank(),
                        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 12.dp)) {
                        Icon(Icons.Outlined.CloudDownload, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(if (busy == "restore") "正在拉取..." else "从云端恢复备份")
                    }
                }
            }
        }
        if (busy.isNotBlank()) LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = 12.dp))
        error?.let { Text(it, Modifier.padding(top = 12.dp), color = MaterialTheme.colorScheme.error) }
    }
    if (confirm) ReviewAlertDialog(onDismissRequest = { confirm = false }, title = { Text("从 WebDAV 恢复备份？") },
        text = { Text("将覆盖备份中包含的设置和历史。全量备份会替换登录凭据和 WebDAV 密码。安全备份保留本机凭据。") },
        confirmButton = { Button(onClick = hapticClick { confirm = false; execute("restore") }) { Text("确定恢复") } },
        dismissButton = { TextButton(onClick = hapticClick { confirm = false }) { Text("取消") } })
}
