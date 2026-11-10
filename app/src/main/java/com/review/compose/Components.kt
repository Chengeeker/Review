package com.review.compose

import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.automirrored.outlined.Reply
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.ChatBubbleOutline
import androidx.compose.material.icons.rounded.ThumbUp
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.em
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.SubcomposeAsyncImage
import coil.compose.SubcomposeAsyncImageContent
import coil.request.ImageRequest

@Composable
fun ReviewTheme(dark: Boolean, dynamic: Boolean = false, scale: Float = 1f, palette: Int = 0, pureBlack: Boolean = false, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val resources = androidx.compose.ui.platform.LocalResources.current
    val scheme = if (dynamic && Build.VERSION.SDK_INT >= 31) {
        remember(context, dark, resources, androidx.compose.ui.platform.LocalConfiguration.current) {
            val platform = if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
            val surface = resources.getColor(if (dark) android.R.color.system_neutral1_900 else android.R.color.system_neutral1_10, context.theme)
            val seed = resources.getColor(if (dark) android.R.color.system_accent1_200 else android.R.color.system_accent1_600, context.theme)
            reviewDynamicSurfaces(platform, dark, seed, surface)
        }
    } else ReviewPalettes[palette.coerceIn(0, 7)].let { if (dark) it.second else it.first }
    val effective = reviewColors(scheme, dark, pureBlack)
    fun TextStyle.relativeHeight(ratio: Float) = copy(lineHeight = ratio.em, lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None))
    val baseText = Typography().let { text -> text.copy(
        displayLarge = text.displayLarge.relativeHeight(1.12f), displayMedium = text.displayMedium.relativeHeight(1.16f), displaySmall = text.displaySmall.relativeHeight(1.22f),
        headlineLarge = text.headlineLarge.relativeHeight(1.25f), headlineMedium = text.headlineMedium.relativeHeight(1.29f), headlineSmall = text.headlineSmall.relativeHeight(1.33f),
        titleLarge = text.titleLarge.relativeHeight(1.27f), titleMedium = text.titleMedium.relativeHeight(1.5f), titleSmall = text.titleSmall.relativeHeight(1.43f),
        bodyLarge = text.bodyLarge.relativeHeight(1.5f), bodyMedium = text.bodyMedium.relativeHeight(1.43f), bodySmall = text.bodySmall.relativeHeight(1.33f),
        labelLarge = text.labelLarge.relativeHeight(1.43f), labelMedium = text.labelMedium.relativeHeight(1.33f), labelSmall = text.labelSmall.relativeHeight(1.45f)) }
    val text = baseText.copy(
        bodyLarge = baseText.bodyLarge.copy(letterSpacing = 0.sp),
        bodyMedium = baseText.bodyMedium.copy(letterSpacing = 0.sp),
        bodySmall = baseText.bodySmall.copy(letterSpacing = 0.sp, color = effective.onSurfaceVariant),
        titleLarge = baseText.titleLarge.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.sp),
        titleMedium = baseText.titleMedium.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp),
        titleSmall = baseText.titleSmall.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp, color = effective.onSurfaceVariant),
        labelLarge = baseText.labelLarge.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp),
        labelMedium = baseText.labelMedium.copy(fontWeight = FontWeight.Medium, letterSpacing = 0.sp),
    ).adjustWeight(LocalWeightAdjustment.current)
    val density = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density, density.fontScale * scale), LocalContentColor provides effective.onSurface) {
        MaterialTheme(colorScheme = effective, typography = text) { ProvideTextStyle(text.bodyMedium, content) }
    }
}

