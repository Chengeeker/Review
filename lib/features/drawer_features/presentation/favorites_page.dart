import 'package:dio/dio.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:review/core/design_system/components/review_frosted_app_bar.dart';
import 'package:review/core/widgets/review_refresh_header.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/utils/haptic_feedback_util.dart';
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

  List<WeiboStatusModel> _extractFavoriteStatuses(dynamic rawData) {
    if (rawData is! Map) return const [];
    final data = rawData;
    final innerData = data['data'];
    final rawList = (innerData is List)
        ? innerData
        : ((innerData is Map && innerData['statuses'] is List)
            ? innerData['statuses'] as List
            : (data['statuses'] as List? ?? []));
    final statuses = <WeiboStatusModel>[];
    for (final item in rawList) {
      if (item is Map) {
        final itemMap = Map<String, dynamic>.from(item);
        if (itemMap['status'] is Map) {
          statuses.add(
            WeiboStatusModel.fromJson(
              Map<String, dynamic>.from(itemMap['status'] as Map),
            ).copyWith(favorited: true),
          );
        } else if (itemMap['id'] != null || itemMap['text_raw'] != null) {
          statuses.add(
            WeiboStatusModel.fromJson(itemMap).copyWith(favorited: true),
          );
        }
      }
    }
    return statuses;
  }

  Future<List<WeiboStatusModel>> _requestFavorites(
      WeiboDioClient client, int page) async {
    // 1. Try desktop endpoint
    try {
      final res = await client.dio.get(
        '/ajax/favorites/all_fav',
        queryParameters: {'page': page},
      );
      final statuses = _extractFavoriteStatuses(res.data);
      if (statuses.isNotEmpty) return statuses;
    } catch (_) {}

    // 2. Fallback to mobile endpoint if desktop returned empty or failed
    try {
      final mRes = await client.dio.get(
        'https://m.weibo.cn/api/favorites/all_fav',
        queryParameters: {'page': page},
        options: Options(
          headers: {
            'Referer': 'https://m.weibo.cn/',
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
          },
          extra: {'weiboMobileLogin': true},
        ),
      );
      final mStatuses = _extractFavoriteStatuses(mRes.data);
      if (mStatuses.isNotEmpty) return mStatuses;
    } catch (_) {}

    return const [];
  }

  Future<void> _fetchFavorites() async {
    setState(() => _isLoading = true);
    final client = ref.read(weiboDioClientProvider);
    final statuses = await _requestFavorites(client, 1);
    if (mounted) {
      setState(() {
        _statuses.clear();
        _statuses.addAll(statuses);
        _page = 1;
        _hasMore = statuses.isNotEmpty;
        _isLoading = false;
      });
    }
  }

  Future<bool> _loadMore() async {
    if (!_hasMore) return false;
    final client = ref.read(weiboDioClientProvider);
    final nextPage = _page + 1;
    final statuses = await _requestFavorites(client, nextPage);
    if (mounted) {
      setState(() {
        _statuses.addAll(statuses);
        _page = nextPage;
        _hasMore = statuses.isNotEmpty;
      });
    }
    return statuses.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isLoggedIn = authState.isLoggedIn;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: ReviewFrostedAppBar(
        title: const Text(
          '我的收藏',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: !isLoggedIn
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.star_outline_rounded,
                    size: 60,
                    color: colorScheme.primary.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '登录后即可同步您收藏的微博',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
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
              header: reviewFrostedAppBarRefreshHeader,
              onRefresh: () => HapticFeedbackUtil.refresh(_fetchFavorites),
              onLoad: () async {
                final hasMore = await _loadMore();
                return hasMore
                    ? IndicatorResult.success
                    : IndicatorResult.noMore;
              },
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: colorScheme.primary,
                      ),
                    )
                  : _statuses.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.star_border_rounded,
                            size: 54,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '暂无收藏内容',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 14,
                            ),
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
