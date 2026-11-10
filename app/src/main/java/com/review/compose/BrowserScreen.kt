@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.webkit.*
import android.widget.FrameLayout
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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

internal fun browserCookieDomain(url: String): String? {
    val uri = runCatching { java.net.URI(url) }.getOrNull() ?: return null
    val host = uri.host?.lowercase() ?: return null
    if (uri.scheme != "https" || uri.userInfo != null || uri.port !in setOf(-1, 443)) return null
    return listOf("weibo.com", "weibo.cn").firstOrNull { host == it || host.endsWith(".$it") }
}

private fun browserCookiePairs(value: String): Map<String, String> = value.split(';').mapNotNull {
        val name = it.substringBefore('=').trim()
        val content = it.substringAfter('=', "").trim()
        if ('=' in it && name.matches(Regex("[A-Za-z0-9_!#$%&'*+.^`|~-]+"))) name to content else null
}.toMap()

internal fun browserCookieWrites(url: String, cookie: String, existing: String): List<Pair<String, String>> {
    val domain = browserCookieDomain(url) ?: return emptyList()
    if (cookie.length > 32768 || cookie.any { it !in ' '..'~' }) return emptyList()
    val current = browserCookiePairs(cookie)
    val present = browserCookiePairs(existing)
    val known = current["SUB"]?.takeIf(String::isNotBlank)
    // Keep tickets and preferences the site set for the current session.
    if (known != null && present["SUB"] == known && current.all { (name, value) -> present[name] == value }) return emptyList()
    val names = present.keys + current.keys
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
    val route = LocalReviewRoute.current
    val currentActive by rememberUpdatedState(active)
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    var revision by remember(url) { mutableIntStateOf(0) }
    val web = remember(url, model.uid, model.sessionCookie, revision) {
        runCatching {
            WebView(context).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                if (browserCookieDomain(secureImage(url)) == "weibo.com") settings.userAgentString = ApiClient.USER_AGENT
                CookieManager.getInstance().setAcceptThirdPartyCookies(this, false)
            }
        }.getOrNull()
    }
    var rendererGone by remember(web) { mutableStateOf(false) }
    val preparedDomains = remember(web) { mutableSetOf<String>() }
    var redirect by remember(web) { mutableStateOf<Pair<Int, String>?>(null) }
    suspend fun load(target: String) {
        if (web == null || rendererGone) return
        try {
            val domain = browserCookieDomain(target)
            if (domain != null && domain !in preparedDomains) {
                val owner = model.uid
                val source = model.sessionCookie
                val manager = CookieManager.getInstance()
                val existing = manager.getCookie(target).orEmpty()
                val cookie = model.verifiedBrowserCookie(domain, existing)
                if (rendererGone || model.uid != owner || model.sessionCookie != source) return
                for ((address, value) in browserCookieWrites(target, cookie, existing)) {
                    suspendCancellableCoroutine<Unit> { continuation ->
                        manager.setCookie(address, value) { if (continuation.isActive) continuation.resume(Unit) }
                    }
                }
                preparedDomains += domain
            }
            if (rendererGone) return
            current = target; progress = 0; loading = true; error = null
            web.loadUrl(target)
        } catch (e: CancellationException) { throw e }
        catch (_: RuntimeException) { error = "网页暂时无法打开"; loading = false }
    }
    if (web != null) DisposableEffect(web) {
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
                if (currentActive && (route == null || model.routeStack.lastOrNull() === route) &&
                    runCatching { model.openNativeLink(target) }.getOrDefault(false)) {
                    if (route != null) model.routeStack.remove(route)
                    return true
                }
                val domain = browserCookieDomain(target)
                if (target != request.url.toString() || (domain != null && domain !in preparedDomains)) {
                    redirect = (1 + (redirect?.first ?: 0)) to target
                    return true
                }
                return false
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, failure: WebResourceError) {
                if (request.isForMainFrame) { error = "页面加载失败"; loading = false }
            }
            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                rendererGone = true; error = "网页浏览已中断，请重试"; loading = false
                (view.parent as? FrameLayout)?.removeView(view)
                view.destroy()
                return true
            }
        }
        onDispose {
            if (!rendererGone) {
                (web.parent as? FrameLayout)?.removeView(web)
                web.stopLoading(); web.webChromeClient = null; web.webViewClient = WebViewClient(); web.destroy()
            }
        }
    }
    LaunchedEffect(web, redirect) {
        val target = redirect?.second ?: current.ifBlank { secureImage(url) }
        when {
            web == null -> { error = "系统网页组件暂不可用"; loading = false }
            target.isBlank() -> { error = "页面地址无效"; loading = false }
            else -> load(target)
        }
    }
    LaunchedEffect(web, active, lifecycle, rendererGone) {
        if (web != null && !rendererGone) {
            if (active && lifecycle.isAtLeast(Lifecycle.State.STARTED)) web.onResume() else web.onPause()
        }
    }
    fun retry() {
        error = null
        if (web == null || rendererGone) revision++
        else scope.launch { load(current.ifBlank { secureImage(url) }) }
    }
    BackHandler(active) { if (web != null && !rendererGone && web.canGoBack()) web.goBack() else model.back() }
    Column(Modifier.fillMaxSize()) {
        TopAppBar(title = {
            Column(Modifier.padding(start = 16.dp)) {
                Text(title, fontSize = 16.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (current.isNotBlank()) Text(current, fontSize = 11.sp, color = colors.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }, modifier = Modifier.frostedBackdrop(colors.background), expandedHeight = 56.dp,
            colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
            navigationIcon = { IconButton(onClick = hapticClick(model::back)) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回") } }, actions = {
                IconButton(onClick = hapticClick { retry() }) { Icon(Icons.Rounded.Refresh, "刷新") }
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
        error?.let { ErrorNotice(it, ::retry) }
        if (web != null && !rendererGone) key(web) {
            AndroidView({ ctx -> FrameLayout(ctx).apply { addView(web, FrameLayout.LayoutParams(-1, -1)) } },
                Modifier.weight(1f).fillMaxWidth())
        }
    }
}
