import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../auth/presentation/login_page.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../../feed/presentation/widgets/tweet_card.dart';

/// 赞和收藏 综合大厅 (双顶栏：我的赞 / 我的收藏)
class LikesFavoritesPage extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const LikesFavoritesPage({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<LikesFavoritesPage> createState() => _LikesFavoritesPageState();
}

class _LikesFavoritesPageState extends ConsumerState<LikesFavoritesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLoggedIn = authState.isLoggedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('赞和收藏', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          tabs: const [
            Tab(text: '我的赞'),
            Tab(text: '我的收藏'),
          ],
        ),
      ),
      body: !isLoggedIn
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_rounded,
                      size: 60, color: colorScheme.primary.withValues(alpha: 0.6)),
                  const SizedBox(height: 16),
                  const Text('登录后即可同步查看您点赞与收藏的微博',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (ctx) => const LoginPage()),
                      );
                    },
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('立即登录'),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: const [
                _LikesListView(),
                _FavoritesListView(),
              ],
            ),
    );
  }
}

/// 官方原生我的赞列表 (直连 /ajax/statuses/likelist?uid={uid}&page={page})
class _LikesListView extends ConsumerStatefulWidget {
  const _LikesListView();

  @override
  ConsumerState<_LikesListView> createState() => _LikesListViewState();
}

class _LikesListViewState extends ConsumerState<_LikesListView>
    with AutomaticKeepAliveClientMixin {
  final List<WeiboStatusModel> _statuses = [];
  bool _isLoading = true;
  int _page = 1;
  bool _hasMore = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchLikes(refresh: true);
  }

  Future<void> _fetchLikes({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      setState(() => _isLoading = true);
    }

    final client = ref.read(weiboDioClientProvider);
    final authState = ref.read(authProvider);
    var uid = authState.uid ?? '';

    if (uid.isEmpty) {
      await ref.read(authProvider.notifier).refreshUserProfile();
      uid = ref.read(authProvider).uid ?? '';
    }

    final extracted = <WeiboStatusModel>[];

    try {
      final res = await client.dio.get(
        '/ajax/statuses/likelist',
        queryParameters: {
          if (uid.isNotEmpty) 'uid': uid,
          'page': _page,
        },
      );
      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        final dynamic rawData = data['data'];
        final List rawList;
        if (rawData is List) {
          rawList = rawData;
        } else if (rawData is Map) {
          rawList = (rawData['list'] as List?) ?? (rawData['statuses'] as List?) ?? [];
        } else {
          rawList = (data['list'] as List?) ?? (data['statuses'] as List?) ?? [];
        }
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            final statusData = item['status'] is Map ? item['status'] as Map<String, dynamic> : item;
            final status = WeiboStatusModel.fromJson(statusData);
            extracted.add(status.copyWith(liked: true));
          }
        }
      }
    } catch (_) {}

    // Fallback: /ajax/profile/likelist
    if (extracted.isEmpty && _page == 1) {
      try {
        final res2 = await client.dio.get(
          '/ajax/profile/likelist',
          queryParameters: {
            if (uid.isNotEmpty) 'uid': uid,
            'page': _page,
          },
        );
        if (res2.data is Map<String, dynamic>) {
          final data = res2.data as Map<String, dynamic>;
          final dynamic rawData = data['data'];
          final List rawList;
          if (rawData is List) {
            rawList = rawData;
          } else if (rawData is Map) {
            rawList = (rawData['list'] as List?) ?? (rawData['statuses'] as List?) ?? [];
          } else {
            rawList = (data['list'] as List?) ?? (data['statuses'] as List?) ?? [];
          }
          for (final item in rawList) {
            if (item is Map<String, dynamic>) {
              final statusData = item['status'] is Map ? item['status'] as Map<String, dynamic> : item;
              final status = WeiboStatusModel.fromJson(statusData);
              extracted.add(status.copyWith(liked: true));
            }
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        if (refresh) {
          _statuses.clear();
        }
        _statuses.addAll(extracted);
        _hasMore = extracted.isNotEmpty;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    return EasyRefresh(
      onRefresh: () => _fetchLikes(refresh: true),
      onLoad: () async {
        _page++;
        await _fetchLikes(refresh: false);
        return _hasMore ? IndicatorResult.success : IndicatorResult.noMore;
      },
      child: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : _statuses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_border_rounded,
                          size: 54, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text(
                        '暂无点赞内容',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _statuses.length,
                  itemBuilder: (context, index) {
                    return TweetCard(
                      key: ValueKey('like_${_statuses[index].id}'),
                      status: _statuses[index],
                      isDetail: false,
                    );
                  },
                ),
    );
  }
}

/// 官方原生我的收藏列表 (直连 /ajax/favorites/all_fav?page={page})
class _FavoritesListView extends ConsumerStatefulWidget {
  const _FavoritesListView();

  @override
  ConsumerState<_FavoritesListView> createState() => _FavoritesListViewState();
}

class _FavoritesListViewState extends ConsumerState<_FavoritesListView>
    with AutomaticKeepAliveClientMixin {
  final List<WeiboStatusModel> _statuses = [];
  bool _isLoading = true;
  int _page = 1;
  bool _hasMore = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchFavorites(refresh: true);
  }

  Future<void> _fetchFavorites({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      setState(() => _isLoading = true);
    }

    final client = ref.read(weiboDioClientProvider);
    final extracted = <WeiboStatusModel>[];

    try {
      final res = await client.dio.get(
        '/ajax/favorites/all_fav',
        queryParameters: {'page': _page},
      );
      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        final dynamic rawData = data['data'];
        final List rawList;
        if (rawData is List) {
          rawList = rawData;
        } else if (rawData is Map) {
          rawList = (rawData['list'] as List?) ?? (rawData['statuses'] as List?) ?? [];
        } else {
          rawList = (data['list'] as List?) ?? (data['statuses'] as List?) ?? [];
        }
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            final statusData = item['status'] is Map ? item['status'] as Map<String, dynamic> : item;
            final status = WeiboStatusModel.fromJson(statusData);
            extracted.add(status.copyWith(favorited: true));
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        if (refresh) {
          _statuses.clear();
        }
        _statuses.addAll(extracted);
        _hasMore = extracted.isNotEmpty;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    return EasyRefresh(
      onRefresh: () => _fetchFavorites(refresh: true),
      onLoad: () async {
        _page++;
        await _fetchFavorites(refresh: false);
        return _hasMore ? IndicatorResult.success : IndicatorResult.noMore;
      },
      child: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : _statuses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star_border_rounded,
                          size: 54, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text(
                        '暂无收藏内容',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _statuses.length,
                  itemBuilder: (context, index) {
                    return TweetCard(
                      status: _statuses[index],
                      isDetail: false,
                    );
                  },
                ),
    );
  }
}
