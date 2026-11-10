package com.review.compose

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray

class ReviewRoute(val key: Long, val name: String, post: Post? = null) {
    var post by mutableStateOf(post)
    var profile by mutableStateOf<User?>(null)
    var profilePreview: User? = null
    var initialComment: Comment? = null
    var topic by mutableStateOf<org.json.JSONObject?>(null)
    var contact by mutableStateOf<Contact?>(null)
    var group by mutableStateOf<org.json.JSONObject?>(null)
    var media by mutableStateOf<Media?>(null)
    var backProgress by mutableStateOf<Float?>(null)
}

class ReviewModel(application: Application) : AndroidViewModel(application) {
    private val prefs = application.getSharedPreferences("preferences", 0)
    private val session = SessionStore(application)
    private val accountCommitLock = Mutex()
    private val webRecoveryLock = Mutex()
    val nativeAuth = com.review.weiboauth.WeiboAuthManager(application)
    val repository = Repository(nativeAuth)
    private var cookie = ""
    private var epoch = 0
    private var feedJob: Job? = null
    private var detailJob: Job? = null
    private var searchJob: Job? = null
    private var accountJob: Job? = null
    private var commentJob: Job? = null
    private var actionJob: Job? = null
    private var feedCursor = "0"
    private var feedPage = 1
    private var feedGeneration = 0
    private var feedRetryRefresh = true
    val feedRefreshing: Boolean get() = feedLoading && feedRetryRefresh
    private var searchPage = 1
    private var searchGeneration = 0
    private var commentCursor = "0"
    var ready by mutableStateOf(false); private set
    var demo by mutableStateOf(false); private set
    var uid by mutableStateOf(""); private set
    var tab by mutableStateOf(0)
    var feedTopRequest by mutableStateOf(0); private set
    var feedToggleRequest by mutableStateOf(0); private set
    var feedSaveTopRequest by mutableStateOf(0); private set
    var trendsTopRequest by mutableStateOf(0); private set
    var trendsRefreshRequest by mutableStateOf(0); private set
    private var lastTabTap = 0L
    private var lastTappedTab = -1
    private var tabTapJob: Job? = null
    private var lastFeedTopTap: Long? = null
    fun tapFeedTop() {
        val now = android.os.SystemClock.uptimeMillis()
        if (lastFeedTopTap?.let { now - it < 300 } == true) {
            lastFeedTopTap = null; feedSaveTopRequest++; refreshFeed()
        } else { lastFeedTopTap = now; feedTopRequest++ }
    }
    fun tapTab(index: Int) {
        if (index !in 0..2) return
        if (tab != index) {
            tabTapJob?.cancel(); tabTapJob = null; lastTappedTab = -1
            tab = index
            return
        }
        if (index == 2) return
        val now = android.os.SystemClock.uptimeMillis()
        tabTapJob?.cancel()
        if (lastTappedTab == index && now - lastTabTap < 300) {
            lastTappedTab = -1; tabTapJob = null
            if (index == 0) { feedTopRequest++; refreshFeed() }
            else { trendsTopRequest++; trendsRefreshRequest++ }
        } else {
            lastTabTap = now; lastTappedTab = index
            tabTapJob = viewModelScope.launch {
                kotlinx.coroutines.delay(300)
                if (tab == index) { if (index == 0) feedToggleRequest++ else trendsTopRequest++ }
                lastTappedTab = -1; tabTapJob = null
            }
        }
    }
    var screen by mutableStateOf("root"); private set
    private var routeKey = 0L
    val routeStack = mutableStateListOf(ReviewRoute(routeKey, "root"))
    var theme by mutableStateOf(prefs.getInt("theme", 0)); private set
    var dynamicColor by mutableStateOf(prefs.getBoolean("dynamic", false)); private set
    var textScale by mutableStateOf(prefs.getFloat("textScale", 1f)); private set
    var feed by mutableStateOf<List<Post>>(emptyList()); private set
    var feedLoading by mutableStateOf(false); private set
    var feedError by mutableStateOf<String?>(null); private set
    var feedMore by mutableStateOf(false); private set
    var query by mutableStateOf("")
    var searchResults by mutableStateOf<List<Post>>(emptyList()); private set
    var searchLoading by mutableStateOf(false); private set
    var searchError by mutableStateOf<String?>(null); private set
    var searchMore by mutableStateOf(false); private set
    var submittedQuery by mutableStateOf(""); private set
    var selected by mutableStateOf<Post?>(null); private set
    var detailLoading by mutableStateOf(false); private set
    var detailError by mutableStateOf<String?>(null); private set
    var comments by mutableStateOf<List<Comment>>(emptyList()); private set
    var commentsLoading by mutableStateOf(false); private set
    var commentsError by mutableStateOf<String?>(null); private set
    var commentsMore by mutableStateOf(false); private set
    var accountLoading by mutableStateOf(false); private set
    var accountError by mutableStateOf<String?>(null); private set
    var bookmarks by mutableStateOf<List<Post>>(emptyList()); private set
    var history by mutableStateOf<List<Post>>(emptyList()); private set
    var blocked by mutableStateOf<Set<String>>(emptySet()); private set
    var actionPost by mutableStateOf<Post?>(null)
    internal val postObservers = mutableSetOf<(String, Post?) -> Unit>()
    var revisionPost by mutableStateOf<Post?>(null)
    var articleSource: Post? = null
    var profileUser by mutableStateOf<User?>(null)
    var mediaAuthor: String = ""
    var actionBusy by mutableStateOf(false); private set
    var actionError by mutableStateOf<String?>(null); private set
    private var noticeText by mutableStateOf<String?>(null)
    var noticeRevision by mutableStateOf(0); private set
    var notice: String?
        get() = noticeText
        set(value) { noticeText = value; noticeRevision++ }
    var draft by mutableStateOf(""); private set
    private val scopeKey get() = if (demo) "preview" else uid
    val sessionCookie get() = cookie
    var groups by mutableStateOf<List<FeedGroup>>(emptyList()); private set
    var group by mutableStateOf(FeedGroup("friends", "最新微博")); private set
    var groupsError by mutableStateOf<String?>(null); private set
    var smsChallenge by mutableStateOf(""); private set
    var smsPhone by mutableStateOf(""); private set
    var smsArea by mutableStateOf(""); private set
    var smsAvailableAt by mutableStateOf(0L); private set
    var optionsVersion by mutableStateOf(0); private set
    fun bool(key: String, default: Boolean = false): Boolean { optionsVersion; return prefs.getBoolean(key, default) }
    fun number(key: String, default: Float): Float { optionsVersion; return prefs.getFloat(key, default) }
    fun option(key: String, default: String = ""): String { optionsVersion; return prefs.getString(key, default).orEmpty() }
    fun setOption(key: String, value: Any) {
        prefs.edit().apply { when (value) { is Boolean -> putBoolean(key, value); is Float -> putFloat(key, value); is String -> putString(key, value) } }.apply()
        optionsVersion++
    }
    var me by mutableStateOf<User?>(null); private set