// shortcut: palette helpers are restricted Material internals, revalidate when upgrading Material.
@android.annotation.SuppressLint("RestrictedApi")
internal fun reviewDynamicSurfaces(scheme: ColorScheme, dark: Boolean, seed: Int, surface: Int): ColorScheme {
    val colors = com.google.android.material.color.utilities.MaterialDynamicColors()
    val palette = com.google.android.material.color.utilities.SchemeTonalSpot(com.google.android.material.color.utilities.Hct.fromInt(seed), dark, 0.0)
    return scheme.copy(surface = Color(surface),
        surfaceContainerLowest = Color(colors.surfaceContainerLowest().getArgb(palette)),
        surfaceContainerLow = Color(colors.surfaceContainerLow().getArgb(palette)),
        surfaceContainer = Color(colors.surfaceContainer().getArgb(palette)),
        surfaceContainerHigh = Color(colors.surfaceContainerHigh().getArgb(palette)),
        surfaceContainerHighest = Color(colors.surfaceContainerHighest().getArgb(palette)))
}

fun reviewColors(scheme: ColorScheme, dark: Boolean, pureBlack: Boolean): ColorScheme = when {
    !dark -> scheme.copy(background = scheme.surface)
    pureBlack -> scheme.copy(background = Color.Black, surface = Color.Black,
        surfaceContainerLowest = Color(0xFF121212), surfaceContainer = Color(0xFF121212),
        surfaceContainerHigh = Color(0xFF181818), surfaceContainerHighest = Color(0xFF222222))
    else -> scheme.copy(background = Color(0xFF111215), surfaceContainerLowest = Color(0xFF1B1C20))
}

@Composable
fun ReviewDivider(modifier: Modifier = Modifier, thickness: androidx.compose.ui.unit.Dp = .5.dp, color: Color = Color.Unspecified) {
    val colors = MaterialTheme.colorScheme
    val line = if (color != Color.Unspecified) color else if (colors.background == Color.Black) Color.White.copy(alpha = .1f)
        else colors.outlineVariant.copy(alpha = if (colors.background.luminance() < .5f) .2f else .3f)
    Box(modifier.fillMaxWidth().height(maxOf(1.dp, thickness)), contentAlignment = Alignment.Center) {
        HorizontalDivider(thickness = thickness, color = line)
    }
}

@Composable
fun ReviewListItem(headlineContent: @Composable () -> Unit, modifier: Modifier = Modifier,
    supportingContent: (@Composable () -> Unit)? = null, leadingContent: (@Composable () -> Unit)? = null,
    trailingContent: (@Composable () -> Unit)? = null,
    colors: ListItemColors = ListItemDefaults.colors(containerColor = Color.Transparent)) {
    ListItem(modifier = modifier.padding(vertical = 3.dp), colors = colors,
        headlineContent = { ProvideTextStyle(MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp, lineHeight = 1.35.em, fontWeight = reviewWeight(FontWeight.SemiBold)), headlineContent) },
        supportingContent = supportingContent?.let { content -> { ProvideTextStyle(MaterialTheme.typography.bodyMedium.copy(fontSize = 12.5.sp, lineHeight = 1.4.em, fontWeight = reviewWeight(FontWeight.Normal)), content) } },
        leadingContent = leadingContent, trailingContent = trailingContent)
}

@Composable
fun Avatar(name: String, url: String = "", modifier: Modifier = Modifier, verified: Boolean = false, verifiedType: Int = -1, shareWithProfile: Boolean = false, crossfade: Boolean = true) {
    BoxWithConstraints(modifier.size(42.dp)) {
    val diameter = maxWidth
    @Composable fun Fallback() {
        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
            val first = name.trim().codePoints().findFirst()
            if (first.isPresent) Text(String(Character.toChars(first.asInt)).uppercase(), color = MaterialTheme.colorScheme.onPrimaryContainer, fontSize = (diameter.value * .45f).sp, fontWeight = reviewWeight(FontWeight.Bold))
            else Icon(Icons.Rounded.Person, null, Modifier.size(diameter * .55f), tint = MaterialTheme.colorScheme.onPrimaryContainer)
        }
    }
    Box(Modifier.fillMaxSize().clip(CircleShape), contentAlignment = Alignment.Center) {
        if (url.isBlank()) Fallback()
        else {
            val context = LocalContext.current
            val sharedSize = with(androidx.compose.ui.platform.LocalDensity.current) { 64.dp.roundToPx() }
            val request = remember(context, url, shareWithProfile, sharedSize, crossfade) {
                ImageRequest.Builder(context).data(url).addHeader("Referer", "${ApiClient.DESKTOP}/")
                    .addHeader("User-Agent", ApiClient.USER_AGENT)
                    .apply { if (shareWithProfile) size(sharedSize); if (!crossfade) crossfade(false) }.build()
            }
            SubcomposeAsyncImage(model = request, contentDescription = null, modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop, loading = { Fallback() }, error = { Fallback() })
        }
    }
    if (verified) Box(Modifier.align(Alignment.BottomEnd).size(diameter * .35f).clip(CircleShape).background(if (verifiedType == 0) Color(0xFFFFC107) else Color(0xFF448AFF)).border(1.5.dp, MaterialTheme.colorScheme.surface, CircleShape), contentAlignment = Alignment.Center) {
        Text("v", fontSize = (diameter.value * .22f).sp, lineHeight = (diameter.value * .22f).sp, fontWeight = reviewWeight(FontWeight.Black), color = Color.White)
    }
    }
}

