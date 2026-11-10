package com.review.compose

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.IOException

internal fun placeRegionCode(id: String): String? = Regex("80086([1-9][0-9]{5})0{8}")
    .matchEntire(id)?.groupValues?.get(1)

private suspend fun placeRegionName(context: Context, id: String): String {
    val code = placeRegionCode(id) ?: return ""
    return withContext(Dispatchers.IO) {
        context.assets.open("place_regions.tsv").bufferedReader().useLines { rows ->
            rows.firstOrNull { it.startsWith("$code\t") }?.substringAfter('\t').orEmpty()
        }
    }
}

internal suspend fun Repository.linkedPlace(cookie: String, id: String, queries: List<String>): JSONObject {
    require(id.matches(Regex("[A-Za-z0-9]{8,48}"))) { "地点标识无效" }
    fun matching(items: List<JSONObject>) = items.map(::normalizePlace)
        .firstOrNull { it.optString("poiid").equals(id, true) && it.optString("title").isNotBlank() }
    if (cookie.isNotBlank() && !mobileOnly) {
        for (query in queries.filter(String::isNotBlank).distinct()) {
            matching(picker(cookie, "place", query))?.let { return it }
        }
    }
    val native = nativeGet("place/pois/show", mapOf("poiid" to id))
    matching(listOfNotNull(native?.optJSONObject("data") ?: native))?.let { return it }
    throw IOException("服务暂未返回这个地点的资料")
}

@Composable
internal fun PlaceLinkScreen(id: String, titleHint: String) {
    val model = LocalReview.current
    val context = LocalContext.current
    val cookie = model.sessionCookie
    var retry by remember(id) { mutableIntStateOf(0) }
    var place by remember(id, model.uid) { mutableStateOf<JSONObject?>(null) }
    var error by remember(id, model.uid) { mutableStateOf<String?>(null) }
    LaunchedEffect(id, model.uid, cookie, model.restoringWebSession, retry) {
        if (model.restoringWebSession) return@LaunchedEffect
        error = null
        try {
            val region = placeRegionName(context, id)
            val title = titleHint.trim().removePrefix("📍").trim().takeIf {
                it.length in 2..80 && it !in setOf("网页链接", "微博", "地点", "地理位置") && !it.contains("://")
            }.orEmpty()
            place = model.repository.linkedPlace(cookie, id, listOf(region, title))
        } catch (e: CancellationException) { throw e }
        catch (_: Exception) { error = "暂时无法加载这个地点" }
    }
    val top = LocalContentTop.current
    val result = place
    if (result == null) {
        Box(Modifier.fillMaxSize().padding(top = top), contentAlignment = Alignment.Center) {
            error?.let { ErrorNotice(it) { retry++ } } ?: CircularProgressIndicator()
        }
        return
    }
    val title = result.optString("title")
    val address = result.optString("address").ifBlank { placeSubtitle(result) }.takeUnless { it == title }.orEmpty()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())
        .padding(start = 16.dp, end = 16.dp, top = top + 12.dp, bottom = 24.dp)) {
        ElevatedCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Outlined.Place, null, tint = MaterialTheme.colorScheme.primary)
                    Text(title, style = MaterialTheme.typography.titleLarge)
                }
                if (address.isNotBlank()) Text(address, color = MaterialTheme.colorScheme.onSurfaceVariant)
                result.optLong("checkin_user_num").takeIf { it > 0 }?.let {
                    Text("$it 人签到", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                FilledTonalButton(onClick = hapticClick { model.openSearchResults(title) }) { Text("搜索相关微博") }
            }
        }
    }
}
