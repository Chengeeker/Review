import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../auth/presentation/login_page.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../../feed/presentation/widgets/tweet_card.dart';

/// 微博收藏大厅 (直连 /ajax/favorites/all_fav)
class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  final List<WeiboStatusModel> _statuses = [];
  bool _isLoading = true;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchFavorites();
  }

  Future<void> _fetchFavorites() async {
    setState(() => _isLoading = true);
    final client = ref.read(weiboDioClientProvider);
    try {
      final res = await client.dio.get(
        '/ajax/favorites/all_fav',
        queryParameters: {'page': 1},
      );
      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        final rawList = data['data'] as List? ?? data['statuses'] as List? ?? [];
        final statuses = <WeiboStatusModel>[];
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            if (item['status'] is Map<String, dynamic>) {
              statuses.add(WeiboStatusModel.fromJson(item['status'] as Map<String, dynamic>).copyWith(favorited: true));
            } else if (item['id'] != null || item['text_raw'] != null) {
              statuses.add(WeiboStatusModel.fromJson(item).copyWith(favorited: true));
            }
          }
        }
        if (mounted) {
          setState(() {
            _statuses.clear();
            _statuses.addAll(statuses);
            _page = 1;
            _hasMore = statuses.isNotEmpty;
            _isLoading = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<bool> _loadMore() async {
    if (!_hasMore) return false;
    final client = ref.read(weiboDioClientProvider);
    final nextPage = _page + 1;
    try {
      final res = await client.dio.get(
        '/ajax/favorites/all_fav',
        queryParameters: {'page': nextPage},
      );
      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        final rawList = data['data'] as List? ?? data['statuses'] as List? ?? [];
        final statuses = <WeiboStatusModel>[];
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            if (item['status'] is Map<String, dynamic>) {
              statuses.add(WeiboStatusModel.fromJson(item['status'] as Map<String, dynamic>).copyWith(favorited: true));
            } else if (item['id'] != null || item['text_raw'] != null) {
              statuses.add(WeiboStatusModel.fromJson(item).copyWith(favorited: true));
            }
          }
        }
        if (mounted) {
          setState(() {
            _statuses.addAll(statuses);
            _page = nextPage;
            _hasMore = statuses.isNotEmpty;
          });
        }
        return statuses.isNotEmpty;
      }
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isLoggedIn = authState.isLoggedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: !isLoggedIn
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_outline_rounded, size: 60, color: colorScheme.primary.withValues(alpha: 0.6)),
                  const SizedBox(height: 16),
                  const Text('登录后即可同步您收藏的微博', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
          : EasyRefresh(
              onRefresh: _fetchFavorites,
              onLoad: () async {
                final hasMore = await _loadMore();
                return hasMore ? IndicatorResult.success : IndicatorResult.noMore;
              },
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
                  : _statuses.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.star_border_rounded, size: 54, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
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
            ),
    );
  }
}
