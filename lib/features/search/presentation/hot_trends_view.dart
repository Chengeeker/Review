import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../data/search_repository.dart';
import 'search_results_page.dart';
import 'search_view.dart';

/// 独立微博热搜大厅 (底栏热搜 Tab / 与网页端热搜导航保持一致)
class HotTrendsView extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const HotTrendsView({
    super.key,
    this.initialTabIndex = 1, // 默认高亮“热搜”总榜
  });

  @override
  ConsumerState<HotTrendsView> createState() => _HotTrendsViewState();
}

class _HotTrendsViewState extends ConsumerState<HotTrendsView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Map<String, String>> _categories = [
    {'key': 'mine', 'name': '我的'},
    {'key': 'hot', 'name': '热搜'},
    {'key': 'ent', 'name': '文娱'},
    {'key': 'social', 'name': '社会'},
    {'key': 'tech', 'name': '科技'},
    {'key': 'life', 'name': '生活'},
    {'key': 'sports', 'name': '体育'},
    {'key': 'acg', 'name': 'ACG'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _categories.length,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Read the same effective setting that builds MaterialApp's theme. This
    // keeps the tab labels responsive even when the font option changes while
    // this page is already open, instead of inferring it from bodyMedium.
    final fontWeightAdjustment =
        ref.watch(themeProvider).effectiveFontWeightAdjustment;

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('微博热搜', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          // 搜索按钮 (打开搜索落地页)
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: '搜索',
            onPressed: () {
              HapticFeedbackUtil.light();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => const SearchView()),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorSize: TabBarIndicatorSize.label,
          labelPadding: const EdgeInsets.symmetric(horizontal: 14),
          labelStyle: TextStyle(
            fontWeight: AppTheme.adjustFontWeight(
              FontWeight.w600,
              fontWeightAdjustment,
            ),
            fontSize: 15,
          ),
          unselectedLabelStyle: TextStyle(
            fontWeight: AppTheme.adjustFontWeight(
              FontWeight.normal,
              fontWeightAdjustment,
            ),
            fontSize: 14,
          ),
          tabs: _categories.map((c) => Tab(text: c['name'])).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _categories.map((c) {
          return _HotCategoryListView(
            categoryKey: c['key']!,
          );
        }).toList(),
      ),
    );
  }
}

/// 单个分类的热搜列表
class _HotCategoryListView extends ConsumerStatefulWidget {
  final String categoryKey;

  const _HotCategoryListView({
    required this.categoryKey,
  });

  @override
  ConsumerState<_HotCategoryListView> createState() =>
      _HotCategoryListViewState();
}

class _HotCategoryListViewState extends ConsumerState<_HotCategoryListView>
    with AutomaticKeepAliveClientMixin {
  List<HotSearchItem> _items = [];
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchList();
  }

  Future<void> _fetchList() async {
    final repo = ref.read(searchRepositoryProvider);
    final list = await repo.getCategoryHotSearch(widget.categoryKey);
    if (mounted) {
      setState(() {
        _items = list;
        _isLoading = false;
      });
    }
  }

  void _navigateToSearch(String keyword) {
    if (keyword.trim().isEmpty) return;
    HapticFeedbackUtil.light();

    // 自动沉淀至搜索历史
    ref.read(storageServiceProvider).addSearchHistory(keyword.trim());

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => SearchResultsPage(keyword: keyword.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_fire_department_outlined,
                size: 48,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              '暂无该分类热搜',
              style:
                  TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () {
                setState(() => _isLoading = true);
                _fetchList();
              },
              child: const Text('重新加载'),
            ),
          ],
        ),
      );
    }

    final themeState = ref.watch(themeProvider);
    final double bottomNavPadding = themeState.useFloatingNavBar ? 72.0 : 16.0;

    return EasyRefresh(
      onRefresh: _fetchList,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomNavPadding),
        itemCount: _items.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 52, thickness: 0.5),
        itemBuilder: (context, index) {
          final item = _items[index];
          return _buildHotRow(context, item, colorScheme);
        },
      ),
    );
  }

  Widget _buildHotRow(
    BuildContext context,
    HotSearchItem item,
    ColorScheme colorScheme,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _navigateToSearch(item.word),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            // 官方置顶、普通排名和不占排名的定位热搜使用不同标记。
            SizedBox(
              width: 40,
              child: _buildRankMarker(context, item, colorScheme),
            ),
            const SizedBox(width: 12),

            // 词条、标签与精确讨论数
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.word,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  context.adjustWeight(FontWeight.normal),
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (item.labelName != null &&
                            item.labelName!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _buildTagBadge(item.labelName!, colorScheme),
                        ],
                        if (item.locationLabel != null) ...[
                          const SizedBox(width: 6),
                          _buildLocationBadge(),
                        ],
                        if (item.category != null &&
                            item.category!.isNotEmpty &&
                            widget.categoryKey == 'hot') ...[
                          const SizedBox(width: 4),
                          _buildCategoryBadge(item.category!, colorScheme),
                        ],
                      ],
                    ),
                  ),
                  if (item.num > 0) ...[
                    const SizedBox(width: 10),
                    Text(
                      '${item.num} 讨论',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankMarker(
    BuildContext context,
    HotSearchItem item,
    ColorScheme colorScheme,
  ) {
    if (item.isPinned) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Icon(
          Icons.push_pin_rounded,
          size: 22,
          color: Color(0xFFFF6D00),
        ),
      );
    }

    if (!item.isRanked) {
      return Align(
        alignment: Alignment.center,
        child: Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
            color: Color(0xFFFF7A45),
            shape: BoxShape.circle,
          ),
        ),
      );
    }

    final rank = item.rank;
    if (rank <= 3) {
      final background = switch (rank) {
        1 => const Color(0xFFFF3852),
        2 => const Color(0xFFFF9406),
        _ => const Color(0xFFFFC229),
      };
      return Container(
        height: 24,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.local_fire_department_rounded,
              size: 15,
              color: Colors.white,
            ),
            Text(
              '$rank',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: context.adjustWeight(FontWeight.normal),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 24,
      decoration: BoxDecoration(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          color: colorScheme.surface,
          fontSize: 14,
          fontWeight: context.adjustWeight(FontWeight.normal),
        ),
      ),
    );
  }

  Widget _buildLocationBadge() {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: const Color(0xFF4CCB73),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.location_on_rounded,
        size: 14,
        color: Colors.white,
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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCategoryBadge(String cat, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Text(
        cat,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 9.5,
        ),
      ),
    );
  }
}
