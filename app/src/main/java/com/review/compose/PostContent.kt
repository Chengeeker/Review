package com.review.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.MotionPhotosOn
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.VideoLibrary
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.BiasAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException

@Composable
internal fun HdrBadge(modifier: Modifier = Modifier, description: String = "HDR 图片", compact: Boolean = false) {
    Text("HDR", modifier.semantics { contentDescription = description }
        .background(Color.Black.copy(alpha = .4f), RoundedCornerShape(4.dp))
        .padding(horizontal = if (compact) 3.dp else 6.dp, vertical = if (compact) 1.dp else 2.dp),
        color = Color.White, fontSize = if (compact) 8.sp else 10.sp, lineHeight = if (compact) 9.sp else 12.sp,
        fontWeight = FontWeight.Normal)
}

@Composable
fun PostBody(post: Post, detail: Boolean, gallery: (List<Media>, Int) -> Unit, quoted: Boolean = false) {
    val model = LocalReview.current
    val cookie = model.sessionCookie
    var expanded by rememberSaveable(post.id) { mutableStateOf(false) }
    var full by remember(post.id, post.raw, cookie) {
        mutableStateOf(post.availableFullText().ifBlank { if (post.longText) cachedFullText(cookie, post.id) else "" })
    }
    var loading by remember(post.id, cookie) { mutableStateOf(false) }
    var error by remember(post.id, cookie) { mutableStateOf<String?>(null) }
    var retry by remember(post.id, cookie) { mutableIntStateOf(0) }
    LaunchedEffect(post.id, post.raw, post.longText, cookie, model.restoringWebSession, retry) {
        if (!post.longText || post.demo || full.isNotBlank() || model.restoringWebSession) return@LaunchedEffect
        loading = true; error = null
        try { full = model.repository.fullText(cookie, post.id) }
        catch (e: CancellationException) { throw e }
        catch (e: Exception) { if (expanded) error = e.message ?: "全文加载失败"; expanded = false }
        finally { loading = false }
    }
    val font = model.number("postFont", 16f) - if (quoted) 1f else 0f
    val body = if ((detail || expanded) && full.isNotBlank()) full else post.text
    val caption = post.images.singleOrNull()?.birthdayCaption().orEmpty()
    val text = remember(body, post.images, caption) {
        val withoutLinks = body.withoutWebCardLinks(post.images)
        if (caption.isEmpty()) withoutLinks else {
            val captionPattern = caption.split(Regex("\\s+")).joinToString("\\s*") { Regex.escape(it) }.toRegex()
            withoutLinks.replaceFirst(captionPattern, "").trim()
        }
    }
    if (quoted || text.isNotBlank()) RichText(if (quoted) "@${post.author}：$text" else text, post, style = MaterialTheme.typography.bodyLarge.copy(fontSize = font.sp, lineHeight = (font * model.number("postLine", 1.3f)).sp, color = if (quoted) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface))
    if (!detail && post.longText && (full.isBlank() || full.trim().length > post.text.trim().length)) {
        TextButton(onClick = hapticClick {
            if (full.isNotBlank()) expanded = !expanded
            else { expanded = true; if (!loading) retry++ }
        }, contentPadding = PaddingValues(0.dp)) { Text(if (loading && expanded) "加载中…" else if (expanded && full.isNotBlank()) "收起全文" else "展开全文") }
    }
    error?.let { Text(it, fontSize = 12.sp, color = MaterialTheme.colorScheme.error) }
    if (post.images.isNotEmpty()) {
        Spacer(Modifier.height(10.dp))
        val single = post.images.singleOrNull()
        val native = post.data.optJSONObject("page_info")?.let(::videoMedia)
        if (single != null && native != null && single.sameVideo(native)) NativeVideoPreview(post, single)
        else MediaGrid(post, detail, gallery)
    }
    if (parsePoll(post.data) != null) { Spacer(Modifier.height(10.dp)); PollCard(post) }
    if (!quoted) post.repost?.let { quote ->
        Spacer(Modifier.height(10.dp))
        Surface(color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = .5f), shape = RoundedCornerShape(if (model.option("cardLayout") == "flat_tile") 6.dp else 16.dp), border = androidx.compose.foundation.BorderStroke(.7.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = .2f)), modifier = Modifier.fillMaxWidth().reviewClickable { model.openPost(quote) }) {
            Column(Modifier.padding(12.7.dp)) { PostBody(quote, detail, gallery, true) }
        }
    }
}

