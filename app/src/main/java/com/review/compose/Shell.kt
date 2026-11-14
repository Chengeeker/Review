@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import androidx.activity.compose.BackHandler
import androidx.activity.compose.PredictiveBackHandler
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateIntAsState
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.DynamicFeed
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material.icons.rounded.Search
import androidx.compose.ui.draw.rotate
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch

private class GalleryRequest(val media: List<Media>, val index: Int, val sources: Map<Int, GalleryOrigin> = emptyMap())

@Composable
fun ReviewApp(model: ReviewModel = viewModel()) {
    val dark = when (model.theme) { 1 -> false; 2 -> true; else -> isSystemInDarkTheme() }
    val activity = androidx.activity.compose.LocalActivity.current
    var openGallery by remember { mutableStateOf<GalleryRequest?>(null) }
    LaunchedEffect(model.linkedCommentPhoto) {
        model.linkedCommentPhoto?.let { url ->
            openGallery = GalleryRequest(listOf(Media(url)), 0)
            model.linkedCommentPhoto = null
        }
    }
    val darkBars = dark || model.screen.startsWith("video:") || openGallery?.sources?.isNotEmpty() == true
    val hapticsEnabled = remember(model) { { model.bool("haptics", true) } }
    LaunchedEffect(activity, darkBars) {
        activity?.window?.let { window ->
            androidx.core.view.WindowCompat.getInsetsController(window, window.decorView).apply {
                isAppearanceLightStatusBars = !darkBars
                isAppearanceLightNavigationBars = !darkBars
            }
        }
    }
    CompositionLocalProvider(LocalReview provides model, LocalRippleConfiguration provides null,
        LocalReviewHapticsEnabled provides hapticsEnabled,
        androidx.compose.ui.platform.LocalHapticFeedback provides SilentComposeHaptics) {
        ReviewFontWeight {
        ReviewTheme(dark, model.dynamicColor, model.textScale, model.number("palette", 0f).toInt(), model.bool("pureBlack")) {
            val windowColor = MaterialTheme.colorScheme.background
            LaunchedEffect(activity, windowColor) {
                activity?.window?.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(windowColor.toArgb()))
            }
            BoxWithConstraints(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            val drawerWidth = minOf(maxWidth * .62f, 280.dp)
            val drawer = rememberDrawerState(DrawerValue.Closed)
            val scope = rememberCoroutineScope()



            var groupsOpen by remember { mutableStateOf(false) }
            LaunchedEffect(model.screen, model.tab) { groupsOpen = false }
            val gallery: (List<Media>, Int) -> Unit = { media, index ->
                if (media.isNotEmpty()) openGallery = GalleryRequest(media, index)
            }
            val canReturn = model.screen != "root" && openGallery == null && !drawer.isOpen && !groupsOpen
            val predictive = android.os.Build.VERSION.SDK_INT >= 34 && model.bool("predictiveBack") && android.animation.ValueAnimator.areAnimatorsEnabled()
            val previewEnabled by rememberUpdatedState(canReturn && predictive)
            BackHandler(canReturn && !predictive) { model.back() }
            PredictiveBackHandler(canReturn && predictive) { progress ->
                val route = model.routeStack.last()
                try {
                    progress.collect { event ->
                        if (previewEnabled && model.routeStack.lastOrNull() === route) route.backProgress = event.progress
                    }
                    if (previewEnabled && model.routeStack.lastOrNull() === route) model.backFrom(route)
                } finally { route.backProgress = null }
            }
            BackHandler(drawer.isOpen) { scope.launch { drawer.close() } }
            BackHandler(groupsOpen) { groupsOpen = false }
            ModalNavigationDrawer(drawerState = drawer, gesturesEnabled = model.screen == "root", drawerContent = {
                ModalDrawerSheet(Modifier.width(drawerWidth).testTag("review-drawer"), drawerContainerColor = if (dark) Color(0xFF1B1B1E) else MaterialTheme.colorScheme.background) {
                    ReviewDrawerContent(drawer.isOpen) { target -> scope.launch { drawer.close() }; model.navigate(target) }
                }
            }) {
                PageStack(model.routeStack.toList()) { route ->
                    val kind = route.name.substringBefore(':')
                    val root = kind == "root"
                    val hasTabsBelow = kind in setOf("favorites", "relations", "topic") || route.name == "notificationsList:mentions"
                    val ownsTopBar = kind in setOf("account", "webLogin", "draft", "edit", "groups", "search", "searchResults",
                        "trends", "topics", "video", "browser", "profileSearch", "topicSearch")
                    val behindShellBar = kind in setOf("detail", "article", "profile", "history", "messages", "groupPosts", "groupInfo",
                        "theme", "storage", "refreshRate", "icons", "notifications", "backup")
                    // The platform WebView draws its own RenderNodes. Do not replay them as a Compose backdrop.
                    val backdrop = if (kind == "browser" || kind == "webLogin") null else {
                        val backgroundLayer = rememberGraphicsLayer()
                        remember(backgroundLayer) { ReviewBackdrop(backgroundLayer) }
                    }
                CompositionLocalProvider(LocalBackdrop provides backdrop, LocalGalleryOpenFrom provides { media, index, sources ->
                    openGallery = GalleryRequest(media, index, sources)
                }) {
                Scaffold(containerColor = MaterialTheme.colorScheme.background, topBar = {
                    if (!root || model.tab == 0) Box(Modifier.frostedBackdrop(MaterialTheme.colorScheme.background, showBorder = !hasTabsBelow)) {
                    if (root) {
                        if (model.tab == 0) FeedTopBar({ groupsOpen = false; scope.launch { drawer.open() } }, groupsOpen, { groupsOpen = !groupsOpen; if (model.groups.isEmpty()) model.loadGroups() })
                    } else if (!ownsTopBar) TopAppBar(title = { if (route.name.startsWith("chat:")) ConversationTitle(route) else if (route.name.startsWith("groupMembers:")) GroupMembersTitle(route) else Text(if (route.name.startsWith("profile:")) route.profile?.name ?: "微博用户" else if (route.name.startsWith("topic:")) route.topic?.optString("title")?.ifBlank { route.topic?.optString("nick").orEmpty() }.orEmpty().ifBlank { "超话" } else routeTitle(route.name), Modifier.padding(start = 16.dp), fontSize = if (route.name.startsWith("topic:")) 17.sp else 18.sp, fontWeight = reviewWeight(androidx.compose.ui.text.font.FontWeight.Bold)) },
                        navigationIcon = { IconButton(onClick = hapticClick(model::back)) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回") } }, expandedHeight = 56.dp,
                        actions = { if (route.name == "style") TextButton(onClick = hapticClick(model::back)) { Text("确定") }
                            if (route.name == "detail") { IconButton(onClick = hapticClick { model.actionPost = route.post }) { Icon(Icons.Rounded.MoreHoriz, "更多操作") }; Spacer(Modifier.width(4.dp)) }
                            if (route.name.startsWith("article:")) IconButton(onClick = hapticClick { model.navigate("browser:${android.net.Uri.encode("https://weibo.com/ttarticle/p/show?id=${route.name.substringAfter(':')}")}") }) { Icon(Icons.Rounded.Language, "在应用内浏览器打开") }
                            if (route.name == "messages" && (model.uid.isNotBlank() || model.demo)) IconButton(onClick = hapticClick(model::clearUnreadMessages), enabled = !model.actionBusy) { Icon(Icons.Outlined.CleaningServices, "清除未读消息") }
                            if (route.name.startsWith("chat:")) {
                                val parts = route.name.split(':'); val group = parts.getOrNull(2) == "true"
                                IconButton(onClick = hapticClick { if (group) { model.navigate("groupInfo:${parts[1]}"); model.routeStack.last().contact = route.contact; model.routeStack.last().group = route.group } else model.openProfile(User(parts[1], route.contact?.name.orEmpty(), route.contact?.avatar.orEmpty())) }) { Icon(if (group) Icons.Outlined.MoreHoriz else Icons.Outlined.PersonOutline, if (group) "群信息" else "用户主页") }
                            }
                            if (route.name.startsWith("topic:")) {
                                val topicTitle = route.topic?.optString("title")?.ifBlank { route.topic?.optString("nick").orEmpty() }.orEmpty()
                                IconButton(onClick = hapticClick {
                                    val id = route.topic?.let(::topicId)?.takeIf(String::isNotBlank) ?: route.name.substringAfter(':')
                                    if (Regex("100808[0-9a-f]{32}", RegexOption.IGNORE_CASE).matches(id)) model.navigate("topicSearch:$id:${android.net.Uri.encode(topicTitle)}")
                                    else model.notice = "超话信息加载中，请稍后重试"
                                }) { Icon(Icons.Outlined.Search, "搜索本超话") }
                                IconButton(onClick = hapticClick { model.notice = "超话：$topicTitle" }) { Icon(Icons.Outlined.Share, "分享超话") }
                            }
                            if (route.name.startsWith("profile:")) {
                            IconButton(onClick = hapticClick { model.navigate("profileSearch:${route.profile?.id ?: route.name.substringAfter(':')}"); model.routeStack.last().profile = route.profile }) { Icon(Icons.Outlined.Search, "搜索微博") }
                            val context = androidx.compose.ui.platform.LocalContext.current
                            IconButton(onClick = hapticClick {
                                (context.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager).setPrimaryClip(android.content.ClipData.newPlainText("博主主页", "https://weibo.com/u/${route.profile?.id ?: route.name.substringAfter(':')}")); model.notice = "已复制博主主页链接"
                            }) { Icon(Icons.Outlined.Share, "分享主页") }
                        } },
                        colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent))
                    }
                }) { padding ->
                    Box(Modifier.fillMaxSize()) {
                        val pagePadding = PaddingValues(
                            top = if (root || ownsTopBar || behindShellBar) 0.dp else padding.calculateTopPadding(),
                            bottom = if (root || kind == "video") 0.dp else padding.calculateBottomPadding(),
                        )
                        Box(Modifier.fillMaxSize().then(if (backdrop != null) Modifier.recordBackdrop(backdrop) else Modifier)
                            .padding(pagePadding).consumeWindowInsets(pagePadding)) {
                            CompositionLocalProvider(LocalContentTop provides when {
                                root -> TopAppBarDefaults.windowInsets.asPaddingValues().calculateTopPadding() + 56.dp
                                behindShellBar -> padding.calculateTopPadding()
                                else -> 0.dp
                            }) {
                            if (!model.ready) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                            else key(route.key, model.uid, model.demo) {
                                val parts = route.name.split(':')
                                when (parts[0]) {
                                    "root" -> RootPages(model, gallery)
                                    "account" -> AccountScreen(model)
                                    "webLogin" -> WebLoginScreen(model)
                                    "detail" -> DetailScreen(model, gallery, route.post)
                                    "search" -> SearchScreen(model, gallery)
                                    "searchResults" -> SearchResultsScreen(android.net.Uri.decode(parts.drop(1).joinToString(":")), gallery)
                                    "trends" -> TrendsScreen(model)
                                    "advanced" -> AdvancedSearchScreen(gallery)
                                    "draft", "edit" -> PublishScreen(if (parts[0] == "edit") parts[1] else null)
                                    "favorites" -> FavoritesScreen(gallery)
                                    "saved" -> SavedScreen(model, gallery)
                                    "groups" -> GroupsScreen()
                                    "profile" -> ProfileScreen(parts.drop(1).joinToString(":"), gallery)
                                    "profileSearch" -> ProfileSearchScreen(parts[1], gallery)
                                    "relations" -> RelationsScreen(parts.getOrElse(1) { model.uid }, parts.getOrElse(2) { "false" }.toBoolean())
                                    "history" -> HistoryScreen(gallery)
                                    "theme" -> ThemeScreen()
                                    "style" -> StyleScreen()
                                    "storage" -> StorageScreen()
                                    "cache" -> CacheScreen()
                                    "refreshRate" -> RefreshRateScreen()
                                    "icons" -> IconScreen()
                                    "backup" -> BackupScreen()
                                    "article" -> ArticleScreen(parts[1], gallery)
                                    "browser" -> BrowserScreen(android.net.Uri.decode(parts.drop(1).joinToString(":")))
                                    "video" -> VideoLinkScreen(android.net.Uri.decode(parts.drop(1).joinToString(":")))
                                    "notifications" -> NotificationSettingsScreen()
                                    "messages" -> MessagesScreen()
                                    "topics" -> TopicsScreen()
                                    "topic" -> TopicScreen(parts.drop(1).joinToString(":"), gallery, route)
                                    "place" -> PlaceLinkScreen(parts.getOrElse(1) { "" }, android.net.Uri.decode(parts.getOrElse(2) { "" }))
                                    "topicSearch" -> TopicSearchScreen(parts[1], android.net.Uri.decode(parts.drop(2).joinToString(":")), gallery)
                                    "notificationsList" -> NotificationList(parts[1], gallery)
                                    "chat" -> ConversationScreen(parts[1], parts[2].toBoolean(), gallery)
                                    "groupInfo" -> GroupInfoScreen(parts[1])
                                    "groupMembers" -> GroupMembersScreen(parts[1])
                                    "groupPosts" -> PagedContent(route.name, { model.repository.userPosts(model.sessionCookie, parts[1], it.toInt().coerceAtLeast(1)) }, Post::id) { PostRow(it, gallery) }
                                }
                            }
                            }
                        }
                        if (route.name == "root") Box(Modifier.align(Alignment.BottomCenter)) { ReviewBottomBar(model) }
                        if (route.name == "root" && groupsOpen) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .4f)).reviewClickable { groupsOpen = false })
                        AnimatedVisibility(route.name == "root" && groupsOpen, Modifier.padding(top = padding.calculateTopPadding()), enter = expandVertically(expandFrom = Alignment.Top), exit = shrinkVertically(shrinkTowards = Alignment.Top)) { GroupDropdown { groupsOpen = false } }
                    }
                }
                }
                }
            }
            openGallery?.let { request ->
                key(request) { Gallery(request.media, request.index, request.sources) { if (openGallery === request) openGallery = null } }
            }
            PostActions()
            model.revisionPost?.let { post ->
                key(post.id) { EditHistorySheet(post, openGallery == null, gallery) { model.revisionPost = null } }
            }
            ReviewToast(model.notice, model.noticeRevision, dark) { model.notice = null }
            if (model.actionPost == null && model.actionError != null) ReviewAlertDialog(onDismissRequest = { model.clearActionError() }, title = { Text("操作未完成") }, text = { Text(model.actionError.orEmpty()) }, confirmButton = { TextButton(onClick = hapticClick(model::clearActionError)) { Text("知道了") } })
            }
        }
        }
    }
}

