import 'package:easy_refresh/easy_refresh.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../detail/presentation/widgets/image_gallery_page.dart';
import '../../drawer_features/presentation/chaohua_detail_page.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../../feed/presentation/widgets/tweet_card.dart';
import '../../profile/presentation/user_profile_page.dart';
import '../data/models/weibo_topic_header_model.dart';
import '../data/search_repository.dart';
import 'widgets/weibo_topic_header_card.dart';

/// 微博全景搜索结果页 (支持顶部直接重新编辑搜索、相关博主/超话直达、超话实体检索、分类顶栏、热度综合与时间实时独立排布)
class SearchResultsPage extends ConsumerStatefulWidget {
  final String keyword;

  const SearchResultsPage({
    super.key,
    required this.keyword,
  });

  @override
  ConsumerState<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends ConsumerState<SearchResultsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _searchController;
  late String _currentKeyword;

  final List<WeiboStatusModel> _statuses = [];
  WeiboTopicHeaderModel? _topicHeader;
  WeiboStatusModel? _toppingStatus;
  List<WeiboUserModel> _matchedUsers = [];
  WeiboUserModel? _primaryMatchedUser;
  List<SearchChaohuaItem> _matchedChaohuas = [];
  SearchChaohuaItem? _primaryMatchedChaohua;
  bool _isLoading = true;
  int _page = 1;
  bool _hasMore = true;

  final List<String> _tabs = [
    '综合',
    '实时',
    '用户',
    '超话',
    '图片',
    '视频',
    '关注',
    '热门',
    '评论',
    '话题',
    '地点',
    '商品',
  ];

