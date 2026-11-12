@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Article
import androidx.compose.material.icons.outlined.BrokenImage
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.LastBaseline
import androidx.compose.ui.layout.AlignmentLine
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.constrainHeight
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import coil.compose.SubcomposeAsyncImage
import coil.compose.SubcomposeAsyncImageContent
import coil.request.ImageRequest

data class ArticleInline(val text: String, val url: String = "")
data class ArticleBlock(val text: String = "", val inlines: List<ArticleInline> = emptyList(), val heading: Boolean = false, val image: String = "", val ratio: Float = 1.5f, val caption: String = "")
data class Article(val title: String, val author: String, val uid: String, val avatar: String, val publishedAt: String, val metadata: String, val cover: String, val blocks: List<ArticleBlock>)
fun parseArticle(html: String): Article {
    val doc = Jsoup.parse(html, "https://weibo.com/")
    val author = doc.selectFirst(".authorinfo")
    val owner = author?.selectFirst("a[href*=/u/]")
    val blocks = mutableListOf<ArticleBlock>()
    fun clean(text: String) = text.replace(Regex("[\u200B\u200C\u200D\uFEFF]"), "").lines().map { it.replace(Regex("\\s+"), " ").trim() }.filter(String::isNotEmpty).joinToString("\n")
    fun url(raw: String): String = secureImage(if (raw.trim().startsWith('/') && !raw.trim().startsWith("//")) "https://weibo.com${raw.trim()}" else raw.trim())
    fun imageUrl(element: Element?): String {
        if (element == null) return ""
        val candidates = element.attr("srcset").split(',').mapNotNull { item ->
            val parts = item.trim().split(Regex("\\s+"))
            val address = url(parts.first())
            if (address.isBlank()) null else address to (Regex("(\\d+)w").find(parts.getOrElse(1) { "" })?.groupValues?.get(1)?.toIntOrNull() ?: 0)
        }
        if (candidates.isNotEmpty()) return (candidates.filter { it.second in 1..1024 }.ifEmpty { candidates }.maxBy { it.second }).first
        return listOf("data-original", "data-src", "data-lazy-src", "src").firstNotNullOfOrNull { url(element.attr(it)).takeIf(String::isNotBlank) }.orEmpty()
    }
    fun image(element: Element, caption: String = "") {
        val url = imageUrl(element)
        if (url.isBlank()) return
        val ratio = element.attr("aspect").toFloatOrNull()?.takeIf { it.isFinite() && it > .15f && it < 8f } ?: 1.5f
        if (blocks.size < 5000) blocks += ArticleBlock(image = url, ratio = ratio, caption = caption)
    }
    fun inlines(element: Element): List<ArticleInline> {
        val result = mutableListOf<ArticleInline>()
        fun walk(node: org.jsoup.nodes.Node, activeUrl: String, depth: Int) {
            if (depth > 40) return
            if (node is org.jsoup.nodes.TextNode) result += ArticleInline(node.wholeText.replace(Regex("\\s+"), " "), activeUrl)
            if (node is Element) {
                val nextUrl = if (node.tagName() == "a") url(listOf("href", "data-href", "data-url").firstNotNullOfOrNull { key -> node.attr(key).takeIf { node.hasAttr(key) } }.orEmpty()).ifBlank { activeUrl } else activeUrl
                if (node.tagName() == "br") result += ArticleInline(" ", activeUrl) else node.childNodes().forEach { walk(it, nextUrl, depth + 1) }
            }
        }
        walk(element, "", 0)
        return result
    }
    fun walk(element: Element, depth: Int) {
        if (depth > 40 || blocks.size >= 5000) return
        val tag = element.tagName()
        if (tag in setOf("script", "style", "noscript", "iframe", "button", "figcaption")) return
        when {
            tag == "figure" -> element.select("img").forEach { image(it, clean(element.selectFirst("figcaption")?.text().orEmpty())) }
            tag == "img" -> image(element)
            tag in setOf("p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "li", "a") -> {
                val text = clean(element.wholeText())
                if (text.isNotBlank()) blocks += ArticleBlock(text, inlines(element), tag.startsWith('h') || (tag != "a" && element.selectFirst("strong") != null && text.length <= 80))
                if (tag != "a") element.select("img").forEach { image(it) }
            }
            element.select("img").isNotEmpty() -> {
                val text = clean(element.wholeText())
                if (text.isNotBlank()) blocks += ArticleBlock(text)
                element.select("img").forEach { image(it) }
            }
            else -> if (element.children().isEmpty() && element.text().isNotBlank()) blocks += ArticleBlock(clean(element.wholeText())) else element.children().forEach { walk(it, depth + 1) }
        }
    }
    (doc.selectFirst("[node-type=contentBody]") ?: doc.selectFirst(".WB_editor_iframe"))?.children()?.forEach { walk(it, 0) }
    val published = clean(author?.selectFirst(".time")?.text().orEmpty())
    return Article(clean(doc.selectFirst("[node-type=articleTitle]")?.text().orEmpty()).ifBlank { clean(doc.title()).replace(Regex("\\s*[-|｜]\\s*微博\\s*$"), "") }.ifBlank { "微博文章" }, clean((owner?.selectFirst("em") ?: owner)?.text().orEmpty()), Regex("/u/(\\d+)(?:[/?#]|$)").find(owner?.attr("href").orEmpty())?.groupValues?.get(1).orEmpty(),
        url(author?.selectFirst("img.W_face_radius")?.attr("src").orEmpty()), published, listOf(published, clean(author?.selectFirst(".num")?.text().orEmpty())).filter(String::isNotBlank).joinToString("  "), imageUrl(doc.selectFirst("[node-type=articleHeaderPic]")), blocks)
}
private val articleCache = android.util.LruCache<String, Article>(8)