fun routeTitle(route: String): String = when (route.substringBefore(':')) {
    "detail", "article" -> "文章详情"; "search" -> "搜索"; "advanced" -> "高级搜索"; "draft" -> "发微博"; "edit" -> "编辑微博"
    "account" -> "账号登录"; "favorites" -> "赞和收藏"; "groups" -> "我的分组"; "relations" -> "关注列表"; "history" -> "浏览记录"
    "messages" -> "我的消息"; "topics" -> "超话中心"; "place" -> "地理位置"; "profile" -> "个人主页"; "theme" -> "个性化"
    "style" -> "微博样式"; "storage" -> "存储设置"; "cache" -> "缓存管理"; "backup" -> "WebDAV 云端备份与恢复"; "notifications" -> "订阅消息提醒"
    "icons" -> "自定义应用图标"; "refreshRate" -> "屏幕帧率设置"
    "groupMembers" -> "群成员"; "groupPosts" -> "群微博"; "groupInfo" -> "群信息"
    "notificationsList" -> when (route.substringAfter(':')) { "mentions" -> "@我的"; "likes" -> "收到的赞"; "sentComments" -> "发出的评论"; else -> "收到的评论" }
    else -> "Review"
}
@Composable
private fun FeedTopBar(openDrawer: () -> Unit, groupsOpen: Boolean, toggleGroups: () -> Unit) {
    val model = LocalReview.current
    val arrow by animateFloatAsState(if (groupsOpen) 180f else 0f, tween(200), label = "group-arrow")
    TopAppBar(title = {
        Row(Modifier.padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(model.group.title, fontSize = 18.sp, fontWeight = reviewWeight(FontWeight.Bold))
            Spacer(Modifier.width(4.dp))
            Box(Modifier.clip(RoundedCornerShape(12.dp)).reviewClickable(onClickLabel = "切换分组", onClick = toggleGroups).padding(4.dp)) { Icon(Icons.Rounded.ArrowDropDown, "切换分组", Modifier.size(24.dp).rotate(arrow)) }
        }
    }, navigationIcon = { Box(Modifier.size(48.dp).padding(start = 12.dp), contentAlignment = Alignment.Center) { Avatar(model.me?.name.orEmpty(), model.me?.avatar.orEmpty(), Modifier.size(34.dp).reviewClickable(onClick = openDrawer).semantics { contentDescription = "打开侧栏" }, shareWithProfile = true) } },
        actions = {
            IconButton(onClick = hapticClick { model.navigate("draft") }) { Icon(Icons.Outlined.Edit, "发微博") }
            IconButton(onClick = hapticClick { model.navigate("advanced") }) { Icon(Icons.Rounded.Search, "高级搜索") }
        }, modifier = Modifier.reviewClickable { model.tapFeedTop() }, expandedHeight = 56.dp, colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent))
}
@Composable
private fun ReviewBottomBar(model: ReviewModel) {
    val select: (Int) -> Unit = model::tapTab
    val icons = listOf(if (model.tab == 0) Icons.Rounded.DynamicFeed else Icons.Outlined.DynamicFeed,
        if (model.tab == 1) Icons.Rounded.LocalFireDepartment else Icons.Outlined.LocalFireDepartment,
        if (model.tab == 2) Icons.Rounded.Settings else Icons.Outlined.Settings)
    val names = listOf("时间线", "热搜", "设置")
    if (!model.bool("floating", true)) {
        NavigationBar(Modifier.height(68.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()), windowInsets = WindowInsets.navigationBars) { names.forEachIndexed { i, name -> NavigationBarItem(model.tab == i, hapticClick { select(i) }, icon = { Icon(icons[i], null) }, label = { Text(name) }) } }
    } else BoxWithConstraints(Modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = if (WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() > 0.dp) 6.dp else 14.dp), contentAlignment = Alignment.Center) {
        val width = minOf(440.dp, maxWidth - 40.dp) * (2f / 3f)
        if (model.bool("liquidGlass")) {
            GlassNavigation(model, width,
                listOf(Icons.Outlined.DynamicFeed, Icons.Outlined.LocalFireDepartment, Icons.Outlined.Settings),
                listOf(Icons.Rounded.DynamicFeed, Icons.Rounded.LocalFireDepartment, Icons.Rounded.Settings), names, select)
            return@BoxWithConstraints
        }
        Surface(Modifier.width(width).height(56.dp).dropShadow(RoundedCornerShape(32.dp), Shadow(radius = 16.dp, color = Color.Black.copy(alpha = if (MaterialTheme.colorScheme.background.luminance() < .5f) .35f else .12f), offset = androidx.compose.ui.unit.DpOffset(0.dp, 4.dp))), color = MaterialTheme.colorScheme.surfaceContainerHigh, shape = RoundedCornerShape(32.dp)) {
            Box(Modifier.padding(4.dp)) {
                val cell = (width - 8.dp) / 3
                val x by animateDpAsState(cell * model.tab, tween(240, easing = CubicBezierEasing(.215f, .61f, .355f, 1f)), label = "navigation")
                Box(Modifier.offset(x = x).width(cell).fillMaxHeight().clip(RoundedCornerShape(28.dp)).background(MaterialTheme.colorScheme.secondaryContainer))
                Row(Modifier.fillMaxSize()) { names.forEachIndexed { i, name ->
                    val tint by animateColorAsState(if (model.tab == i) MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurfaceVariant, tween(150), label = "navigation-label")
                    val weight by animateIntAsState(if (model.tab == i) 600 else 400, tween(150), label = "navigation-weight")
                    Column(Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(28.dp)).reviewClickable { select(i) }, Arrangement.Center, Alignment.CenterHorizontally) {
                        AnimatedContent(icons[i], transitionSpec = { fadeIn(tween(150)).togetherWith(fadeOut(tween(150))) }, label = "navigation-icon") { icon -> Icon(icon, null, Modifier.size(22.dp), tint = tint) }
                        Spacer(Modifier.height(2.dp))
                        Text(name, fontSize = 11.5.sp, color = tint, fontWeight = reviewWeight(FontWeight(weight)))
                    }
                } }
            }
        }
    }
}

