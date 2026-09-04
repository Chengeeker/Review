import 'package:dio/dio.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../compose/presentation/compose_tweet_page.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../../feed/presentation/widgets/tweet_card.dart';
import '../../search/data/search_repository.dart';

/// 超话频道分栏模型
class ChaohuaChannel {
  final String title;
  final String flowId;
  final String? channelId;

  const ChaohuaChannel({
    required this.title,
    required this.flowId,
    this.channelId,
  });
}

/// 微博原生超话专属大厅页面 (支持动态自适应频道 Tab、实时签到、关注/取关与无限信息流)
class ChaohuaDetailPage extends ConsumerStatefulWidget {
  final String containerid;
  final String title;
  final String? avatar;
  final String? desc;
  final String? followCount;
  final int? statusCount;

  const ChaohuaDetailPage({
    super.key,
    required this.containerid,
    required this.title,
    this.avatar,
    this.desc,
    this.followCount,
    this.statusCount,
  });

  @override
  ConsumerState<ChaohuaDetailPage> createState() => _ChaohuaDetailPageState();
}

class _ChaohuaDetailPageState extends ConsumerState<ChaohuaDetailPage> with TickerProviderStateMixin {
  late String _currentContainerId;
  List<ChaohuaChannel> _channels = [];
  TabController? _tabController;

  // 每个频道的数据缓存
  final Map<String, List<WeiboStatusModel>> _channelStatuses = {};
  final Map<String, int> _channelPages = {};
  final Map<String, bool> _channelHasMore = {};
  final Map<String, bool> _channelLoading = {};

  // 超话头部元数据
  String? _headerTitle;
  String? _headerAvatar;
  String? _headerDesc;
  String? _headerFollowCount;
  bool _isFollowed = true;
  String _followBtnText = '已关注';
  bool _isFollowingLoading = false;
  bool _isChecked = false;
  String _checkinBtnText = '签到';
  bool _isCheckingIn = false;