@Composable
fun ArticleScreen(id: String, gallery: (List<Media>, Int) -> Unit) {
    val model = LocalReview.current
    val scope = rememberCoroutineScope()
    val key = "${model.uid}:$id"
    val source = remember(key) { model.articleSource }
    val origins = remember(key) { mutableMapOf<Int, GalleryOrigin>() }
    val openFrom = LocalGalleryOpenFrom.current
    var article by remember(key) { mutableStateOf(articleCache.get(key)) }
    var busy by remember(key) { mutableStateOf(false) }
    var error by remember(key) { mutableStateOf<String?>(null) }
    suspend fun load() {
        if (busy) return
        busy = true; error = null
        try {
            require(id.matches(Regex("[0-9]+"))) { "文章地址无效" }
            var parsed: Article? = null
            for (cookie in listOf(model.sessionCookie, "").distinct()) {
                try {
                    val html = model.repository.api.raw(ApiClient.DESKTOP + "/ttarticle/p/show", cookie, mapOf("id" to id), html = true).text
                    val candidate = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { parseArticle(html) }
                    if (candidate.blocks.isNotEmpty()) { parsed = candidate; break }
                } catch (e: CancellationException) { throw e } catch (_: Exception) { }
            }
            article = parsed ?: error("微博文章正文暂不可用")
            if (model.uid.isNotBlank()) articleCache.put(key, parsed)
        } catch (e: CancellationException) { throw e } catch (e: Exception) { error = e.message }
        finally { busy = false }
    }
    LaunchedEffect(key) { if (article == null) load() }
    val colors = MaterialTheme.colorScheme
    if (article == null && (busy || error == null)) { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }; return }
    val pulse = reviewPulse()
    PullToRefreshBox(busy, hapticClick { scope.launch { load() } }) {
        SelectionContainer {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = if (article == null) PaddingValues(horizontal = 28.dp, vertical = 120.dp) else PaddingValues(start = 16.dp, top = LocalContentTop.current + 12.dp, end = 16.dp, bottom = 32.dp)) {
            if (error != null && article == null) item {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Outlined.Article, null, Modifier.size(56.dp), tint = colors.outline)
                    Spacer(Modifier.height(16.dp)); Text("文章加载失败", style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(8.dp)); Text("请检查网络或登录状态后重试", style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(20.dp)); Button(hapticClick { scope.launch { load() } }, Modifier.fillMaxWidth()) { Icon(Icons.Rounded.Refresh, null); Spacer(Modifier.width(8.dp)); Text("重新加载") }
                }
            }
            article?.let { document ->
                val media = document.blocks.filter { it.image.isNotBlank() }.map { Media(it.image) }
                if (document.cover.isNotBlank()) item { ArticleImage(document.cover, "文章封面", 1.78f) }
                item { Text(document.title, Modifier.articleLineHeight(30.sp), style = MaterialTheme.typography.headlineSmall, fontSize = 24.sp, lineHeight = 30.sp, fontWeight = reviewWeight(FontWeight.Bold)) }
                item {
                    if (document.author.isNotBlank() || document.publishedAt.isNotBlank()) Row(Modifier.padding(top = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (document.author.isNotBlank()) { Avatar(document.author, source?.takeIf { it.uid == document.uid && it.avatar.isNotBlank() }?.avatar ?: document.avatar, Modifier.size(36.dp)); Spacer(Modifier.width(10.dp)) }
                        Text(listOf(document.author, document.metadata).filter(String::isNotBlank).joinToString("  "), Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                    }
                    Spacer(Modifier.height(22.dp))
                }
                itemsIndexed(document.blocks) { index, block ->
                    if (block.image.isNotBlank()) {
                        val mediaIndex = document.blocks.take(index).count { it.image.isNotBlank() }
                        val origin = remember(block.image, mediaIndex) { GalleryOrigin(14.dp, crop = false) }
                        DisposableEffect(origin) { origins[mediaIndex] = origin; onDispose { if (origins[mediaIndex] === origin) origins.remove(mediaIndex) } }
                        ArticleImage(block.image, block.caption.ifBlank { "文章图片" }, block.ratio,
                            modifier = Modifier.onGloballyPositioned { origin.coordinates = it }.graphicsLayer { alpha = if (origin.covered) 0f else 1f },
                            onBitmap = { origin.bitmap = it }) {
                            model.mediaAuthor = document.author
                            if (openFrom != null && origin.anchor() != null) openFrom(media, mediaIndex, origins) else gallery(media, mediaIndex)
                        }
                        if (block.caption.isNotBlank()) Text(block.caption, Modifier.fillMaxWidth().padding(top = 5.dp, bottom = 12.dp), style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center)
                    } else if (block.heading) Text(block.text, Modifier.padding(top = 14.dp, bottom = 8.dp).articleLineHeight(29.7.sp), style = MaterialTheme.typography.titleLarge, fontSize = 22.sp, lineHeight = 29.7.sp, fontWeight = reviewWeight(FontWeight.Bold))
                    else {
                        val text = buildAnnotatedString {
                            if (block.inlines.none { it.url.isNotBlank() }) append(block.text)
                            else block.inlines.forEach { part ->
                                if (part.url.isBlank()) append(part.text)
                                else withLink(LinkAnnotation.Clickable(part.url, TextLinkStyles(SpanStyle(color = MaterialTheme.colorScheme.primary))) { pulse(); model.openLink(part.url) }) { append(part.text) }
                            }
                        }
                        InlineLinkTargets { Text(text, Modifier.padding(bottom = 14.dp).articleLineHeight(29.75.sp), fontSize = 17.sp, lineHeight = 29.75.sp) }
                    }
                }
            }
        }
        }
    }
}

