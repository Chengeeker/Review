import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/design_system/components/review_frosted_app_bar.dart';
import '../../auth/presentation/login_page.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../../feed/presentation/widgets/tweet_card.dart';
import '../data/following_search_repository.dart';

class FollowingSearchPage extends ConsumerStatefulWidget {
  const FollowingSearchPage({super.key});

  @override
  ConsumerState<FollowingSearchPage> createState() =>
      _FollowingSearchPageState();
}

class _FollowingSearchPageState extends ConsumerState<FollowingSearchPage> {
  final _keyword = TextEditingController();
  final _scroll = ScrollController();
  final _types = followingSearchTypes.keys.toSet();
  final _statuses = <WeiboStatusModel>[];
  DateTime? _startDate;
  DateTime _endDate = DateUtils.dateOnly(DateTime.now());
  FollowingSearchFilter? _submitted;
  bool _loading = false;
  bool _hasMore = false;
  String? _error;
  int _page = 0;
  int _total = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadNearBottom);
  }

  void _loadNearBottom() {
    if (mounted &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 600 &&
        _hasMore &&
        !_loading &&
        _error == null) {
      _search(more: true);
    }
  }

  @override
  void dispose() {
    _keyword.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final date = await showDatePicker(
      context: context,
      initialDate: start ? (_startDate ?? _endDate) : _endDate,
      firstDate: DateTime(2009, 8, 14),
      lastDate: DateUtils.dateOnly(DateTime.now()),
    );
    if (date != null && mounted) {
      setState(() {
        if (start) {
          _startDate = date;
        } else {
          _endDate = date;
        }
      });
    }
  }

  Future<void> _search({bool more = false, bool retry = false}) async {
    if (_loading && more) return;
    final filter = more || retry
        ? _submitted
        : FollowingSearchFilter(
            keyword: _keyword.text,
            types: _types,
            startDate: _startDate,
            endDate: _endDate,
          );
    if (filter == null) return;
    try {
      filter.query(1);
    } on ArgumentError catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${error.message}')));
      return;
    }
    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    final nextPage = more ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _submitted = filter;
        _statuses.clear();
        _page = 0;
        _total = 0;
        _hasMore = false;
      }
    });
    if (!more && _scroll.hasClients) _scroll.jumpTo(0);
    try {
      final result = await ref
          .read(followingSearchRepositoryProvider)
          .search(filter, page: nextPage);
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = _statuses.map((status) => status.id).toSet();
        _statuses.addAll(result.statuses.where((status) => ids.add(status.id)));
        _page = nextPage;
        _total = result.total;
        _hasMore = result.hasMore;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '搜索失败，请确认网页端登录状态或稍后重试');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadNearBottom());
      }
    }
  }

  String _dateLabel(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final loggedIn = ref.watch(authProvider.select((auth) => auth.isLoggedIn));
    return Scaffold(
      appBar: const ReviewFrostedAppBar(title: Text('高级搜索')),
      body: !loggedIn
          ? Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const LoginPage())),
                child: const Text('登录后搜索我关注的人的微博'),
              ),
            )
          : ListView.builder(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: _statuses.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '搜索我关注的人的微博',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final type in followingSearchTypes.entries)
                              FilterChip(
                                label: Text(type.value),
                                selected: _types.contains(type.key),
                                onSelected: (selected) => setState(() {
                                  if (selected) {
                                    _types.add(type.key);
                                  } else {
                                    _types.remove(type.key);
                                  }
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _keyword,
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            labelText: '关键字',
                            hintText: '搜索我关注的人的微博',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onSubmitted: (_) => _search(),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton(
                              onPressed: () => _pickDate(true),
                              child: Text(
                                _startDate == null
                                    ? '开始日期（不限）'
                                    : _dateLabel(_startDate!),
                              ),
                            ),
                            if (_startDate != null)
                              IconButton(
                                tooltip: '清除开始日期',
                                onPressed: () =>
                                    setState(() => _startDate = null),
                                icon: const Icon(Icons.close),
                              ),
                            const Text('到'),
                            OutlinedButton(
                              onPressed: () => _pickDate(false),
                              child: Text(_dateLabel(_endDate)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _loading ? null : () => _search(),
                          icon: const Icon(Icons.search),
                          label: const Text('搜索'),
                        ),
                        if (_submitted != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              _loading && _page == 0
                                  ? '搜索中…'
                                  : _error != null && _page == 0
                                  ? '搜索未完成'
                                  : '搜索到 $_total 条微博',
                            ),
                          ),
                      ],
                    ),
                  );
                }
                if (index <= _statuses.length) {
                  return TweetCard(
                    status: _statuses[index - 1],
                    showFeedReason: true,
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: _loading
                        ? const CircularProgressIndicator()
                        : _error != null
                        ? Column(
                            children: [
                              Text(_error!),
                              TextButton(
                                onPressed: () =>
                                    _search(more: _page > 0, retry: true),
                                child: const Text('重试'),
                              ),
                            ],
                          )
                        : _hasMore
                        ? const SizedBox(height: 24)
                        : Text(
                            _submitted == null
                                ? '选择条件后搜索'
                                : _statuses.isEmpty
                                ? '暂无微博'
                                : '没有更多微博了',
                          ),
                  ),
                );
              },
            ),
    );
  }
}
