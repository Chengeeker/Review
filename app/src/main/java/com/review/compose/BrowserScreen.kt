@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.webkit.*
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

internal fun browserCookieWrites(url: String, cookie: String, existing: String): List<Pair<String, String>> {
    val uri = runCatching { java.net.URI(url) }.getOrNull() ?: return emptyList()
    val host = uri.host?.lowercase() ?: return emptyList()
    val domain = listOf("weibo.com", "weibo.cn").firstOrNull { host == it || host.endsWith(".$it") } ?: return emptyList()
    if (uri.scheme != "https" || uri.userInfo != null || cookie.length > 32768 || cookie.any { it !in ' '..'~' }) return emptyList()
    fun pairs(value: String) = value.split(';').mapNotNull {
        val name = it.substringBefore('=').trim()
        val content = it.substringAfter('=', "").trim()
        if ('=' in it && name.matches(Regex("[A-Za-z0-9_!#$%&'*+.^`|~-]+"))) name to content else null
    }.toMap()
    val current = pairs(cookie)
    val names = pairs(existing).keys + current.keys
    return names.flatMap { name ->
        val value = current[name]
        val setting = if (value == null) "$name=; Max-Age=0" else "$name=$value"
        // Clear host-only leftovers as well as replacing our domain-scoped session.
        listOf(url to "$name=; Max-Age=0; Path=/; Secure", "https://$domain/" to "$setting; Domain=.$domain; Path=/; Secure; HttpOnly")
    }
}

@Composable
fun BrowserScreen(url: String) {
    val model = LocalReview.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val colors = MaterialTheme.colorScheme
    var title by remember(url) { mutableStateOf("网页浏览") }
    var current by remember(url) { mutableStateOf(secureImage(url)) }
    var progress by remember(url) { mutableIntStateOf(0) }
    var loading by remember(url) { mutableStateOf(true) }
    var error by remember(url) { mutableStateOf<String?>(null) }
    var menu by remember { mutableStateOf(false) }
    val active = LocalPageActive.current
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val preparedHosts = remember(url, model.uid) { mutableSetOf<String>() }
    val web = remember(url, model.uid) { WebView(context).apply {
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        settings.userAgentString = "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
        CookieManager.getInstance().setAcceptThirdPartyCookies(this, false)
    } }
    suspend fun load(target: String) {
        val manager = CookieManager.getInstance()
        val cookie = model.repository.api.cookieFor(target, model.sessionCookie)
        for ((address, value) in browserCookieWrites(target, cookie, manager.getCookie(target).orEmpty())) {
            suspendCancellableCoroutine<Unit> { continuation ->
                manager.setCookie(address, value) { if (continuation.isActive) continuation.resume(Unit) }
            }
        }
        manager.flush()
        preparedHosts += Uri.parse(target).host.orEmpty()
        error = null
        web.loadUrl(target)
    }
    DisposableEffect(web) {
        web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) { progress = newProgress }
            override fun onReceivedTitle(view: WebView, value: String?) { if (!value.isNullOrBlank() && !value.contains("404")) title = value }
        }
        web.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView, address: String?, favicon: android.graphics.Bitmap?) {
                current = address.orEmpty(); progress = 0; loading = true; error = null
            }
            override fun onPageFinished(view: WebView, address: String?) { current = address.orEmpty(); loading = false }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (!request.isForMainFrame) return request.url.scheme !in setOf("http", "https")
                val target = secureImage(request.url.toString())
                if (target.isBlank()) return true
                if (model.openNativeLink(target)) return true
                if (target != request.url.toString() || request.url.host !in preparedHosts) {
                    scope.launch { load(target) }; return true
                }
                return false
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, failure: WebResourceError) {
                if (request.isForMainFrame) { error = "页面加载失败"; loading = false }
            }
        }
        onDispose { web.stopLoading(); web.webChromeClient = null; web.webViewClient = WebViewClient(); web.destroy() }
    }
    LaunchedEffect(web) { if (current.isBlank()) { error = "页面地址无效"; loading = false } else load(current) }
    LaunchedEffect(web, active, lifecycle) { if (active && lifecycle.isAtLeast(Lifecycle.State.STARTED)) web.onResume() else web.onPause() }
    BackHandler(active) { if (web.canGoBack()) web.goBack() else model.back() }
    Column(Modifier.fillMaxSize()) {
        TopAppBar(title = {
            Column(Modifier.padding(start = 16.dp)) {
                Text(title, fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (current.isNotBlank()) Text(current, fontSize = 11.sp, color = colors.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }, modifier = Modifier.frostedBackdrop(colors.background), expandedHeight = 56.dp,
            colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
            navigationIcon = { IconButton(onClick = hapticClick(model::back)) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回") } }, actions = {
                IconButton(onClick = hapticClick { error = null; web.reload() }) { Icon(Icons.Rounded.Refresh, "刷新") }
                Box {
                    IconButton(onClick = hapticClick { menu = true }) { Icon(Icons.Rounded.MoreVert, "更多") }
                    DropdownMenu(menu, { menu = false }) {
                        DropdownMenuItem(text = { Text("复制链接") }, leadingIcon = { Icon(Icons.Rounded.ContentCopy, null, Modifier.size(20.dp)) }, onClick = hapticClick {
                            menu = false
                            (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("链接", current))
                            model.notice = "链接已复制到剪贴板"
                        })
                        DropdownMenuItem(text = { Text("在外部浏览器打开") }, leadingIcon = { Icon(Icons.Rounded.OpenInBrowser, null, Modifier.size(20.dp)) }, onClick = hapticClick {
                            menu = false
                            runCatching { require(secureImage(current).isNotBlank()); context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(current))) }.onFailure { model.notice = "未找到可用的外部浏览器" }
                        })
                    }
                }
            })
        if (loading) LinearProgressIndicator(progress = { progress / 100f }, modifier = Modifier.fillMaxWidth().height(2.dp), trackColor = Color.Transparent, gapSize = 0.dp, drawStopIndicator = {})
        error?.let { ErrorNotice(it) { error = null; web.reload() } }
        AndroidView({ web }, Modifier.weight(1f).fillMaxWidth())
    }
}