@Composable
fun MediaGrid(post: Post, detail: Boolean, gallery: (List<Media>, Int) -> Unit) {
    val model = LocalReview.current
    val shown = if (detail) post.images else post.images.take(9)
    val large = model.bool("largeImages", true)
    val rounded = model.bool("roundImages", true)
    val columns = when (shown.size) { 1 -> 1; 2, 4 -> 2; else -> 3 }
    val spacing = if (large) 7.dp else 5.dp
    val openFrom = LocalGalleryOpenFrom.current
    val sources = remember(post.id, rounded) { mutableMapOf<Int, GalleryOrigin>() }
    @Composable fun Cell(media: Media, index: Int, modifier: Modifier) {
        val radius = if (rounded) if (columns == 1) 16.dp else 12.dp else 0.dp
        val source = remember(sources, index, media.url, radius) { GalleryOrigin(radius) }
        DisposableEffect(source) { sources[index] = source; onDispose { if (sources[index] === source) sources.remove(index) } }
        Box(modifier.onGloballyPositioned { source.coordinates = it }.graphicsLayer { alpha = if (source.covered) 0f else 1f }.clip(RoundedCornerShape(radius)).background(if (media.card) Color.White else Color.Transparent).reviewClickable {
            model.mediaAuthor = post.author
            if (media.article.isNotBlank()) { model.articleSource = post; model.openLink(media.article) }
            else if (openFrom != null && source.anchor() != null && (media.video.isBlank() || media.live)) openFrom(post.images, index, sources)
            else gallery(post.images, index)
        }) {
            val description = "${post.author}的第 ${index + 1} 张图片"
            if (media.card) WebCardImage(media, description, Modifier.fillMaxSize(), caption = columns == 1, onBitmap = { source.bitmap = it })
            else MediaImage(media.copy(url = media.preview.ifBlank { media.url }), description, Modifier.fillMaxSize(), media.article.isNotBlank(),
                onBitmap = { source.bitmap = it })
            if (media.video.isNotBlank() && !media.live) Box(Modifier.size(if (columns == 1) 44.dp else 36.dp).align(Alignment.Center).background(Color.Black.copy(alpha = .55f), CircleShape), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.PlayArrow, "播放视频", Modifier.size(if (columns == 1) 28.dp else 22.dp), tint = Color.White) }
            val gif = media.gif || media.url.substringBefore('?').endsWith(".gif", true)
            val long = media.long || (media.width > 0 && media.height.toFloat() / media.width > 2f)
            LaunchedEffect(media.url, media.canHaveHdrBadge) {
                if (media.canHaveHdrBadge) MediaFiles.probeHdr(media.url)
            }
            Column(Modifier.align(Alignment.BottomEnd).padding(if (columns == 1) 6.dp else 4.dp), horizontalAlignment = Alignment.End) {
                if (MediaFiles.hasHdrBadge(media)) {
                    HdrBadge()
                    if (long) Spacer(Modifier.height(2.dp))
                }
                if (media.live) Row(Modifier.background(Color.Black.copy(alpha = .72f), RoundedCornerShape(10.dp)).padding(horizontal = 5.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.MotionPhotosOn, null, Modifier.size(11.dp), tint = Color.White); Spacer(Modifier.width(2.5.dp))
                    Text("LIVE", color = Color.White, fontSize = 9.sp, fontWeight = reviewWeight(FontWeight.Bold), letterSpacing = .4.sp)
                } else if (media.video.isNotBlank()) MediaBadge(media.duration.ifBlank { "视频" })
                else if (gif || long) MediaBadge(if (gif) "GIF" else "长图")
            }
            if (!detail && index == 8 && post.images.size > 9) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .45f)), contentAlignment = Alignment.Center) { Text("+${post.images.size - 9}", color = Color.White, fontSize = 24.sp, fontWeight = reviewWeight(FontWeight.SemiBold)) }
        }
    }
    if (columns == 1) {
        val media = shown.first()
        val ratio = media.thumbnailAspect.takeIf { it > 0f } ?: if (media.width > 0 && media.height > 0) (media.width.toFloat() / media.height).coerceIn(.5f, 2f) else 1f
        val maximum = if (large) 260.dp else 190.dp
        Cell(media, 0, Modifier.width(if (ratio < 1) maximum * ratio else maximum).aspectRatio(ratio))
    } else Column(verticalArrangement = Arrangement.spacedBy(spacing)) {
        shown.chunked(columns).forEachIndexed { row, media -> Row(horizontalArrangement = Arrangement.spacedBy(spacing)) {
            media.forEachIndexed { column, item -> Cell(item, row * columns + column, Modifier.weight(1f).aspectRatio(1f)) }
            repeat(columns - media.size) { Spacer(Modifier.weight(1f)) }
        } }
    }
}

