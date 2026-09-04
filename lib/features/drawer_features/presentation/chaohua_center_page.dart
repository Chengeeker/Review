import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../search/data/search_repository.dart';
import 'chaohua_detail_page.dart';

/// 微博原生超话中心大厅 (支持分类浏览、实时超话检索、无限滚动预加载与一键直达)
class ChaohuaCenterPage extends ConsumerStatefulWidget {
  const ChaohuaCenterPage({super.key});

  @override
  ConsumerState<ChaohuaCenterPage> createState() => _ChaohuaCenterPageState();
}

class _ChaohuaCenterPageState extends ConsumerState<ChaohuaCenterPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // 官方超话分类
  final List<Map<String, dynamic>> _categories = [
    {'id': 'all', 'name': '推荐'},
    {'id': '126', 'name': '游戏'},
    {'id': '187', 'name': '电竞'},
    {'id': '97', 'name': '动漫'},
    {'id': '98', 'name': '体育'},
    {'id': '2', 'name': '明星'},
    {'id': '184', 'name': '红人'},
    {'id': '181', 'name': '影视综'},
    {'id': '190', 'name': 'AI'},
    {'id': '94', 'name': '读书'},
    {'id': '188', 'name': '生活'},
    {'id': '133', 'name': '学习'},
  ];

  int _selectedCategoryIndex = 0;
  final List<SearchChaohuaItem> _chaohuaList = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _page = 1;
  bool _hasMore = true;
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchCategoryTopics(_categories[_selectedCategoryIndex]['name'] as String);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchCategoryTopics(String categoryName) async {
    setState(() {
      _isLoading = true;
      _page = 1;
      _hasMore = true;
      _currentQuery = categoryName == '推荐' ? '超话' : categoryName;
    });

    final searchRepo = ref.read(searchRepositoryProvider);
    final results = await searchRepo.searchChaohua(_currentQuery, page: 1);

    if (mounted) {
      setState(() {
        _chaohuaList.clear();
        _chaohuaList.addAll(results);
        _isLoading = false;
        _hasMore = results.isNotEmpty;
      });
    }
  }

  Future<void> _performSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    _searchFocusNode.unfocus();
    setState(() {
      _isLoading = true;
      _page = 1;
      _hasMore = true;
      _currentQuery = clean;
    });

    final searchRepo = ref.read(searchRepositoryProvider);
    final results = await searchRepo.searchChaohua(clean, page: 1);

    if (mounted) {
      setState(() {
        _chaohuaList.clear();
        _chaohuaList.addAll(results);
        _isLoading = false;
        _hasMore = results.isNotEmpty;
      });
    }
  }

  Future<bool> _loadMoreTopics() async {
    if (!_hasMore || _isLoading || _isLoadingMore) return false;

    _isLoadingMore = true;
    final nextPage = _page + 1;
    final searchRepo = ref.read(searchRepositoryProvider);
    final nextResults = await searchRepo.searchChaohua(_currentQuery, page: nextPage);

    if (mounted) {
      final existingIds = _chaohuaList.map((e) => e.pageId).toSet();
      final newItems = nextResults.where((e) => !existingIds.contains(e.pageId)).toList();

      setState(() {
        _page = nextPage;
        _chaohuaList.addAll(newItems);
        _hasMore = nextResults.isNotEmpty;
        _isLoadingMore = false;
      });
    }
    return nextResults.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('超话中心', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // 1. 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索感兴趣的超话社区...',
                hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _fetchCategoryTopics(_categories[_selectedCategoryIndex]['name'] as String);
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() {}),
              onSubmitted: _performSearch,
            ),
          ),

          // 2. 分类横滑选择栏
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = index == _selectedCategoryIndex;
                return ChoiceChip(
                  label: Text(
                    cat['name'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: colorScheme.primaryContainer,
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  side: BorderSide(
                    color: isSelected ? colorScheme.primary : Colors.transparent,
                    width: 1.0,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  onSelected: (selected) {
                    if (selected && _selectedCategoryIndex != index) {
                      HapticFeedbackUtil.selection();
                      setState(() {
                        _selectedCategoryIndex = index;
                        _searchController.clear();
                      });
                      _fetchCategoryTopics(cat['name'] as String);
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // 3. 超话实体列表 (支持 55%~70% 阈值无感预加载与双保险翻页)
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: colorScheme.primary),
                  )
                : _chaohuaList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.diamond_outlined, size: 56, color: colorScheme.outlineVariant),
                            const SizedBox(height: 12),
                            Text(
                              '暂未找到相关超话',
                              style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : EasyRefresh(
                        controller: EasyRefreshController(
                          controlFinishRefresh: false,
                          controlFinishLoad: false,
                        ),
                        onRefresh: () => _fetchCategoryTopics(
                          _searchController.text.isNotEmpty
                              ? _searchController.text
                              : _categories[_selectedCategoryIndex]['name'] as String,
                        ),
                        onLoad: () async {
                          final hasMore = await _loadMoreTopics();
                          return hasMore ? IndicatorResult.success : IndicatorResult.noMore;
                        },
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification.metrics.maxScrollExtent > 0) {
                              final progress = notification.metrics.pixels / notification.metrics.maxScrollExtent;
                              final remainingDistance = notification.metrics.maxScrollExtent - notification.metrics.pixels;
                              // 当滑动浏览达到 55%~70% 阈值，或剩余可视距离小于 1200dp 时，提前在后台无感预加载下一页
                              if (progress >= 0.55 || remainingDistance < 1200) {
                                if (_hasMore && !_isLoading && !_isLoadingMore) {
                                  _loadMoreTopics();
                                }
                              }
                            }
                            return false;
                          },
                          child: ListView.separated(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _chaohuaList.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
                            itemBuilder: (context, index) {
                              // 滑动到最后 5 项时触发预加载
                              if (index >= _chaohuaList.length - 5 && _hasMore && !_isLoading && !_isLoadingMore) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  _loadMoreTopics();
                                });
                              }
                              final item = _chaohuaList[index];
                              return _buildChaohuaItem(context, item, colorScheme);
                            },
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildChaohuaItem(BuildContext context, SearchChaohuaItem item, ColorScheme colorScheme) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      leading: AppAvatar(
        url: item.image,
        size: 48,
        name: item.title,
      ),
      title: Row(
        children: [
          const Icon(Icons.diamond_rounded, size: 16, color: Color(0xFFFF8200)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          item.description.isNotEmpty ? item.description : '微博热门超话社区',
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: FilledButton.tonal(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () {
          HapticFeedbackUtil.light();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (ctx) => ChaohuaDetailPage(
                containerid: item.pageId,
                title: item.title,
                avatar: item.image,
                desc: item.description,
              ),
            ),
          );
        },
        child: const Text('进入', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ),
      onTap: () {
        HapticFeedbackUtil.light();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => ChaohuaDetailPage(
              containerid: item.pageId,
              title: item.title,
              avatar: item.image,
              desc: item.description,
            ),
          ),
        );
      },
    );
  }
}