@Composable
private fun RootPages(model: ReviewModel, gallery: (List<Media>, Int) -> Unit) {
    val selected = model.tab
    val visited = remember { mutableStateListOf(selected) }
    val initialOffsets = remember { mutableMapOf(selected to 0f) }
    var previous by remember { mutableIntStateOf(selected) }
    SideEffect {
        if (selected !in visited) { initialOffsets[selected] = if (selected > previous) 1f else -1f; visited.add(selected) }
        previous = selected
    }
    val direction = if (androidx.compose.ui.platform.LocalLayoutDirection.current == androidx.compose.ui.unit.LayoutDirection.Rtl) -1 else 1
    BoxWithConstraints(Modifier.fillMaxSize().padding(bottom = if (model.bool("floating", true)) 0.dp else 68.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()).clipToBounds()) {
        val width = constraints.maxWidth.toFloat()
        visited.forEach { index -> key(index) {
            val target = when { index == selected -> 0f; index < selected -> -1f; else -> 1f }
            val x = remember { androidx.compose.animation.core.Animatable(initialOffsets[index] ?: 0f) }
            LaunchedEffect(target) { x.animateTo(target, tween(260, easing = CubicBezierEasing(.215f, .61f, .355f, 1f))) }
            Box(Modifier.fillMaxSize().graphicsLayer { translationX = x.value * width * direction }.then(if (index == selected) Modifier else Modifier.clearAndSetSemantics {})) {
                CompositionLocalProvider(LocalPageActive provides (LocalPageActive.current && index == selected)) {
                    when (index) { 0 -> FeedScreen(model, gallery); 1 -> TrendsScreen(model); else -> SettingsScreen(model) }
                }
            }
        } }
    }
}