@Composable
internal fun WebCardImage(media: Media, description: String, modifier: Modifier, caption: Boolean, onBitmap: ((android.graphics.Bitmap) -> Unit)? = null) {
    val layer = if (onBitmap != null) rememberGraphicsLayer() else null
    var recorded by remember(layer) { mutableStateOf(false) }
    var foreground by remember(media.url) { mutableStateOf<android.graphics.Bitmap?>(null) }
    var background by remember(media.background) { mutableStateOf<android.graphics.Bitmap?>(null) }
    val latestBitmap by rememberUpdatedState(onBitmap)
    val layered = media.background.isNotBlank() && media.background != media.url
    LaunchedEffect(layer, recorded, foreground, background, media, caption) {
        if (layer != null && recorded && foreground != null && (!layered || background != null)) {
            withFrameNanos {}
            latestBitmap?.invoke(layer.toImageBitmap().asAndroidBitmap())
        }
    }
    BoxWithConstraints(modifier.then(if (layer == null) Modifier else Modifier.drawWithContent {
        layer.record { this@drawWithContent.drawContent() }; recorded = true; drawLayer(layer)
    }).background(Color.White)) {
        if (layered) MediaImage(Media(media.background, card = true), "", Modifier.fillMaxSize(), fit = true, onBitmap = if (layer == null) null else { { background = it } })
        // Card dimensions describe the composite canvas, not the transparent asset.
        MediaImage(media.copy(width = 0, height = 0), description, Modifier.fillMaxSize(), fit = true, overlay = layered,
            onBitmap = if (layer == null) null else { { foreground = it } })
        val greeting = media.birthdayCaption()
        if (caption && greeting.isNotEmpty()) {
            val font = (maxWidth.value * .045f).coerceIn(11f, 16f)
            Text(greeting, Modifier.align(BiasAlignment(0f, .68f)).padding(horizontal = 12.dp), color = Color(0xFFFF8200),
                fontSize = font.sp, lineHeight = (font * 1.35f).sp, maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun MediaBadge(text: String) {
    Text(text, Modifier.background(Color.Black.copy(alpha = .7f), RoundedCornerShape(4.dp)).padding(horizontal = 5.dp, vertical = 2.dp), color = Color.White, fontSize = 10.sp, fontWeight = reviewWeight(FontWeight.Bold))
}

@Composable
private fun NativeVideoPreview(post: Post, media: Media) {
    val model = LocalReview.current
    val info = post.data.optJSONObject("page_info")?.optJSONObject("media_info")
    val count = info?.optLong("play_count", info.optLong("online_users_number")) ?: 0
    Box(Modifier.fillMaxWidth().aspectRatio(16f / 9).clip(RoundedCornerShape(12.dp)).background(Color.Black).reviewClickable {
        model.mediaAuthor = post.author
        model.navigate("video:${android.net.Uri.encode(media.video)}")
        model.routeStack.last().media = media
        model.routeStack.last().post = post
    }) {
        if (media.url.isNotBlank()) MediaImage(media, "${post.author}的视频封面", Modifier.fillMaxSize())
        else Icon(Icons.Rounded.VideoLibrary, null, Modifier.size(36.dp).align(Alignment.Center), tint = Color.White.copy(alpha = .7f))
        Surface(Modifier.size(52.dp).align(Alignment.Center), color = Color.Black.copy(alpha = .54f), shape = CircleShape, border = androidx.compose.foundation.BorderStroke(1.5.dp, Color.White.copy(alpha = .7f))) {
            Box(contentAlignment = Alignment.Center) { Icon(Icons.Rounded.PlayArrow, "播放视频", Modifier.size(34.dp), tint = Color.White) }
        }
        Row(Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = .87f)))).padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (count > 0) Text(if (count > 10000) String.format(java.util.Locale.ROOT, "%.1f万次播放", count / 10000.0) else "${count}次播放", color = Color.White, fontSize = 11.5.sp, fontWeight = reviewWeight(FontWeight.Medium))
            Spacer(Modifier.weight(1f))
            if (media.duration.isNotBlank()) Text(media.duration, Modifier.background(Color.Black.copy(alpha = .54f), RoundedCornerShape(4.dp)).padding(horizontal = 6.dp, vertical = 2.dp), color = Color.White, fontSize = 11.sp, fontWeight = reviewWeight(FontWeight.Bold))
        }
    }
}
