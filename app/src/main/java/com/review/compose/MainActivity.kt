@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.review.compose

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.automirrored.outlined.Login
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val model: ReviewModel = viewModel()
            LaunchedEffect(model.ready, model.number("refreshRate", 0f)) { if (model.ready) applyRefreshRate(this@MainActivity, model.number("refreshRate", 0f).toInt()) }
            ReviewApp(model)
        }
    }
}

@Composable
internal fun LoadingRow() { Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(28.dp), strokeWidth = 2.dp) } }

@Composable
internal fun SavedScreen(model: ReviewModel, gallery: (List<Media>, Int) -> Unit) {
    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.fillMaxSize()) {
        item { Text("保存在本机，按账号隔离；最多保留最近 200 条。", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        if (model.bookmarks.isEmpty()) item { EmptyNotice("还没有收藏", "在动态右上角轻点书签，即可保存。") }
        items(model.bookmarks, key = { it.id }) { post -> PostCard(post, true, { model.openPost(post) }, { model.bookmark(post) }, gallery, model::openPost) }
    }
}

@Composable
internal fun SectionLabel(text: String) { Text(text, Modifier.padding(start = 16.dp, top = 4.dp).semantics { heading() }, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.titleSmall) }

@Composable
internal fun SettingRow(icon: ImageVector, title: String, subtitle: String, onClick: () -> Unit) {
    ReviewListItem(headlineContent = { Text(title) }, supportingContent = { Text(subtitle) }, leadingContent = { Icon(icon, null, tint = MaterialTheme.colorScheme.primary) },
        trailingContent = { Icon(Icons.Outlined.ChevronRight, null) }, modifier = Modifier.reviewClickable(onClick = onClick).padding(vertical = 5.dp),
        colors = ListItemDefaults.colors(containerColor = Color.Transparent))
}

@Composable
internal fun WebLoginScreen(model: ReviewModel) {
    val context = LocalContext.current
    var error by remember { mutableStateOf<String?>(null) }
    val webView = remember {
        WebView(context).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
            settings.userAgentString = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val uri = request.url; val host = uri.host.orEmpty()
                    return uri.scheme != "https" || listOf("weibo.com", "weibo.cn", "sina.com.cn", "sina.cn").none { host == it || host.endsWith(".$it") }
                }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, failure: android.webkit.WebResourceError) {
                    if (request.isForMainFrame) error = "登录页面未能加载，请检查网络后重试"
                }
            }
            loadUrl("https://weibo.com/login.php")
        }
    }
    DisposableEffect(webView) { onDispose {
        webView.stopLoading()
        CookieManager.getInstance().removeAllCookies { CookieManager.getInstance().flush() }
        android.webkit.WebStorage.getInstance().deleteAllData()
        webView.clearCache(true)
        webView.destroy()
    } }
    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top))) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = hapticClick(model::back)) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回账号") }
            Text("网页登录", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
            TextButton(onClick = hapticClick {
                CookieManager.getInstance().flush()
                model.login(CookieManager.getInstance().getCookie("https://weibo.com/").orEmpty())
            }, enabled = !model.accountLoading) { Text("完成并验证") }
        }
        if (model.accountLoading) LinearProgressIndicator(Modifier.fillMaxWidth())
        model.accountError?.let { Text(it, Modifier.padding(12.dp), color = MaterialTheme.colorScheme.error) }
        error?.let { ErrorNotice(it) { error = null; webView.reload() } }
        AndroidView(factory = { webView }, modifier = Modifier.weight(1f).fillMaxWidth())
    }
}