@Composable
private fun Modifier.articleLineHeight(lineHeight: TextUnit): Modifier {
    val pixels = with(LocalDensity.current) { lineHeight.toPx() }
    return layout { measurable, constraints ->
        val text = measurable.measure(constraints)
        val first = text[FirstBaseline]; val last = text[LastBaseline]
        // Android adds fallback-font padding even to explicit line heights; Flutter uses the line box.
        val height = if (first == AlignmentLine.Unspecified || last == AlignmentLine.Unspecified) text.height else constraints.constrainHeight(kotlin.math.ceil(last - first + pixels).toInt())
        layout(text.width, height) { text.placeRelative(0, (height - text.height) / 2) }
    }
}

@Composable
private fun ArticleImage(url: String, description: String, ratio: Float, modifier: Modifier = Modifier,
    onBitmap: ((android.graphics.Bitmap) -> Unit)? = null, open: (() -> Unit)? = null) {
    val colors = MaterialTheme.colorScheme
    SubcomposeAsyncImage(ImageRequest.Builder(LocalContext.current).data(url).size(2048).build(), description,
        Modifier.padding(bottom = 16.dp).then(modifier).fillMaxWidth().aspectRatio(ratio).clip(RoundedCornerShape(14.dp)).background(colors.surfaceContainerHighest.copy(alpha = .35f)).then(if (open == null) Modifier else Modifier.reviewClickable(onClick = open)), contentScale = ContentScale.Fit,
        success = { state -> SideEffect { (state.result.drawable as? android.graphics.drawable.BitmapDrawable)?.bitmap?.let { onBitmap?.invoke(it) } }; SubcomposeAsyncImageContent() },
        loading = { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() } },
        error = { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(Icons.Outlined.BrokenImage, null, Modifier.size(36.dp), tint = colors.outline) } })
}