@Composable
fun MediaImage(media: Media, description: String, modifier: Modifier = Modifier, fit: Boolean = false, overlay: Boolean = false,
    onBitmap: ((android.graphics.Bitmap) -> Unit)? = null, backgroundColor: Color? = null) {
    if (media.artwork > 0) LandscapeArt(media.artwork, modifier.semantics { contentDescription = description })
    else {
        var attempt by remember(media.url) { mutableIntStateOf(0) }
        val context = LocalContext.current
        val model = LocalReview.current
        BoxWithConstraints(modifier) {
        val size = previewDecodeSize(media, constraints.maxWidth.takeIf { it < androidx.compose.ui.unit.Constraints.Infinity } ?: 1080,
            constraints.maxHeight.takeIf { it < androidx.compose.ui.unit.Constraints.Infinity } ?: 1080, fit)
        val url = if (media.gif || media.card) media.url else highQualityPreviewUrl(media.url)
        val request = remember(url, size, fit, model.sessionCookie) {
            ImageRequest.Builder(context).data(url).size(size.width, size.height)
                .crossfade(!media.card) // A composite transition source must contain final pixels, not a loading fade.
                .precision(coil.size.Precision.EXACT).scale(if (fit || media.width <= 0 || media.height <= 0) coil.size.Scale.FIT else coil.size.Scale.FILL)
                .allowRgb565(false).diskCacheKey(MediaFiles.cacheKey(url, model.sessionCookie))
                .memoryCacheKey("preview-v2:${size.width}x${size.height}:${MediaFiles.cacheKey(url, model.sessionCookie)}")
                .addHeader("Referer", "${ApiClient.DESKTOP}/").addHeader("User-Agent", ApiClient.USER_AGENT).apply {
                    MediaFiles.privateMediaCookie(url, model.sessionCookie).takeIf(String::isNotBlank)?.let { addHeader("Cookie", it) }
                }.build()
        }
        key(attempt) {
            SubcomposeAsyncImage(
                model = request,
                contentDescription = description, modifier = Modifier.fillMaxSize().background(backgroundColor ?: if (media.card) Color.Transparent else MaterialTheme.colorScheme.surfaceContainer),
                contentScale = if (fit) ContentScale.Fit else ContentScale.Crop,
                filterQuality = androidx.compose.ui.graphics.FilterQuality.High,
                success = { state ->
                    SideEffect { (state.result.drawable as? android.graphics.drawable.BitmapDrawable)?.bitmap?.let { onBitmap?.invoke(it) } }
                    SubcomposeAsyncImageContent()
                },
                loading = { if (!overlay) Box(Modifier.fillMaxSize().background(backgroundColor ?: if (media.card) Color.White else MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = .4f))) },
                error = { Box(Modifier.fillMaxSize().reviewClickable(onClickLabel = "重试图片") { attempt++ }, contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Outlined.BrokenImage, null); Text("点击重试", style = MaterialTheme.typography.labelSmall) }
                } },
            )
        }
        }
    }
}