    init {
        viewModelScope.launch {
            try { restoreAccount() }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { accountError = "保存的会话无法读取，请重新登录" }
            configureWebSession(prefs.getBoolean("mobileOnly", false))
            demo = BuildConfig.DEBUG && prefs.getBoolean("demo", false)
            if (demo) feed = PreviewContent.posts
            loadLocal()
            ready = true
            scheduleNotifications(application)
            viewModelScope.launch { try { maintainImageCache(application, number("cacheLimit", 200f).toInt()) } catch (e: CancellationException) { throw e } catch (_: Exception) { } }
            if (!demo && uid.isNotEmpty()) {
                val owner = uid
                if (cookie.isBlank()) messagePoll { recoverCurrentWebSession() }
                if (uid == owner && !demo) { refreshFeed(); loadGroups(); loadMe() }
            }
        }
    }
    private fun loadLocal() {
        bookmarks = runCatching {
            JSONArray(prefs.getString("saved-$scopeKey", "[]")).objects().map(Post::restore)
        }.getOrDefault(emptyList())
        draft = prefs.getString("draft-$scopeKey", "").orEmpty()
        history = runCatching { JSONArray(prefs.getString("history-$scopeKey", "[]")).objects().map(Post::restore) }.getOrDefault(emptyList())
        blocked = prefs.getStringSet("blocked-$scopeKey", emptySet()).orEmpty().toSet()
    }
    fun updateTheme(value: Int) { theme = value; prefs.edit().putInt("theme", value).apply() }
    fun setDynamic(value: Boolean) { dynamicColor = value; prefs.edit().putBoolean("dynamic", value).apply() }
    fun updateTextScale(value: Float) { textScale = value.coerceIn(.8f, 1.5f); prefs.edit().putFloat("textScale", textScale).apply() }
    private suspend fun restoreAccount() {
        val storedUid = prefs.getString("uid", "").orEmpty()
        val (storedCookie, loggedIn) = withContext(Dispatchers.IO) {
            val webCookie = session.load()
            webCookie to (webCookie.isNotBlank() || nativeAuth.hasNativeSessionFor(storedUid))
        }
        cookie = storedCookie
        uid = if (loggedIn) storedUid else ""
    }
    suspend fun reloadPreferences(reloadAccount: Boolean = true) {
        if (reloadAccount) restoreAccount()
        theme = prefs.getInt("theme", 0); dynamicColor = prefs.getBoolean("dynamic", false); textScale = prefs.getFloat("textScale", 1f).coerceIn(.8f, 1.5f)
        configureWebSession(prefs.getBoolean("mobileOnly", false))
        optionsVersion++
        if (reloadAccount) changeMode(false) else loadLocal()
    }
    private fun configureWebSession(mobileOnly: Boolean) {
        repository.mobileOnly = mobileOnly
        repository.api.configureSession(cookie, mobileOnly)
    }
    fun saveDraft(value: String) { draft = value; prefs.edit().putString("draft-$scopeKey", value).apply() }
    fun openRepostDraft(post: Post) {
        saveDraft("//@${post.author}: ${post.text}")
        navigate("draft")
    }
    fun bookmark(post: Post) {
        bookmarks = if (bookmarks.any { it.id == post.id }) bookmarks.filterNot { it.id == post.id }
            else (listOf(post) + bookmarks).take(200)
        prefs.edit().putString("saved-$scopeKey", JSONArray(bookmarks.map(Post::snapshot)).toString()).apply()
    }
    fun changeMode(preview: Boolean) {
        epoch++
        actionPost = null; actionBusy = false; actionError = null
        feedGeneration++
        actionJob?.cancel()
        feedJob?.cancel(); detailJob?.cancel(); searchJob?.cancel(); commentJob?.cancel()
        feedLoading = false; detailLoading = false; searchLoading = false; commentsLoading = false
        demo = preview && BuildConfig.DEBUG; prefs.edit().putBoolean("demo", demo).apply()
        feed = if (demo) PreviewContent.posts else emptyList()
        selected = null; revisionPost = null; searchResults = emptyList(); submittedQuery = ""; query = ""; comments = emptyList()
        feedError = null; searchError = null; feedMore = false
        groups = emptyList(); group = FeedGroup("friends", "最新微博"); groupsError = null
        loadLocal(); resetNavigation()
        scheduleNotifications(getApplication())
        me = null
        if (!preview && uid.isNotEmpty()) { refreshFeed(); loadGroups(); loadMe() }
    }
    private fun loadMe() {
        val generation = epoch
        viewModelScope.launch {
            try { val user = repository.profile(cookie, uid); if (generation == epoch) me = user }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { }
        }
    }
    private suspend fun commitAccount(newCookie: String, newUid: String, mobile: Boolean, acceptNative: Boolean,
        expectedCookie: String? = null): Boolean = accountCommitLock.withLock { withContext(NonCancellable + Dispatchers.IO) {
        val oldCookie = session.load()
        val oldUid = prefs.getString("uid", "").orEmpty()
        if (expectedCookie != null && (oldUid != newUid || oldCookie != expectedCookie)) return@withContext false
        val oldMobile = prefs.getBoolean("mobileOnly", false)
        val oldNative = nativeAuth.exportBackupSession(oldUid)
        try {
            if (acceptNative) check(nativeAuth.acceptPendingSession()) { "加密会话保存失败" }
            else if (newUid.isEmpty() || newUid != oldUid) nativeAuth.logout()
            if (newCookie.isBlank()) session.clear() else session.save(newCookie)
            check(prefs.edit().putString("uid", newUid).putBoolean("mobileOnly", mobile).commit()) { "会话保存失败" }
        } catch (failure: Exception) {
            try {
                nativeAuth.restoreBackupSession(oldNative, oldUid)
                if (oldCookie.isBlank()) session.clear() else session.save(oldCookie)
                check(prefs.edit().putString("uid", oldUid).putBoolean("mobileOnly", oldMobile).commit())
            } catch (rollback: Exception) { failure.addSuppressed(rollback) }
            throw failure
        }
        true
    } }
    fun login(value: String) {
        if (accountLoading || !ready) return
        accountLoading = true; accountError = null
        accountJob = viewModelScope.launch {
            try {
                val expectedUid = uid.takeIf { it.isNotEmpty() && cookie.isBlank() }
                val verified = repository.importWebSession(value, expectedUid)
                commitAccount(verified.cookie, verified.uid, verified.mobileOnly, false)
                cookie = verified.cookie; uid = verified.uid
                configureWebSession(verified.mobileOnly)
                changeMode(false)
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { accountError = e.message ?: "登录失败，请重试" }
            finally { accountLoading = false }
        }
    }
    fun logout() {
        if (accountLoading) return
        accountLoading = true
        accountJob = viewModelScope.launch {
            try {
                commitAccount("", "", false, false)
                cookie = ""; uid = ""; configureWebSession(false)
                changeMode(false)
                runCatching {
                    android.webkit.CookieManager.getInstance().removeAllCookies { android.webkit.CookieManager.getInstance().flush() }
                    android.webkit.WebStorage.getInstance().deleteAllData()
                }.onFailure { accountError = "账号已退出，网页缓存未能清理，请重启应用后重试" }
            } catch (_: Exception) { accountError = "未能移除会话，请重试" }
            finally { accountLoading = false }
        }
    }
    fun refreshFeed() = loadFeed(true)
    fun retryFeed() = loadFeed(feedRetryRefresh)
    fun loadFeed(refresh: Boolean = false) {
        if (demo) { feed = PreviewContent.posts; return }
        if (uid.isEmpty()) return
        if (feedLoading || (!refresh && !feedMore)) return
        feedRetryRefresh = refresh
        feedLoading = true; feedError = null
        val generation = epoch
        val feedRequest = feedGeneration
        feedJob = viewModelScope.launch {
            try {
                val result = repository.feed(cookie, if (refresh) "0" else feedCursor, if (refresh) 1 else feedPage, group.id, ownerUid = uid)
                if (epoch != generation || feedRequest != feedGeneration) return@launch
                if (refresh && result.items.isEmpty() && feed.isNotEmpty()) {
                    feedError = "暂未返回新内容，已保留当前列表"; return@launch
                }
                val merged = if (refresh) result.items.distinctBy { it.id } else mergePosts(feed, result.items)
                feedMore = canContinuePage(if (refresh) "0" else feedCursor, result.next,
                    result.items.isNotEmpty() && (refresh || merged.size > feed.size))
                feed = merged; feedCursor = result.next; feedPage = if (refresh) 2 else feedPage + 1
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { if (epoch == generation && feedRequest == feedGeneration) feedError = e.message ?: "内容加载失败" }
            finally { if (epoch == generation && feedRequest == feedGeneration) feedLoading = false }
        }
    }
    fun selectGroup(value: FeedGroup) {
        if (group == value) return
        feedJob?.cancel(); feedGeneration++; feedLoading = false; feedError = null; feed = emptyList(); feedCursor = "0"; feedPage = 1
        group = value
        while (routeStack.size > 1) routeStack.removeAt(routeStack.lastIndex)
        screen = "root"; tab = 0; feedTopRequest++; refreshFeed()
    }
    fun loadGroups() {
        if (uid.isEmpty()) return
        val generation = epoch
        viewModelScope.launch {
            groupsError = null
            try { val result = repository.groups(cookie); if (generation == epoch) { groups = result; setOption("groupsOwner", uid); setOption("saved_personal_groups_json", encodeGroups(result.filter { it.section == "我的分组" && it.title != "特别关注" })) } }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (e: Exception) { if (generation == epoch) groupsError = e.message ?: "分组加载失败" }
        }
    }
    fun requestSms(phone: String, area: String) {
        if (accountLoading || System.currentTimeMillis() < smsAvailableAt) return
        if (!phone.matches(Regex("[0-9]{5,20}")) || !area.matches(Regex("[0-9]{1,6}"))) { accountError = "请输入正确的区号和手机号"; return }
        accountLoading = true; accountError = null
        accountJob = viewModelScope.launch {
            try {
                val response = withContext(Dispatchers.IO) { nativeAuth.requestSmsCode(phone, area) }
                val number = response["number"]?.toString().orEmpty()
                check(response["sent"] == true && number.isNotBlank()) { "验证码未发送成功" }
                smsPhone = phone; smsArea = area; smsChallenge = number; smsAvailableAt = System.currentTimeMillis() + 60000
                notice = "验证码已发送"
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (e: Exception) { accountError = if (e is com.review.weiboauth.WeiboApi.ApiFailure) e.serverMsg.ifBlank { "验证码发送失败" } else "验证码发送失败，请检查网络后重试" }
            finally { accountLoading = false }
        }
    }
    fun loginNative(account: String, password: String, phone: String, area: String, code: String, sms: Boolean) {
        if (accountLoading) return
        if (sms && (smsChallenge.isBlank() || phone != smsPhone || area != smsArea || !code.matches(Regex("[0-9]{4,12}")))) { accountError = "请先获取当前手机号的验证码并填写"; return }
        if (!sms && (account.isBlank() || account.length > 128 || password.isEmpty() || password.length > 256)) { accountError = "请输入有效的账号和密码"; return }
        accountLoading = true; accountError = null
        accountJob = viewModelScope.launch {
            var failureMessage = "登录请求未完成，请检查网络后重试"
            var receivedLogin = false
            var recoverUid: String? = null
            val recoveringNotice = "登录成功，正在同步阅读会话"
            try {
                val result = withContext(Dispatchers.IO) {
                    if (sms) nativeAuth.loginWithSms(phone, area, smsChallenge, code) else nativeAuth.loginWithPassword(account.trim(), password)
                }
                receivedLogin = true
                failureMessage = "登录响应缺少可用会话，请稍后重试"
                val newUid = result["uid"]?.toString().orEmpty()
                val nativeVerified = result["nativeVerified"] == true
                val probeWeb: suspend () -> VerifiedWebSession? = {
                    repository.verifyWebSession(newUid, result["cookie"]?.toString().orEmpty(),
                        result["desktopCookie"]?.toString().orEmpty(), result["mobileCookie"]?.toString().orEmpty())
                }
                val web = if (nativeVerified) withTimeoutOrNull(8000) { probeWeb() } else probeWeb()
                if (web == null && !nativeVerified) {
                    failureMessage = "原生会话校验失败，请稍后重试"
                    check(withContext(Dispatchers.IO) { nativeAuth.verifyPendingNativeSession(newUid) })
                }
                val newCookie = web?.cookie.orEmpty()
                failureMessage = "会话校验已通过，但加密保存失败，请重试"
                val mobileOnly = web?.mobileOnly == true
                commitAccount(newCookie, newUid, mobileOnly, true)
                cookie = newCookie; uid = newUid
                configureWebSession(mobileOnly)
                failureMessage = "已保存登录会话，打开关注流失败，请重新打开应用"
                changeMode(false)
                if (newCookie.isBlank() && listOf("cookie", "desktopCookie", "mobileCookie").any { !result[it]?.toString().isNullOrBlank() }) recoverUid = newUid
                notice = if (recoverUid != null) recoveringNotice else if (newCookie.isBlank()) "登录成功，部分操作仍需网页会话" else "登录成功"
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (e: Exception) {
                accountError = if (!receivedLogin && e is com.review.weiboauth.WeiboApi.ApiFailure) {
                    val message = e.serverMsg.orEmpty().ifBlank { "登录被拒绝" }
                    val responseCode = e.responseCode.orEmpty()
                    if (sms && responseCode.matches(Regex("-?[0-9]{1,12}"))) "$message（错误码 $responseCode）" else message
                } else failureMessage
            }
            finally { withContext(NonCancellable + Dispatchers.IO) { nativeAuth.discardPendingSession() }; repository.mobileOnly = prefs.getBoolean("mobileOnly", false); accountLoading = false }
            val owner = recoverUid
            if (owner != null && uid == owner && cookie.isBlank() && messagePoll { recoverCurrentWebSession(48_000) } == true && uid == owner) {
                feedJob?.cancel(); feedGeneration++; feedLoading = false
                refreshFeed(); loadGroups(); loadMe()
            }
            if (owner != null && uid == owner && notice == recoveringNotice) notice = if (cookie.isBlank()) "登录已完成，阅读会话暂未同步成功" else "登录成功"
        }
    }
    private suspend fun recoverCurrentWebSession(timeoutMillis: Long = 12_000): Boolean = webRecoveryLock.withLock {
        val owner = uid
        val saved = cookie
        val wasMobile = repository.mobileOnly
        if (owner.isBlank() || demo || accountLoading) return@withLock false
        val browserCookies = runCatching {
            val manager = android.webkit.CookieManager.getInstance()
            manager.getCookie(ApiClient.DESKTOP + "/").orEmpty() to manager.getCookie(ApiClient.MOBILE + "/").orEmpty()
        }.getOrDefault("" to "")
        val nativeCookies = withContext(Dispatchers.IO) { nativeAuth.restoreSession() }
        val verified = withTimeoutOrNull(timeoutMillis) {
            repository.recoverWebSession(owner, saved, wasMobile, nativeCookies, browserCookies.first, browserCookies.second)
        }
            ?: return@withLock false
        if (owner != uid || saved != cookie || accountLoading) return@withLock false
        if (verified.cookie == saved && verified.mobileOnly == wasMobile) return@withLock true
        if (!commitAccount(verified.cookie, owner, verified.mobileOnly, false, expectedCookie = saved)) return@withLock false
        if (owner != uid || saved != cookie) return@withLock false
        cookie = verified.cookie
        configureWebSession(verified.mobileOnly)
        true
    }
    suspend fun checkAccount() {
        val owner = uid
        var readCode: String? = null
        val native = try { repository.verifyNativeAccount(owner) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: com.review.weiboauth.WeiboApi.ApiFailure) {
            readCode = failure.responseCode.orEmpty().takeIf { it.matches(Regex("-?[0-9]{1,12}")) }
            false
        } catch (_: Exception) { false }
        val web = !native && recoverCurrentWebSession()
        val oauth = !native && !web && messagePoll {
            withContext(Dispatchers.IO) { nativeAuth.verifyActiveOAuthAccount(owner) }
        } == true
        if (uid != owner) return
        check(native || web || oauth) {
            if (readCode != null) "内容服务拒绝了原生请求（错误码 $readCode），暂未找到可用的网页会话"
            else "暂时无法校验账号会话，请稍后重试"
        }
        notice = if (!native && !web) "已确认登录账号，正在尝试授权关注流" else "账号凭据有效"
        if (feed.isEmpty()) refreshFeed()
        if (groups.isEmpty()) loadGroups()
        if (me == null) loadMe()
    }
    fun search(more: Boolean = false) {
        val term = if (more) submittedQuery else query.trim()
        if (term.isEmpty() || (more && (searchLoading || !searchMore))) return
        searchJob?.cancel()
        val requestGeneration = ++searchGeneration
        if (!more) { submittedQuery = term; searchResults = emptyList(); searchPage = 1; searchMore = false }
        searchError = null
        if (demo) {
            searchResults = PreviewContent.posts.filter { it.text.contains(term, true) || it.author.contains(term, true) }
            searchLoading = false; return
        }
        searchLoading = true
        val generation = epoch
        searchJob = viewModelScope.launch {
            try {
                val result = repository.search(cookie, term, searchPage)
                if (epoch == generation && searchGeneration == requestGeneration) {
                    val merged = mergePosts(searchResults, result.items)
                    searchMore = result.next != "0" && merged.size > searchResults.size
                    searchResults = merged; searchPage++
                }
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { if (epoch == generation && searchGeneration == requestGeneration) searchError = e.message ?: "搜索失败" }
            finally { if (epoch == generation && searchGeneration == requestGeneration) searchLoading = false }
        }
    }
    fun openPost(post: Post) {
        navigate("detail", post)
        detailJob?.cancel(); commentJob?.cancel()
        selected = post; detailError = null
        comments = if (post.demo) PreviewContent.comments else emptyList()
        commentsError = null; commentsLoading = false; commentsMore = false; commentCursor = "0"
        detailLoading = false
        if (post.demo) return
        history = (listOf(post) + history.filterNot { it.id == post.id }).take(300)
        prefs.edit().putString("history-$scopeKey", JSONArray(history.map(Post::snapshot)).toString()).apply()
        reloadDetail()
    }
    fun openComment(post: Post, comment: Comment) {
        openPost(post)
        routeStack.last().initialComment = comment
    }
    fun reloadDetail() {
        val source = selected ?: return
        if (source.demo || detailLoading) return
        detailLoading = true; detailError = null
        val generation = epoch
        detailJob = viewModelScope.launch {
            try { val full = repository.detail(cookie, source); if (epoch == generation && selected?.id == source.id) { selected = full; routeStack.lastOrNull()?.post = full } }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { if (epoch == generation && selected?.id == source.id) detailError = e.message ?: "详情加载失败" }
            finally { if (epoch == generation && selected?.id == source.id) detailLoading = false }
        }
    }
    fun loadComments(first: Boolean = false) {
        val post = selected ?: return
        if (post.demo || commentsLoading || (!first && !commentsMore)) return
        commentsLoading = true; commentsError = null
        val generation = epoch
        commentJob = viewModelScope.launch {
            try {
                val result = repository.comments(cookie, post, if (first) "0" else commentCursor)
                if (epoch != generation || selected?.id != post.id) return@launch
                val merged = ((if (first) emptyList() else comments) + result.items).distinctBy { it.id }
                commentsMore = result.next != "0" && result.next != commentCursor && (first || merged.size > comments.size)
                comments = merged; commentCursor = result.next
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { if (epoch == generation && selected?.id == post.id) commentsError = e.message ?: "评论加载失败" }
            finally { if (epoch == generation && selected?.id == post.id) commentsLoading = false }
        }
    }
    internal fun backFrom(route: ReviewRoute) {
        if (routeStack.lastOrNull() === route) back()
    }
    fun back() {
        detailJob?.cancel(); commentJob?.cancel(); detailLoading = false; commentsLoading = false
        if (routeStack.size > 1) routeStack.removeAt(routeStack.lastIndex)
        val prior = routeStack.last()
        screen = prior.name; selected = prior.post; profileUser = prior.profile
        detailError = null
    }
    fun navigate(target: String, post: Post? = null) {
        routeStack.lastOrNull()?.let { if (it.name == "detail") it.post = selected }
        routeStack.add(ReviewRoute(++routeKey, target, post))
        screen = target
        if (target.startsWith("profile:")) profileUser = null
    }
    fun openProfile(post: Post) {
        if (post.demo || post.uid.isBlank()) return
        val author = post.data.optJSONObject("user")?.let(::parseUser) ?: User(post.uid, post.author, post.avatar)
        openProfile(author.copy(id = post.uid, name = post.author, avatar = post.avatar))
    }
    fun openProfile(user: User) {
        if (user.id.isBlank()) return
        navigate("profile:${user.id}")
        routeStack.last().profilePreview = user
    }
    fun openProfile(comment: Comment) {
        val user = runCatching { org.json.JSONObject(comment.raw).optJSONObject("user")?.let(::parseUser) }.getOrNull()
            ?: User(comment.uid, comment.author, comment.avatar)
        openProfile(user.copy(id = comment.uid, name = comment.author, avatar = comment.avatar))
    }
    private fun resetNavigation() {
        routeStack.clear(); routeStack.add(ReviewRoute(++routeKey, "root")); screen = "root"; profileUser = null
    }
    fun clearHistory() { history = emptyList(); prefs.edit().remove("history-$scopeKey").apply() }
    fun openTopic(item: org.json.JSONObject) {
        val id = topicId(item)
        if (id.isBlank()) { notice = "当前超话暂无可用入口"; return }
        navigate("topic:$id")
        routeStack.last().topic = org.json.JSONObject(item.toString())
    }
    var messagesRevision by mutableStateOf(0); private set
    fun refreshMessages() { messagesRevision++ }
    fun openConversation(contact: Contact) {
        navigate("chat:${contact.id}:${contact.group}")
        routeStack.last().contact = contact
    }
    suspend fun markInteractionRead(kind: String) {
        if (kind !in setOf("mentions", "likes", "comments") || demo || uid.isBlank()) return
        val owner = uid
        val route = routeStack.lastOrNull() ?: return
        val counts = messagePoll { interactionCounts(repository.unreadMessages(cookie, owner)) } ?: return
        if (uid == owner && routeStack.lastOrNull() === route) {
            counts[kind]?.let { setOption("read-interaction:$owner:$kind", it.toFloat()) }
        }
    }
    fun clearUnreadMessages() = mutate {
        val owner = uid
        val contacts = messagePoll { repository.contacts(cookie) }
        val counts = messagePoll { interactionCounts(repository.unreadMessages(cookie, owner)) }.orEmpty()
        if (uid != owner) return@mutate
        if (contacts == null && counts.isEmpty()) throw java.io.IOException("暂时无法读取未读计数，请重试")
        contacts?.forEach { setOption("read:$owner:${it.id}", it.unread.toFloat()) }
        counts.forEach { (kind, count) -> setOption("read-interaction:$owner:$kind", count.toFloat()) }
        var confirmed = false
        val webEndpoints = if (cookie.isBlank()) emptyList()
            else listOf(ApiClient.CHAT + "/webim/2/direct_messages/clear_unread.json", ApiClient.DESKTOP + "/ajax/message/clearUnread")
        for (address in webEndpoints) {
            try {
                val response = repository.api.get(address, cookie, if (address.contains("webim")) mapOf("source" to "209678993") else mapOf("type" to "all"))
                confirmed = confirmed || ApiClient.acceptedMutation(response)
            } catch (e: CancellationException) { throw e } catch (_: Exception) { }
        }
        notice = when {
            confirmed -> "已清除未读消息"
            contacts == null || counts.isEmpty() -> "已清除可读取的本地未读计数"
            else -> "本地未读计数已清零，服务器未确认同步"
        }
        messagesRevision++
    }
    fun block(id: String) { blocked = blocked + id; prefs.edit().putStringSet("blocked-$scopeKey", blocked).apply(); actionPost = null }
    fun unblock(id: String) { blocked = blocked - id; prefs.edit().putStringSet("blocked-$scopeKey", blocked).apply() }
    fun updatePost(post: Post) {
        feed = feed.map { if (it.id == post.id) post else it }; searchResults = searchResults.map { if (it.id == post.id) post else it }
        if (selected?.id == post.id) selected = post
        routeStack.forEach { if (it.post?.id == post.id) it.post = post }
        actionPost = actionPost?.let { if (it.id == post.id) post else it }
        postObservers.toList().forEach { it(post.id, post) }
    }
    fun clearActionError() { actionError = null }
    fun mutate(action: suspend () -> Unit) {
        if (actionBusy) return
        if (uid.isBlank() || demo) { navigate("account"); return }
        val generation = epoch
        actionBusy = true; actionError = null
        actionJob = viewModelScope.launch {
            val priorNotice = notice
            try { action(); if (generation == epoch && notice == priorNotice) notice = "操作已完成" }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { if (generation == epoch) actionError = e.message ?: "操作未完成" }
            finally { if (generation == epoch) actionBusy = false }
        }
    }
    fun postAction(post: Post, kind: String) = mutate {
        val enabled = if (kind == "like") !post.liked else !post.favorited
        repository.interact(cookie, kind, post.id, enabled)
        if (kind == "delete") {
            feed = feed.filterNot { it.id == post.id }; searchResults = searchResults.filterNot { it.id == post.id }; actionPost = null
            postObservers.toList().forEach { it(post.id, null) }
            if (screen == "detail") back()
        } else {
            updatePost(post.withInteraction(kind, enabled))
            try { updatePost(repository.detail(cookie, post)) }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { }
        }
    }
}
