import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/utils/weibo_text_parser.dart';
import '../../../core/utils/weibo_time_formatter.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../detail/presentation/status_detail_page.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../../feed/presentation/widgets/tweet_card.dart';

/// @我的 页面 (直连 /ajax/statuses/mentions 与 /ajax/comments/mentions)
class MentionsPage extends StatefulWidget {
  final int initialTabIndex;

  const MentionsPage({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<MentionsPage> createState() => _MentionsPageState();
}

class _MentionsPageState extends State<MentionsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('@我的', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
          tabs: const [
            Tab(text: '@我的微博'),
            Tab(text: '@我的评论'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _MentionsStatusesListView(),
          _MentionsCommentsListView(),
        ],
      ),
    );
  }
}

class _MentionsStatusesListView extends ConsumerStatefulWidget {
  const _MentionsStatusesListView();

  @override
  ConsumerState<_MentionsStatusesListView> createState() => _MentionsStatusesListViewState();
}

class _MentionsStatusesListViewState extends ConsumerState<_MentionsStatusesListView>
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
    _fetchMentions(refresh: true);
  }

  Future<void> _fetchMentions({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      setState(() => _isLoading = true);
    }

    final client = ref.read(weiboDioClientProvider);
    final extracted = <WeiboStatusModel>[];

    try {
      final res = await client.dio.get(
        '/ajax/statuses/mentions',
        queryParameters: {'page': _page},
      );
      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        final rawList = data['data']?['statuses'] as List? ??
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
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    return EasyRefresh(
      onRefresh: () => _fetchMentions(refresh: true),
      onLoad: () async {
        _page++;
        await _fetchMentions(refresh: false);
        return _hasMore ? IndicatorResult.success : IndicatorResult.noMore;
      },
      child: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : _statuses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.alternate_email_rounded,
                          size: 54, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text(
                        '暂无@你的微博',
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

class _MentionsCommentsListView extends ConsumerStatefulWidget {
  const _MentionsCommentsListView();

  @override
  ConsumerState<_MentionsCommentsListView> createState() => _MentionsCommentsListViewState();
}

class _MentionsCommentsListViewState extends ConsumerState<_MentionsCommentsListView>
    with AutomaticKeepAliveClientMixin {
  final List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  int _page = 1;
  bool _hasMore = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchComments(refresh: true);
  }

  Future<void> _fetchComments({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      setState(() => _isLoading = true);
    }

    final client = ref.read(weiboDioClientProvider);
    final extracted = <Map<String, dynamic>>[];

    try {
      final res = await client.dio.get(
        '/ajax/comments/mentions',
        queryParameters: {'page': _page},
      );
      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        final rawList = data['data']?['comments'] as List? ??
            data['comments'] as List? ??
            [];
        extracted.addAll(rawList.whereType<Map<String, dynamic>>());
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        if (refresh) {
          _comments.clear();
        }
        _comments.addAll(extracted);
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
      onRefresh: () => _fetchComments(refresh: true),
      onLoad: () async {
        _page++;
        await _fetchComments(refresh: false);
        return _hasMore ? IndicatorResult.success : IndicatorResult.noMore;
      },
      child: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : _comments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded,
                          size: 54, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text(
                        '暂无@你的评论',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _comments.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 64, thickness: 0.5),
                  itemBuilder: (context, index) {
                    final c = _comments[index];
                    final user = c['user'] is Map ? (c['user'] as Map<String, dynamic>) : {};
                    final text = c['text_raw']?.toString() ?? c['text']?.toString() ?? '';
                    final nick = user['screen_name']?.toString() ?? '微博用户';
                    final avatar = user['avatar_hd']?.toString() ??
                        user['profile_image_url']?.toString() ??
                        '';
                    final createdAt = c['created_at']?.toString() ?? '';

                    return ListTile(
                      leading: AppAvatar(url: avatar, size: 40, name: nick),
                      title: Text(nick, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (createdAt.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              WeiboTimeFormatter.format(rawDate: createdAt),
                              style: TextStyle(fontSize: 12, color: colorScheme.outline),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text.rich(
                            TextSpan(
                              children: WeiboTextParser.parse(
                                rawText: text,
                                context: context,
                                defaultStyle: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        final status = c['status'];
                        if (status is Map<String, dynamic>) {
                          final statusModel = WeiboStatusModel.fromJson(status);
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (ctx) => StatusDetailPage(status: statusModel)),
                          );
                        }
                      },
                    );
                  },
                ),
    );
  }
}
