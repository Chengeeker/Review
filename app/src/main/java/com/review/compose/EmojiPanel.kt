package com.review.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Backspace
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import org.json.JSONArray

@Composable
fun EmojiPanel(backspace: () -> Unit = {}, select: (String) -> Unit) {
    val context = LocalContext.current
    val groups = remember { context.assets.open("emoji.json").bufferedReader().use { JSONArray(it.readText()).objects() } }
    var index by remember { mutableIntStateOf(0) }
    Column(Modifier.height(240.dp)) {
        ReviewDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .3f))
        Row(Modifier.height(36.dp).background(MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = .3f)), verticalAlignment = Alignment.CenterVertically) {
            groups.forEachIndexed { i, item ->
                Column(Modifier.width(60.dp).fillMaxHeight().reviewClickable { index = i }, horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { Text(item.getString("title"), fontSize = 14.sp, color = if (index == i) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) }
                    Box(Modifier.height(2.dp).width(28.dp).background(if (index == i) MaterialTheme.colorScheme.primary else androidx.compose.ui.graphics.Color.Transparent))
                }
            }
            Spacer(Modifier.weight(1f))
            IconButton(onClick = hapticClick(backspace)) { Icon(Icons.Outlined.Backspace, "删除", Modifier.size(20.dp)) }
        }
        key(index) {
            LazyVerticalGrid(GridCells.Fixed(7), Modifier.weight(1f), contentPadding = PaddingValues(8.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                items(groups[index].getJSONArray("items").objects(), key = { it.getString("phrase") }) { item ->
                    val phrase = item.getString("phrase")
                    Box(Modifier.aspectRatio(1f).semantics { contentDescription = phrase }.reviewClickable { select(phrase) },
                        contentAlignment = Alignment.Center) { Text(item.getString("char"), fontSize = 24.sp) }
                }
            }
        }
    }
}

fun TextFieldValue.insertPhrase(phrase: String): TextFieldValue {
    val start = selection.min.coerceIn(0, text.length)
    val end = selection.max.coerceIn(start, text.length)
    return TextFieldValue(text.replaceRange(start, end, phrase), TextRange(start + phrase.length))
}

fun TextFieldValue.erasePhrase(): TextFieldValue {
    val end = selection.max.coerceIn(0, text.length)
    var start = selection.min.coerceIn(0, end)
    if (start == end) {
        if (start == 0) return this
        start = Regex("\\[[a-zA-Z0-9\\u4e00-\\u9fa5]+]$").find(text.substring(0, start))?.range?.first
            ?: text.offsetByCodePoints(start, -1)
    }
    return TextFieldValue(text.removeRange(start, end), TextRange(start))
}