@Composable
fun LandscapeArt(style: Int, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val w = size.width; val h = size.height
        when (style) {
            4 -> {
                drawRect(Brush.verticalGradient(listOf(Color(0xFFE7BC99), Color(0xFFF3DBBC), Color(0xFF84938B))))
                drawCircle(Color(0xFFFFE8BB), w * .12f, Offset(w * .72f, h * .28f))
                for (i in 0..11) {
                    val bh = h * (.18f + ((i * 7) % 6) * .055f)
                    drawRect(Color(0xFF65766F), Offset(w * i / 11, h * .85f - bh), Size(w / 13, bh))
                    for (j in 0..2) drawRect(Color(0xFFDAC3A1), Offset(w * i / 11 + w * .015f, h * .85f - bh + h * .04f + j * h * .055f), Size(w * .012f, h * .018f))
                }
                drawRect(Color(0xFF3E5751), Offset(0f, h * .85f), Size(w, h * .15f))
            }
            5, 6 -> {
                drawRect(Brush.linearGradient(listOf(Color(0xFFD9C7AB), Color(0xFFAFA48A))))
                drawRect(Color(0xFF556A58), Offset(w * .1f, h * .08f), Size(w * .8f, h * .52f))
                drawRect(Color(0xFFD1D7BA), Offset(w * .12f, h * .1f), Size(w * .37f, h * .48f))
                drawRect(Color(0xFFA3B99C), Offset(w * .51f, h * .1f), Size(w * .37f, h * .48f))
                drawOval(Color(0xFFAE9A7D), Offset(w * .2f, h * .7f), Size(w * .65f, h * .14f))
                drawCircle(Color(0xFFF2EADB), w * .16f, Offset(w * .52f, h * .67f))
                drawCircle(Color(0xFF6F4E38), w * .12f, Offset(w * .52f, h * .67f))
                drawCircle(Color(0xFFB48B60), w * .075f, Offset(w * .51f, h * .67f))
            }
            else -> {
                val palettes = when (style) {
                    2 -> listOf(Color(0xFFDCDCC8), Color(0xFFADBBA4), Color(0xFF7E997F), Color(0xFF46674F))
                    3 -> listOf(Color(0xFFE9D7C0), Color(0xFFC1B89C), Color(0xFF939D7F), Color(0xFF5E765F))
                    else -> listOf(Color(0xFFD6E0D9), Color(0xFFAABFB5), Color(0xFF7E9E90), Color(0xFF466D5C))
                }
                drawRect(Brush.verticalGradient(listOf(palettes[0], Color(0xFFF1EEDB))))
                drawCircle(Color(0xFFF7F0D7), w * .105f, Offset(w * .72f, h * .22f))
                repeat(3) { layer ->
                    val base = h * (.38f + layer * .18f)
                    val path = Path().apply {
                        moveTo(-w * .15f, base + h * .25f)
                        cubicTo(w * .1f, base - h * .38f, w * .28f, base + h * .05f, w * .45f, base)
                        cubicTo(w * .7f, base - h * .4f + layer * h * .05f, w * .8f, base + h * .08f, w * 1.1f, base - h * .1f)
                        lineTo(w, h); lineTo(0f, h); close()
                    }
                    drawPath(path, palettes[layer + 1])
                }
                val stream = Path().apply {
                    moveTo(w * .6f, h * .65f); cubicTo(w * .3f, h * .8f, w * .83f, h * .8f, w * .4f, h)
                    lineTo(w * .65f, h); cubicTo(w * .95f, h * .8f, w * .36f, h * .8f, w * .6f, h * .65f)
                }
                drawPath(stream, Color(0xFFD1DBBE))
            }
        }
    }
}

