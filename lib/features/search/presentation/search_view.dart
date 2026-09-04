import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../../profile/presentation/user_profile_page.dart';
import '../data/search_repository.dart';
import 'hot_trends_view.dart';
import 'search_results_page.dart';

/// Material You Weibo Search View (实时搜索联想 / 用户直达卡片 / 搜索历史 / 前 9 个精选热搜 + 更多热搜跳转)
class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key});

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  List<HotSearchItem> _hotList = [];
  List<String> _historyList = [];
  bool _isLoadingHot = true;
  SearchSuggestResult? _suggestResult;
  bool _isLoadingSuggest = false;
  Timer? _debounceTimer;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _fetchHotSearch();
    _searchController.addListener(_onSearchTextChanged);
  }

  void _loadHistory() {
    final storage = ref.read(storageServiceProvider);
    setState(() {
      _historyList = storage.getSearchHistory();
    });
  }

  void _onSearchTextChanged() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _debounceTimer?.cancel();
      setState(() {
        _suggestResult = null;
        _isLoadingSuggest = false;
      });
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _fetchSuggestions(query);
    });
    setState(() {});
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() {
      _isLoadingSuggest = true;
    });

    try {
      final repo = ref.read(searchRepositoryProvider);
      final result = await repo.getSearchSuggestions(query);
      if (mounted && _searchController.text.trim() == query) {
        setState(() {
          _suggestResult = result;
          _isLoadingSuggest = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingSuggest = false;
        });
      }
    }
  }

  Future<void> _fetchHotSearch() async {
    setState(() {
      _isLoadingHot = true;
    });
    try {
      final repo = ref.read(searchRepositoryProvider);
      final list = await repo.getHotSearch();
      if (mounted) {
        setState(() {
          _hotList = list;
          _isLoadingHot = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingHot = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String keyword) async {
    final clean = keyword.trim();
    if (clean.isEmpty) return;

    HapticFeedbackUtil.light();
    final storage = ref.read(storageServiceProvider);
    await storage.addSearchHistory(clean);
    _loadHistory();

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => SearchResultsPage(keyword: clean),
      ),
    );

    // 返回时刷新搜索历史
    if (mounted) {
      _loadHistory();
    }
  }

  void _navigateToUserProfile(WeiboUserModel user) {
    HapticFeedbackUtil.light();
    final storage = ref.read(storageServiceProvider);
    storage.addSearchHistory(user.screenName);
    _loadHistory();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => UserProfilePage(
          user: user,
          uid: user.id,
          screenName: user.screenName,
        ),
      ),
    );
  }

  Future<void> _removeHistoryItem(String keyword) async {
    HapticFeedbackUtil.light();
    final storage = ref.read(storageServiceProvider);
    await storage.removeSearchHistory(keyword);
    _loadHistory();
  }

  Future<void> _confirmClearHistory() async {
    HapticFeedbackUtil.light();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空搜索历史'),
        content: const Text('确定要清空全部搜索历史记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      HapticFeedbackUtil.light();
      final storage = ref.read(storageServiceProvider);
      await storage.clearSearchHistory();
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isQuerying = _searchController.text.trim().isNotEmpty;

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
              hintText: '搜索微博、话题、用户...',
              hintStyle: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            onSubmitted: _performSearch,
          ),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12, left: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _performSearch(_searchController.text),
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
      body: isQuerying
          ? _buildSuggestionsView(context, colorScheme)
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 1. 第一部分：搜索历史
                _buildSearchHistorySection(context, colorScheme),

                const SizedBox(height: 20),
                const Divider(height: 1, thickness: 0.6),
                const SizedBox(height: 16),

                // 2. 第二部分：热门搜索 (前 9 个热搜 + 第 10 项“更多热搜”)
                _buildHotSearchSection(context, colorScheme),
              ],
            ),
    );
  }

  /// 搜索联想与用户直达卡片视图
  Widget _buildSuggestionsView(BuildContext context, ColorScheme colorScheme) {
    final query = _searchController.text.trim();
    final users = _suggestResult?.users ?? [];
    final suggestions = _suggestResult?.suggestions ?? [];

    if (_isLoadingSuggest && _suggestResult == null) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 1. 精准匹配用户直达卡片 (支持显示头像、ID、认证信息、粉丝数等)
        if (users.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.person_pin_rounded, size: 18, color: colorScheme.primary),
                const SizedBox(width: 6),
                const Text(
                  '用户直达',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          ...users.map((user) => _buildUserSuggestCard(context, user, colorScheme)),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 8),
        ],

        // 2. 搜索联想词列表
        if (suggestions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '相关搜索建议',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
          ),
          ...suggestions.map((word) => _buildSuggestWordRow(context, word, query, colorScheme)),
          const SizedBox(height: 4),
        ],

        // 3. 通用关键词全景搜索入口
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          visualDensity: VisualDensity.compact,
          leading: Icon(Icons.search_rounded, color: colorScheme.primary),
          title: Text(
            '搜索 "$query"',
            style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold),
          ),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 13),
          onTap: () => _performSearch(query),
        ),
      ],
    );
  }

  /// 用户直达卡片
  Widget _buildUserSuggestCard(
    BuildContext context,
    WeiboUserModel user,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
          width: 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _navigateToUserProfile(user),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 用户头像 (带认证标识)
              AppAvatar(
                url: user.avatar,
                size: 48,
                name: user.screenName,
                verified: user.verified,
                verifiedType: user.verifiedType,
              ),
              const SizedBox(width: 12),

              // 用户信息
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
                              fontSize: 15,
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
                            fontWeight: FontWeight.w600,
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

              // 进入主页指示
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 联想词列表行
  Widget _buildSuggestWordRow(
    BuildContext context,
    String word,
    String query,
    ColorScheme colorScheme,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      visualDensity: VisualDensity.compact,
      leading: Icon(
        Icons.search_rounded,
        size: 18,
        color: colorScheme.onSurfaceVariant,
      ),
      title: Text(
        word,
        style: const TextStyle(fontSize: 14.5),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.north_west_rounded, size: 15),
        tooltip: '填入搜索框',
        onPressed: () {
          _searchController.text = word;
          _searchController.selection = TextSelection.fromPosition(
            TextPosition(offset: word.length),
          );
        },
      ),
      onTap: () => _performSearch(word),
    );
  }

  /// 第一部分：搜索历史组件
  Widget _buildSearchHistorySection(BuildContext context, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.history_rounded, size: 19, color: colorScheme.primary),
                const SizedBox(width: 6),
                const Text(
                  '搜索历史',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (_historyList.isNotEmpty)
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                tooltip: '清空历史',
                visualDensity: VisualDensity.compact,
                onPressed: _confirmClearHistory,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_historyList.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _historyList.map((keyword) {
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _performSearch(keyword),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        keyword,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _removeHistoryItem(keyword),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.close_rounded,
                            size: 13,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '暂无搜索历史',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
      ],
    );
  }

  /// 第二部分：热门搜索精简区域 (前 9 项热搜 + 第 10 项“更多热搜”)
  Widget _buildHotSearchSection(BuildContext context, ColorScheme colorScheme) {
    final top9Items = _hotList.take(9).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.local_fire_department_rounded, size: 19, color: Color(0xFFFF5722)),
                SizedBox(width: 6),
                Text(
                  '热门搜索',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            IconButton(
              icon: Icon(
                Icons.refresh_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
              tooltip: '刷新热搜',
              visualDensity: VisualDensity.compact,
              onPressed: _fetchHotSearch,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingHot)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          )
        else if (top9Items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '暂无热门搜索',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 3.8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 2,
              ),
              itemCount: top9Items.length + 1, // 前 9 个热搜 + 1 个“更多热搜”
              itemBuilder: (context, index) {
                if (index < top9Items.length) {
                  final item = top9Items[index];
                  return _buildCompactHotItem(context, item, index, colorScheme);
                } else {
                  // 第 10 个位置：更多热搜按钮
                  return _buildMoreHotSearchButton(context, colorScheme);
                }
              },
            ),
          ),
      ],
    );
  }

  /// 紧凑热搜项
  Widget _buildCompactHotItem(
    BuildContext context,
    HotSearchItem item,
    int index,
    ColorScheme colorScheme,
  ) {
    Color rankColor;
    if (index == 0) {
      rankColor = const Color(0xFFFF2442);
    } else if (index == 1) {
      rankColor = const Color(0xFFFF7700);
    } else if (index == 2) {
      rankColor = const Color(0xFFFFB300);
    } else {
      rankColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _performSearch(item.word),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            // 序号
            SizedBox(
              width: 20,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: index < 3 ? FontWeight.w900 : FontWeight.bold,
                  color: rankColor,
                ),
              ),
            ),
            const SizedBox(width: 4),

            // 词条
            Expanded(
              child: Text(
                item.word,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: index < 3 ? FontWeight.w600 : FontWeight.normal,
                  color: colorScheme.onSurface,
                ),
              ),
            ),

            // 标签 (爆/热/新/沸)
            if (item.labelName != null && item.labelName!.isNotEmpty) ...[
              const SizedBox(width: 4),
              _buildTagBadge(item.labelName!, colorScheme),
            ],
          ],
        ),
      ),
    );
  }

  /// 第 10 个位置：“更多热搜”按钮
  Widget _buildMoreHotSearchButton(BuildContext context, ColorScheme colorScheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        HapticFeedbackUtil.light();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (ctx) => const HotTrendsView()),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_fire_department_rounded, size: 15, color: colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              '更多热搜',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_forward_ios_rounded, size: 11, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildTagBadge(String label, ColorScheme colorScheme) {
    Color bg = colorScheme.primaryContainer;
    Color fg = colorScheme.onPrimaryContainer;

    if (label == '热' || label == '爆') {
      bg = const Color(0xFFFF2442);
      fg = Colors.white;
    } else if (label == '新') {
      bg = const Color(0xFF00B0FF);
      fg = Colors.white;
    } else if (label == '沸') {
      bg = const Color(0xFFFF6D00);
      fg = Colors.white;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
