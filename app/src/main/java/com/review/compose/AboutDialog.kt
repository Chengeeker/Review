package com.review.compose

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog

@Composable
fun AboutDialog(close: () -> Unit) {
    val context = LocalContext.current; val model = LocalReview.current; val colors = MaterialTheme.colorScheme
    val icon = listOf(R.mipmap.ic_launcher, R.mipmap.ic_launcher_alias1, R.mipmap.ic_launcher_alias2)[model.number("icon", 0f).toInt().coerceIn(0, 2)]
    ReviewDialog(onDismissRequest = close) {
        Surface(shape = RoundedCornerShape(20.dp), color = colors.surfaceContainerHigh) {
            Column(Modifier.verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, top = 24.dp, bottom = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Image(painterResource(icon), "Review", Modifier.size(72.dp).clip(RoundedCornerShape(18.dp)))
                Spacer(Modifier.height(14.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Review", fontSize = 21.sp, fontWeight = reviewWeight(FontWeight.Bold), letterSpacing = .2.sp); Spacer(Modifier.width(8.dp))
                    Text("v${BuildConfig.VERSION_NAME}", Modifier.background(colors.primaryContainer, RoundedCornerShape(8.dp)).padding(horizontal = 8.dp, vertical = 2.5.dp), color = colors.onPrimaryContainer, fontSize = 12.sp, fontWeight = reviewWeight(FontWeight.Bold))
                }
                Spacer(Modifier.height(6.dp)); Text("基于 Lucent UI 的原生客户端", fontSize = 13.sp, color = colors.onSurfaceVariant)
                Spacer(Modifier.height(26.dp))
                Row(Modifier.fillMaxWidth().background(colors.surfaceContainerHighest.copy(alpha = .5f), RoundedCornerShape(12.dp)).border(1.dp, colors.outlineVariant.copy(alpha = .4f), RoundedCornerShape(12.dp)).reviewClickable {
                    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/Chengeeker/Review"))) }.onFailure { model.notice = "没有可打开链接的应用" }
                }.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Code, null, Modifier.size(20.dp), colors.primary); Spacer(Modifier.width(10.dp))
                    Text("GitHub 开源地址", Modifier.weight(1f), fontSize = 13.sp, fontWeight = reviewWeight(FontWeight.Bold))
                    Icon(Icons.Outlined.OpenInNew, null, Modifier.size(16.dp), colors.primary)
                }
                Spacer(Modifier.height(24.dp)); Button(onClick = hapticClick(close), shape = RoundedCornerShape(12.dp), contentPadding = PaddingValues(horizontal = 24.dp, vertical = 10.dp)) { Text("我知道了") }
            }
        }
    }
}
