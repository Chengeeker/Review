import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/components/review_frosted_app_bar.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../../feed/presentation/widgets/tweet_card.dart';
import '../data/search_repository.dart';

class ChaohuaSearchPage extends ConsumerStatefulWidget {
  const ChaohuaSearchPage({
    super.key,
    required this.pageId,
    required this.title,
  });
  final String pageId;
  final String title;

  @override
  ConsumerState<ChaohuaSearchPage> createState() => _ChaohuaSearchPageState();
}

class _ChaohuaSearchPageState extends ConsumerState<ChaohuaSearchPage> {
  final _input = TextEditingController();
  final _statuses = <WeiboStatusModel>[];
  String _submitted = '';
  String? _error;
  int _generation = 0;
  int _page = 0;
  bool _loading = false;
  bool _hasMore = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _search({bool next = false}) async {
    final keyword = next ? _submitted : _input.text.trim();
    if (keyword.isEmpty || (next && (_loading || !_hasMore))) return;
    FocusScope.of(context).unfocus();
    final generation = next ? _generation : ++_generation;
    final page = next ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = null;
      if (!next) {
        _submitted = keyword;
        _statuses.clear();
        _page = 0;
      }
    });
    try {
      final result = await ref
          .read(searchRepositoryProvider)
          .searchChaohuaPosts(
            pageId: widget.pageId,
            title: widget.title,
            keyword: keyword,
            page: page,
            isCurrent: () => mounted && generation == _generation,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = _statuses.map((s) => s.id).toSet();
        _statuses.addAll(result.statuses.where((s) => ids.add(s.id)));
        _page = page;
        _hasMore = result.hasMore;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '搜索失败，请重试');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ReviewFrostedAppBar(
        title: TextField(
          controller: _input,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索 ${widget.title} 内的帖子',
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _search(),
        ),
        actions: [
          IconButton(
            tooltip: '搜索本超话',
            icon: const Icon(Icons.search),
            onPressed: () => _search(),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('仅搜索「${widget.title}」内的帖子'),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => TweetCard(status: _statuses[index]),
              childCount: _statuses.length,
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (!_loading && _error != null)
            SliverToBoxAdapter(
              child: Center(
                child: TextButton(
                  onPressed: () => _search(next: _page > 0),
                  child: Text(_error!),
                ),
              ),
            ),
          if (!_loading && _error == null && _submitted.isNotEmpty) ...[
            if (_statuses.isEmpty)
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_hasMore ? '本页暂无匹配帖子，可继续搜索' : '暂无匹配帖子'),
                  ),
                ),
              ),
            if (_hasMore)
              SliverToBoxAdapter(
                child: Center(
                  child: TextButton(
                    onPressed: () => _search(next: true),
                    child: const Text('加载更多'),
                  ),
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }
}
