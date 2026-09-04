import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../../feed/presentation/widgets/tweet_card.dart';

/// 微博原生群动态与群微博专区 (直连 /ajax/statuses/mymblog?uid={ownerUid}&feature=0)
class GroupWeiboPage extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;
  final String ownerUid;

  const GroupWeiboPage({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.ownerUid,
  });

  @override
  ConsumerState<GroupWeiboPage> createState() => _GroupWeiboPageState();
}

class _GroupWeiboPageState extends ConsumerState<GroupWeiboPage> {
  final List<WeiboStatusModel> _statuses = [];
  bool _isLoading = true;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchGroupTimeline(refresh: true);
  }

  Future<void> _fetchGroupTimeline({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      setState(() => _isLoading = true);
    }

    final client = ref.read(weiboDioClientProvider);
    final extracted = <WeiboStatusModel>[];

    try {
      final res = await client.dio.get(
        '/ajax/statuses/mymblog',
        queryParameters: {
          'uid': widget.ownerUid,
          'page': _page,
          'feature': 0,
        },
      );

      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        final rawList = data['data']?['list'] as List? ??
            data['data']?['statuses'] as List? ??
            data['list'] as List? ??
            data['statuses'] as List? ??
            [];
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            extracted.add(WeiboStatusModel.fromJson(item));
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('群微博', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            Text(
              widget.groupName,
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          ],
        ),
      ),
      body: EasyRefresh(
        onRefresh: () => _fetchGroupTimeline(refresh: true),
        onLoad: () async {
          _page++;
          await _fetchGroupTimeline(refresh: false);
          return _hasMore ? IndicatorResult.success : IndicatorResult.noMore;
        },
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
            : _statuses.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.feed_outlined,
                            size: 54,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(
                          '暂无群微博动态',
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