@Composable
fun PostCard(post: Post, saved: Boolean, onOpen: () -> Unit, onSave: () -> Unit,
             onGallery: (List<Media>, Int) -> Unit, onRepost: (Post) -> Unit, detail: Boolean = false) {
    val model = LocalReview.current
    val colors = MaterialTheme.colorScheme
    val layout = model.option("cardLayout", "card_rounded")
    val rounded = layout in listOf("card_rounded", "floating_rounded")
    val floating = layout.startsWith("floating")
    val margin = if (detail || (!rounded && !floating)) Modifier else Modifier.padding(horizontal = if (floating) 10.dp else 8.dp, vertical = if (floating) 6.dp else 4.dp)
    Surface(color = colors.surfaceContainerLowest, shape = RoundedCornerShape(if (rounded) 22.dp else 0.dp), border = if (layout == "normal" && !detail) BorderStroke(.5.dp, colors.outlineVariant.copy(alpha = .15f)) else null, shadowElevation = if (detail) 0.dp else if (floating) 3.5.dp else if (rounded) 1.dp else 0.dp, modifier = margin.fillMaxWidth()) {
        Column(Modifier.reviewClickable(enabled = !detail, onClick = onOpen).padding(start = 14.dp, end = 14.dp, top = 14.dp, bottom = 10.dp)) {
            val title = post.data.optJSONObject("title")?.optString("text") ?: post.data.optString("title")
            val visibility = postVisibility(post.data)
            val pinned = post.data.optBoolean("isTop") || post.data.optInt("isTop") == 1 || title == "置顶"
            if (pinned || title.contains("热门")) {
                val color = if (pinned) Color(0xFF4CAF50) else Color(0xFFFF5722)
                Row(Modifier.padding(bottom = 6.dp).border(.6.dp, color.copy(alpha = .35f), RoundedCornerShape(16.dp)).background(color.copy(alpha = .12f), RoundedCornerShape(16.dp)).padding(horizontal = 8.dp, vertical = 2.5.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (pinned) Icons.Outlined.PushPin else Icons.Outlined.LocalFireDepartment, null, Modifier.size(12.dp), tint = color)
                    Spacer(Modifier.width(3.dp)); Text(if (pinned) "置顶" else "热门", fontSize = 11.sp, fontWeight = reviewWeight(FontWeight.Bold), color = color)
                }
            } else if (title.isNotBlank() && title != "null" && visibilityLabel(visibility) == null) Row(Modifier.padding(bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (title.contains("赞")) Icons.Outlined.Favorite else Icons.Outlined.Repeat, null, Modifier.size(13.dp), tint = colors.primary.copy(alpha = .8f)); Spacer(Modifier.width(4.dp))
                Text(plainText(title), color = colors.primary.copy(alpha = .8f), fontSize = 11.5.sp, fontWeight = reviewWeight(FontWeight.SemiBold))
            }
            if (detail || (visibility != null && visibility != 0 && visibilityLabel(visibility) != null)) Box(Modifier.height(24.dp)) {
                visibilityLabel(visibility)?.let { label -> Row(Modifier.offset(y = (-4).dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Outlined.Public, null, Modifier.size(16.dp), tint = colors.primary); Spacer(Modifier.width(6.dp)); Text(label, fontSize = 14.sp, color = colors.primary) } }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                val user = post.data.optJSONObject("user")
                val verified = user?.optBoolean("verified") == true
                Avatar(post.author, post.avatar, Modifier.reviewClickable { model.openProfile(post) }, verified, user?.optInt("verified_type", -1) ?: -1, shareWithProfile = true)
                Column(Modifier.weight(1f).padding(start = 10.dp).reviewClickable { model.openProfile(post) }) {
                    val description = user?.optString("description").orEmpty()
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(post.author, Modifier.weight(1f, false), fontSize = 15.sp, fontWeight = reviewWeight(FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (model.bool("remark") && description.isNotBlank()) Text("($description)", Modifier.padding(start = 4.dp).weight(1f, false), fontSize = 12.sp, color = colors.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (model.bool("activityIcon", true) && verified) Icon(Icons.Filled.Verified, null, Modifier.padding(start = 4.dp).size(14.dp), tint = colors.primary)
                    }
                    Spacer(Modifier.height(2.dp))
                    val time = postTime(post.time, model.option("timeMode", "relative") == "relative", model.bool("weekday"), model.bool("year"), model.bool("timezone"), model.bool("seconds"))
                    val region = post.data.optString("region_name")
                    val showRegion = model.bool("region", true) && model.option("ip", "all") != "none" && (detail || model.option("ip", "all") == "all")
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(time, fontSize = 11.5.sp, color = colors.onSurfaceVariant, maxLines = 1)
                        if (model.bool("source", true) && post.source.isNotBlank()) Text(post.source, Modifier.weight(1f, false), fontSize = 11.5.sp, color = colors.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (showRegion && region.isNotBlank()) Text(region, fontSize = 11.5.sp, color = colors.onSurfaceVariant, maxLines = 1)
                        if (post.data.optInt("edit_count") > 0) Text("已编辑", Modifier.clip(RoundedCornerShape(6.dp)).background(colors.secondaryContainer.copy(alpha = .85f)).reviewClickable { model.revisionPost = post }.padding(horizontal = 5.dp, vertical = 1.dp), color = colors.onSecondaryContainer, fontSize = 10.5.sp, fontWeight = reviewWeight(FontWeight.SemiBold), maxLines = 1)
                    }
                }
                if (!model.bool("menuBottom", true)) IconButton(onClick = hapticClick { model.actionPost = post }) { Icon(Icons.Outlined.MoreHoriz, "更多", Modifier.size(20.dp)) }
            }
            Spacer(Modifier.height(10.dp))
            PostBody(post, detail, onGallery)
            Spacer(Modifier.height(12.dp))
            Box(Modifier.height(1.dp), contentAlignment = Alignment.Center) { ReviewDivider() }
            Spacer(Modifier.height(4.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceAround, verticalAlignment = Alignment.CenterVertically) {
                PostAction(Icons.Rounded.Repeat, "转发", post.shares, colors.onSurfaceVariant) { model.saveDraft("//@${post.author}: ${post.text}"); model.navigate("draft") }
                PostAction(Icons.Rounded.ChatBubbleOutline, "评论", post.comments, colors.onSurfaceVariant) { if (!detail) onOpen() }
                PostAction(if (post.liked) Icons.Rounded.ThumbUp else Icons.Outlined.ThumbUp, "点赞", post.likes, if (post.liked) colors.primary else colors.onSurfaceVariant, !model.actionBusy) { model.postAction(post, "like") }
                if (model.bool("menuBottom", true)) PostAction(Icons.Rounded.MoreHoriz, "更多", 0, colors.onSurfaceVariant) { model.actionPost = post }
            }
        }
    }
    if (!detail && layout == "normal_thin_divider") Spacer(Modifier.fillMaxWidth().height(8.dp).background(if (colors.background.luminance() < .5f) Color(0xFF101114) else colors.surfaceContainerHighest.copy(alpha = .35f)))
}

@Composable
private fun PostAction(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, count: Int, color: Color, enabled: Boolean = true, action: () -> Unit) {
    Row(Modifier.reviewClickable(enabled = enabled, onClickLabel = label, onClick = action).padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, label, Modifier.size(18.dp), tint = color)
        if (count > 0) { Spacer(Modifier.width(4.dp)); Text(if (count > 10000) String.format(java.util.Locale.ROOT, "%.1fw", count / 10000f) else "$count", fontSize = 12.sp, fontWeight = reviewWeight(FontWeight.Medium), color = color) }
    }
}

@Composable
fun ErrorNotice(message: String, retry: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.errorContainer, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(start = 16.dp, top = 8.dp, bottom = 8.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(message, Modifier.weight(1f), color = MaterialTheme.colorScheme.onErrorContainer, style = MaterialTheme.typography.bodyMedium)
            TextButton(onClick = hapticClick(retry)) { Text("重试", color = MaterialTheme.colorScheme.onErrorContainer) }
        }
    }
}

@Composable
fun EmptyNotice(title: String, message: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Outlined.AutoStories, null, Modifier.size(42.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.height(16.dp)); Text(title, style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(8.dp)); Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
