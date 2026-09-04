import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../data/search_repository.dart';
import 'search_results_page.dart';
import 'search_view.dart';

import 'package:flutter/services.dart';

/// 独立微博热搜大厅 (底栏热搜 Tab / 包含 9 大分类顶栏)
class HotTrendsView extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const HotTrendsView({
    super.key,
    this.initialTabIndex = 1, // 默认高亮“热搜”总榜
  });

  @override
  ConsumerState<HotTrendsView> createState() => _HotTrendsViewState();
}

class _HotTrendsViewState extends ConsumerState<HotTrendsView> with SingleTickerProviderStateMixin {
  static const MethodChannel _locationChannel = MethodChannel('com.sharelite/cookies');
  late TabController _tabController;
  String _currentCity = '佛山'; // 默认定位城市 (支持用户自主选择与动态切换)
  bool _isSystemLocation = false; // 是否为系统定位城市

  final List<Map<String, String>> _categories = [
    {'key': 'mine', 'name': '我的'},
    {'key': 'hot', 'name': '热搜'},
    {'key': 'ent', 'name': '文娱'},
    {'key': 'life', 'name': '生活'},
    {'key': 'social', 'name': '社会'},
    {'key': 'local', 'name': '佛山'}, // 动态依据 _currentCity 显示
    {'key': 'sports', 'name': '体育'},
    {'key': 'acg', 'name': 'ACG'},
    {'key': 'tech', 'name': '科技'},
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

  Future<void> _requestAndDetectSystemLocation({bool showFeedback = false}) async {
    try {
      final String? city = await _locationChannel.invokeMethod<String>('getSystemLocationCity');
      if (city != null && city.trim().isNotEmpty && mounted) {
        setState(() {
          _currentCity = city.trim();
          _isSystemLocation = true;
          _categories[5]['name'] = _currentCity;
        });
        if (showFeedback && mounted) {
          AppToast.show(context, '📍 已获取系统定位城市：$_currentCity');
        }
      }
    } catch (_) {}
  }

  void _showCityPickerDialog() {
    HapticFeedbackUtil.light();
    final cities = ['佛山', '广州', '深圳', '北京', '上海', '成都', '杭州', '武汉', '南京', '重庆', '西安', '长沙'];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择定位城市'),
        children: [
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx);
              await _requestAndDetectSystemLocation(showFeedback: true);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.my_location_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '重新申请并获取系统定位',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  if (_isSystemLocation)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '系统定位',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          ...cities.map((c) {
            final isSelected = c == _currentCity && !_isSystemLocation;
            return SimpleDialogOption(
              onPressed: () {
                HapticFeedbackUtil.light();
                setState(() {
                  _currentCity = c;
                  _isSystemLocation = false;
                  _categories[5]['name'] = c;
                });
                Navigator.pop(ctx);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Theme.of(context).colorScheme.primary : null,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary, size: 18),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('微博热搜', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          // 城市切换与系统定位标注
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _showCityPickerDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isSystemLocation ? Icons.my_location_rounded : Icons.location_on_rounded,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isSystemLocation ? '$_currentCity (系统定位)' : _currentCity,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
          tabs: _categories.map((c) {
            if (c['key'] == 'local') {
              return Tab(text: _isSystemLocation ? '$_currentCity·系统定位' : _currentCity);
            }
            return Tab(text: c['name']);
          }).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _categories.map((c) {
          return _HotCategoryListView(
            categoryKey: c['key']!,
            city: _currentCity,
          );
        }).toList(),
      ),
    );
  }
}

/// 单个分类的热搜列表
class _HotCategoryListView extends ConsumerStatefulWidget {
  final String categoryKey;
  final String city;

  const _HotCategoryListView({
    required this.categoryKey,
    required this.city,
  });

  @override
  ConsumerState<_HotCategoryListView> createState() => _HotCategoryListViewState();
}

class _HotCategoryListViewState extends ConsumerState<_HotCategoryListView> with AutomaticKeepAliveClientMixin {
  List<HotSearchItem> _items = [];
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchList();
  }

  @override
  void didUpdateWidget(covariant _HotCategoryListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.city != widget.city && widget.categoryKey == 'local') {
      _fetchList();
    }
  }

  Future<void> _fetchList() async {
    final repo = ref.read(searchRepositoryProvider);
    final list = await repo.getCategoryHotSearch(widget.categoryKey, city: widget.city);
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

  String _formatNumber(int num) {
    if (num <= 0) return '';
    if (num >= 10000) {
      return '${(num / 10000).toStringAsFixed(1)}万';
    }
    return '$num';
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
            Icon(Icons.local_fire_department_outlined, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              '暂无该分类热搜',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
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
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 40, thickness: 0.5),
        itemBuilder: (context, index) {
          final item = _items[index];
          return _buildHotRow(context, item, index, colorScheme);
        },
      ),
    );
  }

  Widget _buildHotRow(
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
      borderRadius: BorderRadius.circular(12),
      onTap: () => _navigateToSearch(item.word),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            // 序号
            SizedBox(
              width: 32,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: index < 3 ? FontWeight.w900 : FontWeight.bold,
                  color: rankColor,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 词条与统计
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.word,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (item.labelName != null && item.labelName!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _buildTagBadge(item.labelName!, colorScheme),
                      ],
                      if (item.category != null && item.category!.isNotEmpty && widget.categoryKey == 'hot') ...[
                        const SizedBox(width: 4),
                        _buildCategoryBadge(item.category!, colorScheme),
                      ],
                    ],
                  ),
                  if (item.num > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${_formatNumber(item.num)} 讨论',
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