  @override
  void initState() {
    super.initState();
    _currentKeyword = widget.keyword;
    _searchController = TextEditingController(text: _currentKeyword);
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _fetchSearch();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSearch() async {
    final cleanKeyword = _currentKeyword.trim();
    if (cleanKeyword.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    ref.read(storageServiceProvider).addSearchHistory(cleanKeyword);
    final repo = ref.read(searchRepositoryProvider);

    // 并发拉取：匹配博主、匹配超话、全景多维搜索结果
    final results = await Future.wait([
      repo.getSearchSuggestions(cleanKeyword).catchError((_) => const SearchSuggestResult()),
      repo.searchChaohua(cleanKeyword).catchError((_) => <SearchChaohuaItem>[]),
      repo.searchStatusesWithDetails(keyword: cleanKeyword, page: 1),
    ]);

    final suggestRes = results[0] as SearchSuggestResult;
    final chaohuas = results[1] as List<SearchChaohuaItem>;
    final searchRes = results[2] as SearchStatusesResult;

    if (mounted) {
      setState(() {
        if (suggestRes.users.isNotEmpty) {
          _matchedUsers = suggestRes.users;
          _primaryMatchedUser = suggestRes.users.first;
        } else {
          _matchedUsers = [];
          _primaryMatchedUser = null;
        }

        _matchedChaohuas = chaohuas;
        _primaryMatchedChaohua = chaohuas.isNotEmpty ? chaohuas.first : null;

        if (searchRes.topicHeader != null) {
          _topicHeader = searchRes.topicHeader;
        }
        if (searchRes.toppingStatus != null) {
          _toppingStatus = searchRes.toppingStatus;
        }
        _statuses.clear();
        _statuses.addAll(searchRes.statuses);
        _page = 1;
        _hasMore = searchRes.statuses.isNotEmpty;
        _isLoading = false;
      });
    }
  }

  Future<void> _reSearch(String newQuery) async {
    final clean = newQuery.trim();
    if (clean.isEmpty) return;

    HapticFeedbackUtil.light();
    FocusScope.of(context).unfocus();

    setState(() {
      _currentKeyword = clean;
      _topicHeader = null;
      _toppingStatus = null;
    });
    await _fetchSearch();
  }

  Future<bool> _loadMore() async {
    if (!_hasMore) return false;
    final repo = ref.read(searchRepositoryProvider);
    final nextPage = _page + 1;
    final list = await repo.searchStatuses(keyword: _currentKeyword.trim(), page: nextPage);

    if (mounted) {
      setState(() {
        _statuses.addAll(list);
        _page = nextPage;
        _hasMore = list.isNotEmpty;
      });
    }
    return list.isNotEmpty;
  }

  /// 微博时间解析器 (实时按发布时间倒序排布)
  DateTime _parseWeiboDate(String str) {
    try {
      return DateTime.parse(str);
    } catch (_) {}
    try {
      final parts = str.split(' ');
      if (parts.length >= 6) {
        const months = {
          'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
          'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
        };
        final month = months[parts[1]] ?? 1;
        final day = int.tryParse(parts[2]) ?? 1;
        final timeParts = parts[3].split(':');
        final hour = int.tryParse(timeParts[0]) ?? 0;
        final minute = int.tryParse(timeParts[1]) ?? 0;
        final second = int.tryParse(timeParts[2]) ?? 0;
        final year = int.tryParse(parts[5]) ?? 2026;
        return DateTime(year, month, day, hour, minute, second);
      }
    } catch (_) {}
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _searchController,
            autofocus: false,
            textInputAction: TextInputAction.search,
            textAlignVertical: TextAlignVertical.center,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.25,
              color: colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 40),
              suffixIcon: _searchController.text.isNotEmpty
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedbackUtil.light();
                        _searchController.clear();
                        setState(() {});
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.clear_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 40),
              hintText: '搜索微博、超话、用户...',
              hintStyle: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            onSubmitted: _reSearch,
            onChanged: (val) {
              setState(() {});
            },
          ),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12, left: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _reSearch(_searchController.text),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Text(
                    '搜索',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: EasyRefresh(
        onRefresh: _fetchSearch,
        onLoad: () async {
          final hasMore = await _loadMore();
          return hasMore ? IndicatorResult.success : IndicatorResult.noMore;
        },
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
            : CustomScrollView(
                slivers: [
                  // 0. 微博官方词条介绍卡片 (严格位于搜索栏和顶栏分栏中间)
                  if (_topicHeader != null)
                    SliverToBoxAdapter(
                      child: WeiboTopicHeaderCard(topic: _topicHeader!),
                    ),

                  // 1. 最顶层：相关博主直达卡片
                  if (_primaryMatchedUser != null && _tabController.index == 0 && _topicHeader?.hostUid != _primaryMatchedUser!.id)
                    SliverToBoxAdapter(
                      child: _buildMatchedUserCard(context, _primaryMatchedUser!, colorScheme, isDark),
                    ),

                  // 2. 超话直达卡片 (在综合页置顶展示匹配到的核心超话实体)
                  if (_primaryMatchedChaohua != null && _tabController.index == 0)
                    SliverToBoxAdapter(
                      child: _buildMatchedChaohuaCard(context, _primaryMatchedChaohua!, colorScheme, isDark),
                    ),

                  // 3. 中间层：12 大分类顶栏（综合、实时、用户、超话、图片、视频、关注、热门、评论、话题、地点、商品）
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabBarHeaderDelegate(
                      child: Container(
                        color: theme.scaffoldBackgroundColor,
                        child: Column(
                          children: [
                            TabBar(
                              controller: _tabController,
                              isScrollable: true,
                              tabAlignment: TabAlignment.start,
                              indicatorSize: TabBarIndicatorSize.label,
                              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
                              tabs: _tabs.map((t) => Tab(text: t)).toList(),
                            ),
                            Divider(
                              height: 1,
                              thickness: 0.5,
                              color: theme.dividerColor.withValues(alpha: 0.2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 4. 内容流：根据当前选中的 Tab 呈现对应维度的检索内容
                  _buildTabContentSliver(context, colorScheme),
                ],
              ),
      ),
    );
  }

  /// 相关博主直达卡片
  Widget _buildMatchedUserCard(
    BuildContext context,
    WeiboUserModel user,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1F24) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
          width: 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedbackUtil.light();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (ctx) => UserProfilePage(
                user: user,
                uid: user.id,
                screenName: user.screenName,
              ),
            ),
          );
        },
        child: Row(
          children: [
            // 完整高清头像
            AppAvatar(
              url: user.avatar,
              size: 50,
              name: user.screenName,
              verified: user.verified,
              verifiedType: user.verifiedType,
            ),
            const SizedBox(width: 14),

            // 博主昵称、认证信息与实时粉丝数
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.screenName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (user.verified) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.verified,
                          size: 15,
                          color: user.verifiedType == 0 ? const Color(0xFFFFB300) : const Color(0xFF00B0FF),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (user.verifiedReason.isNotEmpty || user.description.isNotEmpty)
                    Text(
                      user.verifiedReason.isNotEmpty ? user.verifiedReason : user.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '粉丝 ${user.followersCountStr}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (user.statusesCount > 0) ...[
                        Text(
                          ' · 微博 ${user.statusesCount}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // 查看主页胶囊
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '主页',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 10,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 相关超话直达卡片 (综合页顶部)
  Widget _buildMatchedChaohuaCard(
    BuildContext context,
    SearchChaohuaItem chaohua,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1F24) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
          width: 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedbackUtil.light();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (ctx) => ChaohuaDetailPage(
                containerid: chaohua.pageId,
                title: chaohua.title,
                avatar: chaohua.image,
                desc: chaohua.description,
              ),
            ),
          );
        },
        child: Row(
          children: [
            // 超话封面头像
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: chaohua.image.isNotEmpty
                  ? Image.network(
                      chaohua.image,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 50,
                        height: 50,
                        color: colorScheme.primaryContainer,
                        child: Icon(Icons.diamond_rounded, color: colorScheme.onPrimaryContainer, size: 26),
                      ),
                    )
                  : Container(
                      width: 50,
                      height: 50,
                      color: colorScheme.primaryContainer,
                      child: Icon(Icons.diamond_rounded, color: colorScheme.onPrimaryContainer, size: 26),
                    ),
            ),
            const SizedBox(width: 14),

            // 超话名称与简介
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          chaohua.title.endsWith('超话') ? chaohua.title : '${chaohua.title}超话',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.diamond_rounded, size: 15, color: colorScheme.primary),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (chaohua.description.isNotEmpty)
                    Text(
                      chaohua.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),

            // 进入超话胶囊按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '进入超话',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 10,
                    color: colorScheme.onPrimary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 各分类内容流构建
  Widget _buildTabContentSliver(BuildContext context, ColorScheme colorScheme) {
    final currentTab = _tabs[_tabController.index];

    // 1. 用户 Tab
    if (currentTab == '用户') {
      if (_matchedUsers.isEmpty) {
        return const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('暂无相关用户')),
        );
      }
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final u = _matchedUsers[index];
            return ListTile(
              leading: AppAvatar(
                url: u.avatar,
                size: 42,
                name: u.screenName,
                verified: u.verified,
                verifiedType: u.verifiedType,
              ),
              title: Text(u.screenName, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(u.verifiedReason.isNotEmpty ? u.verifiedReason : '粉丝 ${u.followersCountStr}'),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => UserProfilePage(user: u, uid: u.id, screenName: u.screenName),
                  ),
                );
              },
            );
          },
          childCount: _matchedUsers.length,
        ),
      );
    }

    // 2. 超话 Tab (搜索超话实体本身列表)
    if (currentTab == '超话') {
      if (_matchedChaohuas.isEmpty) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.diamond_outlined, size: 54, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                Text(
                  '暂无"$_currentKeyword"相关超话',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                ),
              ],
            ),
          ),
        );
      }
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final ch = _matchedChaohuas[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ch.image.isNotEmpty
                    ? Image.network(
                        ch.image,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 48,
                          height: 48,
                          color: colorScheme.primaryContainer,
                          child: Icon(Icons.diamond_rounded, color: colorScheme.onPrimaryContainer),
                        ),
                      )
                    : Container(
                        width: 48,
                        height: 48,
                        color: colorScheme.primaryContainer,
                        child: Icon(Icons.diamond_rounded, color: colorScheme.onPrimaryContainer),
                      ),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      ch.title.endsWith('超话') ? ch.title : '${ch.title}超话',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.diamond_rounded, size: 16, color: colorScheme.primary),
                ],
              ),
              subtitle: ch.description.isNotEmpty
                  ? Text(
                      ch.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                    )
                  : null,
              trailing: FilledButton.tonal(
                onPressed: () {
                  HapticFeedbackUtil.light();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => ChaohuaDetailPage(
                        containerid: ch.pageId,
                        title: ch.title,
                        avatar: ch.image,
                        desc: ch.description,
                      ),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('进入超话', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              onTap: () {
                HapticFeedbackUtil.light();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => ChaohuaDetailPage(
                      containerid: ch.pageId,
                      title: ch.title,
                      avatar: ch.image,
                      desc: ch.description,
                    ),
                  ),
                );
              },
            );
          },
          childCount: _matchedChaohuas.length,
        ),
      );
    }

    // 3. 图片 Tab (3 列瀑布网格呈现所有带图搜索微博)
    if (currentTab == '图片') {
      final allPics = <Map<String, dynamic>>[];
      for (final s in _statuses) {
        for (final p in s.pics) {
          allPics.add({'pic': p, 'statusId': s.id, 'pics': s.pics, 'authorName': s.user.screenName});
        }
      }

      if (allPics.isEmpty) {
        return const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('暂无图片内容')),
        );
      }

      return SliverPadding(
        padding: const EdgeInsets.all(12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 1.0,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = allPics[index];
              final pic = item['pic'] as WeiboPicModel;
              final statusPics = item['pics'] as List<WeiboPicModel>;
              final picIndex = statusPics.indexOf(pic);

              return GestureDetector(
                onTap: () {
                  HapticFeedbackUtil.light();
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      opaque: false,
                      pageBuilder: (_, __, ___) => ImageGalleryPage(
                        pics: statusPics,
                        initialIndex: picIndex >= 0 ? picIndex : 0,
                        statusId: item['statusId'],
                        authorName: item['authorName'],
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ExtendedImage.network(
                    pic.bmiddleUrl.isNotEmpty ? pic.bmiddleUrl : pic.largeUrl,
                    headers: ApiConstants.imageHeaders,
                    fit: BoxFit.cover,
                  ),
                ),
              );
            },
            childCount: allPics.length,
          ),
        ),
      );
    }

    // 4. 默认/综合/实时/热门/视频/评论/话题/地点/商品 列表流
    if (_statuses.isEmpty && _toppingStatus == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_rounded, size: 54, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(
                '暂无"$currentTab"相关内容',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (currentTab == '综合') {
      // 综合栏：完全沿用微博官方返回的内容与原始流顺序，仅适配 UI 层次
      // 1. 话题官方置顶博文 (若存在) 置于信息流首位
      // 2. 话题关联官方热门账号 (若存在) 置于置顶博文下方
      // 3. 官方搜索流内容按官方返回顺序逐条呈现 (若列表中包含置顶博文则去重，避免重复展示)
      final feedStatuses = List<WeiboStatusModel>.from(_statuses);
      if (_toppingStatus != null) {
        feedStatuses.removeWhere((s) => s.id == _toppingStatus!.id || s.mid == _toppingStatus!.mid);
      }

      final hasTopping = _toppingStatus != null;
      final totalCount = (hasTopping ? 1 : 0) + feedStatuses.length;

      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (hasTopping && index == 0) {
              return TweetCard(
                status: _toppingStatus!,
                isDetail: false,
              );
            }
            final statusIndex = index - (hasTopping ? 1 : 0);
            final status = feedStatuses[statusIndex];
            return TweetCard(
              status: status,
              isDetail: false,
            );
          },
          childCount: totalCount,
        ),
      );
    }

    List<WeiboStatusModel> displayList = _statuses;
    if (currentTab == '实时') {
      displayList = List.from(_statuses)..sort((a, b) => _parseWeiboDate(b.createdAt).compareTo(_parseWeiboDate(a.createdAt)));
    } else if (currentTab == '热门') {
      displayList = List.from(_statuses)..sort((a, b) => (b.repostsCount + b.attitudesCount).compareTo(a.repostsCount + a.attitudesCount));
    } else if (currentTab == '视频') {
      displayList = _statuses.where((s) => s.textRaw.contains('视频') || s.textRaw.contains('http')).toList();
      if (displayList.isEmpty) displayList = _statuses;
    } else if (currentTab == '话题') {
      displayList = _statuses.where((s) => s.textRaw.contains('#')).toList();
      if (displayList.isEmpty) displayList = _statuses;
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final status = displayList[index];
          return TweetCard(
            status: status,
            isDetail: false,
          );
        },
        childCount: displayList.length,
      ),
    );
  }
}

class _TabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _TabBarHeaderDelegate({required this.child});

  @override
  double get minExtent => 49.0;

  @override
  double get maxExtent => 49.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _TabBarHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}
