import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../../feed/presentation/widgets/tweet_card.dart';
import '../../search/data/search_repository.dart';

/// 个人主页博主微博内容专属搜索页 (支持按关键词搜索指定博主的全部微博历史，支持分页滚动与无缝互动)
class UserTimelineSearchPage extends ConsumerStatefulWidget {
  final WeiboUserModel user;
  final bool autofocus;

  const UserTimelineSearchPage({
    super.key,
    required this.user,
    this.autofocus = true,
  });

  @override
  ConsumerState<UserTimelineSearchPage> createState() => _UserTimelineSearchPageState();
}

class _UserTimelineSearchPageState extends ConsumerState<UserTimelineSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  final List<WeiboStatusModel> _statuses = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  int _page = 1;
  bool _hasMore = true;
  String _currentKeyword = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _performSearch({bool isRefresh = false}) async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    _focusNode.unfocus();
    HapticFeedbackUtil.light();

    if (isRefresh) {
      setState(() {
        _isLoading = true;
        _hasSearched = true;
        _currentKeyword = query;
        _page = 1;
      });
    }

    final repo = ref.read(searchRepositoryProvider);
    final targetPage = isRefresh ? 1 : _page + 1;

    final results = await repo.searchUserStatuses(
      uid: widget.user.id,
      keyword: query,
      page: targetPage,
    );

    if (mounted) {
      setState(() {
        if (isRefresh) {
          _statuses.clear();
          _statuses.addAll(results);
          _page = 1;
        } else {
          final existingIds = _statuses.map((s) => s.id).toSet();
          for (final s in results) {
            if (!existingIds.contains(s.id)) {
              _statuses.add(s);
            }
          }
          _page = targetPage;
        }
        _hasMore = results.isNotEmpty;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Container(
          height: 42,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(21),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _performSearch(isRefresh: true),
            style: const TextStyle(fontSize: 14.5),
            decoration: InputDecoration(
              hintText: '搜索 @${widget.user.screenName} 的微博',
              hintStyle: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _statuses.clear();
                          _hasSearched = false;
                          _currentKeyword = '';
                        });
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: InputBorder.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _searchController.text.trim().isNotEmpty
                ? () => _performSearch(isRefresh: true)
                : null,
            child: Text(
              '搜索',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _searchController.text.trim().isNotEmpty
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: EasyRefresh(
        onRefresh: _hasSearched ? () => _performSearch(isRefresh: true) : null,
        onLoad: (_hasSearched && _hasMore && !_isLoading)
            ? () async {
                await _performSearch(isRefresh: false);
                return _hasMore ? IndicatorResult.success : IndicatorResult.noMore;
              }
            : null,
        child: CustomScrollView(
          slivers: [
            if (_isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (!_hasSearched)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.manage_search_rounded,
                        size: 64,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '输入关键词，检索 @${widget.user.screenName} 的微博',
                        style: TextStyle(
                          fontSize: 14.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_statuses.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 64,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '未找到与 "$_currentKeyword" 相关的微博',
                        style: TextStyle(
                          fontSize: 14.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '请尝试更换关键词搜索',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Text(
                    '包含 "$_currentKeyword" 的微博 (${_statuses.length}${_hasMore ? '+' : ''})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final status = _statuses[index];
                    return TweetCard(
                      status: status,
                    );
                  },
                  childCount: _statuses.length,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