  @override
  void initState() {
    super.initState();
    _currentContainerId = widget.containerid;
    _headerTitle = widget.title;
    _headerAvatar = widget.avatar;
    _headerDesc = widget.desc;

    if (_currentContainerId.isEmpty ||
        _currentContainerId.contains('_-_') ||
        !_currentContainerId.startsWith('100808') ||
        _currentContainerId.length < 20) {
      _resolveAndLoad();
    } else {
      _initDefaultChannels();
      _fetchChaohuaHeader();
      _fetchFeedForChannel(_channels[0], refresh: true);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _resolveAndLoad() async {
    final cleanTitle = widget.title.replaceAll('[超话]', '').replaceAll('超话', '').trim();
    final searchRepo = ref.read(searchRepositoryProvider);
    final results = await searchRepo.searchChaohua(cleanTitle);

    if (results.isNotEmpty) {
      final match = results.first;
      _currentContainerId = match.pageId;
      if (mounted) {
        setState(() {
          _headerTitle = match.title;
          _headerAvatar = match.image.isNotEmpty ? match.image : _headerAvatar;
          _headerDesc = match.description.isNotEmpty ? match.description : _headerDesc;
        });
      }
    } else if (_currentContainerId.isEmpty) {
      _currentContainerId = '100808_-_$cleanTitle';
    }

    _initDefaultChannels();
    _fetchChaohuaHeader();
    _fetchFeedForChannel(_channels[0], refresh: true);
  }

  void _initDefaultChannels() {
    final cid = _currentContainerId;
    _channels = [
      ChaohuaChannel(title: '热门', flowId: '${cid}_-_recommend', channelId: 'recommend'),
      ChaohuaChannel(title: '最新', flowId: '${cid}_-_feed', channelId: 'feed'),
      ChaohuaChannel(title: '精华', flowId: '${cid}_-_soul', channelId: 'soul'),
    ];
    _updateTabController();
  }

  void _updateTabController([int initialIndex = 0]) {
    final oldIndex = _tabController?.index ?? initialIndex;
    _tabController?.dispose();
    _tabController = TabController(
      length: _channels.length,
      vsync: this,
      initialIndex: oldIndex.clamp(0, _channels.length - 1),
    );
    _tabController!.addListener(() {
      if (!_tabController!.indexIsChanging) {
        final currentChannel = _channels[_tabController!.index];
        if (_channelStatuses[currentChannel.flowId] == null) {
          _fetchFeedForChannel(currentChannel, refresh: true);
        }
      }
    });
  }

  Future<void> _fetchChaohuaHeader() async {
    final client = ref.read(weiboDioClientProvider);
    try {
      final res = await client.dio.get(
        '/ajax_proxy/chaohua/page/extend',
        queryParameters: {
          'page_id': _currentContainerId,
          'show_recommend': 1,
        },
        options: Options(headers: {
          'Referer': 'https://weibo.com/p/$_currentContainerId',
          'X-Requested-With': 'XMLHttpRequest',
        }),
      );
      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _isFollowed = data['is_followed'] == true;
            _followBtnText = data['follow_btn_text']?.toString() ?? (_isFollowed ? '已关注' : '关注');
            _isChecked = data['is_checked'] == true;
            _checkinBtnText = _isChecked ? '已签到' : '签到';
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchFeedForChannel(ChaohuaChannel channel, {bool refresh = false}) async {
    final flowId = channel.flowId;
    if (refresh) {
      _channelPages[flowId] = 1;
      _channelHasMore[flowId] = true;
      if (mounted) {
        setState(() => _channelLoading[flowId] = true);
      }
    }

    final page = _channelPages[flowId] ?? 1;
    final client = ref.read(weiboDioClientProvider);
    final nextStatuses = <WeiboStatusModel>[];

    try {
      final res = await client.dio.get(
        '/ajax_proxy/chaohua/page',
        queryParameters: {
          'containerid': flowId,
          'page': page,
        },
        options: Options(headers: {
          'Referer': 'https://weibo.com/p/$_currentContainerId',
          'X-Requested-With': 'XMLHttpRequest',
        }),
      );

      if (res.data is Map<String, dynamic>) {
        final json = res.data as Map<String, dynamic>;

        // 1. 动态更新频道分栏顶栏列表 (包含热门、最新、精华及所有特有子频道)
        if (json['channelInfo'] is Map<String, dynamic>) {
          final chInfo = json['channelInfo'] as Map<String, dynamic>;
          final rawChannels = chInfo['channels'] as List? ?? [];
          if (rawChannels.isNotEmpty) {
            final parsedChannels = <ChaohuaChannel>[];
            for (final c in rawChannels) {
              if (c is Map<String, dynamic>) {
                final title = c['title']?.toString() ?? '';
                final fId = c['flowId']?.toString() ?? '';
                final chId = c['channelId']?.toString();
                if (title.isNotEmpty && fId.isNotEmpty) {
                  parsedChannels.add(ChaohuaChannel(title: title, flowId: fId, channelId: chId));
                }
              }
            }
            if (parsedChannels.isNotEmpty &&
                (parsedChannels.length != _channels.length || parsedChannels[0].flowId != _channels[0].flowId)) {
              if (mounted) {
                final curIndex = _tabController?.index ?? 0;
                setState(() {
                  _channels = parsedChannels;
                  _updateTabController(curIndex);
                });
              }
            }
          }
        }

        // 2. 尝试从 header 中提取超话元数据
        if (json['header'] is Map<String, dynamic>) {
          final header = json['header'] as Map<String, dynamic>;
          final hData = header['data'] as Map<String, dynamic>?;
          if (hData != null) {
            _headerTitle ??= hData['nick']?.toString();
            _headerAvatar ??= hData['portrait']?.toString() ?? hData['avatar']?.toString();
            _headerDesc ??= hData['desc']?.toString();
            final fRel = hData['follow_relation'];
            if (fRel != null) {
              _isFollowed = fRel == 1;
              _followBtnText = _isFollowed ? '已关注' : '关注';
            }
          }
        }

        // 3. 提取信息流帖子列表
        final items = json['items'] as List? ?? [];
        for (final it in items) {
          if (it is Map) {
            if (it['category'] == 'feed' && it['data'] is Map) {
              try {
                final statusMap = Map<String, dynamic>.from(it['data'] as Map);
                final model = WeiboStatusModel.fromJson(statusMap);
                if (model.id.isNotEmpty) nextStatuses.add(model);
              } catch (_) {}
            } else if (it['data'] is Map && (it['data']['id'] != null || it['data']['text_raw'] != null || it['data']['text'] != null)) {
              try {
                final statusMap = Map<String, dynamic>.from(it['data'] as Map);
                final model = WeiboStatusModel.fromJson(statusMap);
                if (model.id.isNotEmpty) nextStatuses.add(model);
              } catch (_) {}
            }
          }
        }

        if (nextStatuses.isEmpty) {
          final rawStatuses = json['statuses'] as List? ?? json['data']?['statuses'] as List? ?? [];
          for (final s in rawStatuses) {
            if (s is Map) {
              try {
                final model = WeiboStatusModel.fromJson(Map<String, dynamic>.from(s));
                if (model.id.isNotEmpty) nextStatuses.add(model);
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        if (refresh) {
          _channelStatuses[flowId] = nextStatuses;
        } else {
          final existing = _channelStatuses[flowId] ?? [];
          final existingIds = existing.map((e) => e.id).toSet();
          final newUnique = nextStatuses.where((e) => !existingIds.contains(e.id)).toList();
          existing.addAll(newUnique);
          _channelStatuses[flowId] = existing;
        }
        _channelHasMore[flowId] = nextStatuses.isNotEmpty;
        _channelLoading[flowId] = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    if (_isFollowingLoading) return;
    final client = ref.read(weiboDioClientProvider);
    final endpoint = _isFollowed
        ? '/ajax_proxy/chaohua/page/unfollow'
        : '/ajax_proxy/chaohua/page/follow';

    setState(() => _isFollowingLoading = true);
    try {
      final res = await client.dio.post(
        endpoint,
        data: {'page_id': _currentContainerId},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Referer': 'https://weibo.com/p/$_currentContainerId',
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );

      final data = res.data is Map ? res.data as Map : {};
      final code = data['code'];

      if ((_isFollowed && code == 10000) || (!_isFollowed && (code == 100000 || code == 10000))) {
        setState(() {
          _isFollowed = !_isFollowed;
          _followBtnText = data['follow_btn_text']?.toString() ?? (_isFollowed ? '已关注' : '关注');
        });
        if (mounted) {
          AppToast.show(context, _isFollowed ? '已关注该超话' : '已取消关注');
        }
      } else {
        final msg = data['msg']?.toString() ?? '操作失败，请重试';
        if (mounted) {
          AppToast.show(context, msg);
        }
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, '网络请求失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        setState(() => _isFollowingLoading = false);
      }
    }
  }

  Future<void> _handleCheckin() async {
    if (_isCheckingIn || _isChecked) return;
    final client = ref.read(weiboDioClientProvider);
    setState(() => _isCheckingIn = true);

    try {
      final res = await client.dio.post(
        '/ajax_proxy/chaohua/page/checkin',
        data: {
          'scene_id': 'pc_checkin',
          'page_id': _currentContainerId,
          'timezone': 'Asia/Shanghai',
          'lang': 'zh-CN',
          'plat': 'Win32',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Referer': 'https://weibo.com/p/$_currentContainerId',
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );

      final data = res.data is Map ? res.data as Map : {};
      final code = data['code'];

      if (code == 100000 || code == 10000) {
        setState(() {
          _isChecked = true;
          _checkinBtnText = '已签到';
        });
        final checkinData = data['data'] as Map?;
        final rank = checkinData?['rank'];
        final score = checkinData?['score'];
        String msg = '🎉 签到成功！';
        if (rank != null) msg += ' 获得第 $rank 名';
        if (score != null) msg += '，经验值 +$score';

        if (mounted) {
          AppToast.show(context, msg);
        }
      } else {
        final msg = data['msg']?.toString() ?? '签到未成功，请稍后再试';
        if (mounted) {
          AppToast.show(context, msg);
        }
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, '签到网络异常，请重试');
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingIn = false);
      }
    }
  }

  void _navigateToCompose() {
    final title = _headerTitle ?? widget.title;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => ComposeTweetPage(initialText: '#$title[超话]# '),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayTitle = _headerTitle ?? widget.title;
    final displayAvatar = _headerAvatar ?? widget.avatar ?? '';
    final displayDesc = _headerDesc ?? widget.desc ?? '';

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            // 1. 顶部超话 AppBar
            SliverAppBar(
              pinned: true,
              expandedHeight: 0,
              elevation: 0,
              scrolledUnderElevation: 1.0,
              title: Text(
                displayTitle,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: '分享超话',
                  onPressed: () {
                    HapticFeedbackUtil.light();
                    AppToast.show(context, '超话：$displayTitle');
                  },
                ),
              ],
            ),

            // 2. 超话信息卡片 (头像、名称、简介、发帖、关注与签到三大核心操作)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: colorScheme.surfaceContainerHighest,
                              image: displayAvatar.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(displayAvatar),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: displayAvatar.isEmpty
                                ? const Icon(Icons.diamond_rounded, size: 28, color: Color(0xFFFF8200))
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.diamond_rounded, size: 18, color: Color(0xFFFF8200)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        displayTitle,
                                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_headerFollowCount != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _headerFollowCount!,
                                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),

                      if (displayDesc.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            displayDesc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),

                      const SizedBox(height: 12),

                      // 三大核心操作按钮：发帖 / 关注 / 签到
                      Row(
                        children: [
                          // 发帖
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _navigateToCompose,
                              icon: const Icon(Icons.edit_note_rounded, size: 18),
                              label: const Text('发帖', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 关注 / 取关
                          Expanded(
                            child: FilledButton.tonal(
                              onPressed: _toggleFollow,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isFollowingLoading
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(
                                      _followBtnText,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: _isFollowed ? colorScheme.onSecondaryContainer : colorScheme.primary,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 签到
                          Expanded(
                            child: FilledButton(
                              onPressed: _handleCheckin,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: _isChecked ? colorScheme.surfaceContainerHighest : colorScheme.primary,
                                foregroundColor: _isChecked ? colorScheme.onSurfaceVariant : colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isCheckingIn
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (_isChecked) const Icon(Icons.check_rounded, size: 16),
                                        if (_isChecked) const SizedBox(width: 2),
                                        Text(
                                          _checkinBtnText,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 3. 固定吸顶 TabBar (包含动态自适应频道分栏)
            if (_tabController != null)
              SliverPersistentHeader(
                pinned: true,
                delegate: _ChaohuaTabHeaderDelegate(
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14.5),
                    indicatorSize: TabBarIndicatorSize.label,
                    indicatorWeight: 3,
                    indicatorColor: colorScheme.primary,
                    labelColor: colorScheme.primary,
                    unselectedLabelColor: colorScheme.onSurfaceVariant,
                    tabs: _channels.map((ch) => Tab(text: ch.title)).toList(),
                  ),
                  colorScheme.surface,
                ),
              ),
          ];
        },
        body: _tabController == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: _channels.map((channel) {
                  final flowId = channel.flowId;
                  final statuses = _channelStatuses[flowId];
                  final isLoading = _channelLoading[flowId] ?? (statuses == null);
                  final hasMore = _channelHasMore[flowId] ?? true;

                  if (isLoading && statuses == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final list = statuses ?? [];

                  return EasyRefresh(
                    onRefresh: () => _fetchFeedForChannel(channel, refresh: true),
                    onLoad: () async {
                      final curPage = _channelPages[flowId] ?? 1;
                      _channelPages[flowId] = curPage + 1;
                      await _fetchFeedForChannel(channel, refresh: false);
                      return hasMore ? IndicatorResult.success : IndicatorResult.noMore;
                    },
                    child: list.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.feed_outlined, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                Text(
                                  '暂无【${channel.title}】相关动态',
                                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          )
                        : NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification.metrics.maxScrollExtent > 0) {
                                final progress = notification.metrics.pixels / notification.metrics.maxScrollExtent;
                                final remainingDistance = notification.metrics.maxScrollExtent - notification.metrics.pixels;
                                if (progress >= 0.55 || remainingDistance < 1200) {
                                  if (hasMore && !isLoading) {
                                    final curPage = _channelPages[flowId] ?? 1;
                                    _channelPages[flowId] = curPage + 1;
                                    _fetchFeedForChannel(channel, refresh: false);
                                  }
                                }
                              }
                              return false;
                            },
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 20),
                              itemCount: list.length,
                              itemBuilder: (context, index) {
                                return TweetCard(status: list[index]);
                              },
                            ),
                          ),
                  );
                }).toList(),
              ),
      ),
    );
  }
}

/// 固定吸顶 TabBar 委托
class _ChaohuaTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;

  _ChaohuaTabHeaderDelegate(this.tabBar, this.backgroundColor);

  @override
  double get minExtent => tabBar.preferredSize.height + 1;

  @override
  double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: backgroundColor,
      child: Column(
        children: [
          tabBar,
          const Divider(height: 1, thickness: 0.5),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ChaohuaTabHeaderDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar || oldDelegate.backgroundColor != backgroundColor;
  }
}
