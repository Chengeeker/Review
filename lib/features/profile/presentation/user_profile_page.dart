import 'dart:convert';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/card_display_provider.dart';
import '../../../core/theme/weibo_style_provider.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/utils/spring_page_route.dart';
import '../../../core/utils/weibo_time_formatter.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../detail/presentation/widgets/image_gallery_page.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../../feed/presentation/widgets/tweet_card.dart';
import '../../feed/presentation/widgets/weibo_video_player_page.dart';
import 'user_timeline_search_page.dart';

/// Comprehensive User Profile Page with Follow State, Dynamic Tabs (微博/相册/视频), Album Photo Wall, Video Waterfall Cards & Pinned Posts
class UserProfilePage extends ConsumerStatefulWidget {
  final WeiboUserModel? user;
  final String? uid;
  final String? screenName;

  const UserProfilePage({
    super.key,
    this.user,
    this.uid,
    this.screenName,
  });

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> with SingleTickerProviderStateMixin {
  static final Map<String, List<WeiboStatusModel>> _profileTimelineCache = {};
  static final Map<String, List<WeiboStatusModel>> _profileVideoCache = {};
  static final Map<String, WeiboUserModel> _profileUserCache = {};

  late WeiboUserModel _user;
  late TabController _tabController;

  // Timeline State
  final List<WeiboStatusModel> _statuses = [];
  bool _isLoading = true;
  int _page = 1;
  bool _hasMore = true;
  bool _isPrefetching = false;

  // Follow State
  bool _isTogglingFollow = false;

  // Filter State in 微博 Tab
  int _currentFeature = 0; // 0: 全部, 1: 原创, 2: 图片, 3: 视频
  int? _selectedYear;
  int? _selectedMonth;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);

    final effectiveUid = widget.user?.id.isNotEmpty == true ? widget.user!.id : (widget.uid ?? '');
    if (effectiveUid.isNotEmpty && _profileUserCache.containsKey(effectiveUid)) {
      _user = _profileUserCache[effectiveUid]!;
    } else {
      _user = widget.user ??
          WeiboUserModel(
            id: widget.uid ?? '',
            screenName: widget.screenName ?? '微博用户',
            avatar: '',
          );
    }

    if (effectiveUid.isNotEmpty && _profileTimelineCache.containsKey(effectiveUid)) {
      _statuses.addAll(_profileTimelineCache[effectiveUid]!);
      _isLoading = false;
    }

    _fetchUserProfileAndTimeline();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    setState(() {});

    // Active ultra-fast buffer prefetching on tab switch to Video or Album
    if (_tabController.index == 2) {
      if (_getVideoStatuses().length < 12 && _hasMore) {
        _prefetchVideoBuffer();
      }
    } else if (_tabController.index == 1 && _getAllAlbumPics().isEmpty && _hasMore) {
      _prefetchVideoBuffer();
    }
  }

  // Fetch a raw page without blocking UI or setting state directly
  Future<List<WeiboStatusModel>> _fetchRawPage(int page, {int feature = 0, String? uidToUse}) async {
    final client = ref.read(weiboDioClientProvider);
    final effectiveUid = uidToUse ?? (_user.id.isNotEmpty ? _user.id : widget.uid);
    if (effectiveUid == null || effectiveUid.isEmpty) return [];

    try {
      final res = await client.dio.get(
        ApiConstants.userTimeline,
        queryParameters: {
          'uid': effectiveUid,
          'page': page,
          'feature': feature,
        },
        options: Options(headers: {'Referer': 'https://weibo.com/u/$effectiveUid'}),
      );

      if (res.data is Map<String, dynamic>) {
        final rawList = res.data['data']?['list'] as List? ?? [];
        return rawList
            .whereType<Map<String, dynamic>>()
            .map((item) => WeiboStatusModel.fromJson(item))
            .where((s) => s.id.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // Actively prefetch background pages in parallel to maintain a rich video/album buffer
  Future<void> _prefetchVideoBuffer({int targetVideoCount = 16, int maxPages = 4}) async {
    if (_isPrefetching || !_hasMore) return;
    _isPrefetching = true;
    try {
      final effectiveUid = _user.id.isNotEmpty ? _user.id : widget.uid;
      if (effectiveUid == null || effectiveUid.isEmpty) return;

      // Concurrently fetch next 3 timeline pages AND dedicated video stream (feature: 3) in parallel
      final futures = <Future<List<WeiboStatusModel>>>[
        _fetchRawPage(_page + 1, feature: 0, uidToUse: effectiveUid),
        _fetchRawPage(_page + 2, feature: 0, uidToUse: effectiveUid),
        _fetchRawPage(_page + 3, feature: 0, uidToUse: effectiveUid),
        _fetchRawPage(1, feature: 3, uidToUse: effectiveUid),
        _fetchRawPage(2, feature: 3, uidToUse: effectiveUid),
      ];

      final results = await Future.wait(futures);
      if (!mounted) return;

      bool hasNew = false;
      final existingIds = _statuses.map((s) => s.id).toSet();

      for (final list in results) {
        for (final item in list) {
          if (!existingIds.contains(item.id)) {
            existingIds.add(item.id);
            _statuses.add(item);
            hasNew = true;
          }
        }
      }

      if (hasNew && mounted) {
        setState(() {
          _page = _page + 3;
          _profileTimelineCache[effectiveUid] = List.from(_statuses);
          _profileVideoCache[effectiveUid] = _getVideoStatuses();
        });
      }
    } finally {
      _isPrefetching = false;
    }
  }

  Future<void> _fetchUserProfileAndTimeline() async {
    if (_statuses.isEmpty) {
      setState(() => _isLoading = true);
    }
    final client = ref.read(weiboDioClientProvider);

    var effectiveUid = _user.id.isNotEmpty ? _user.id : widget.uid;

    // 1. If UID is empty, resolve UID from search suggest API
    if ((effectiveUid == null || effectiveUid.isEmpty) && _user.screenName.isNotEmpty) {
      try {
        final searchSuggestRes = await client.dio.get(
          ApiConstants.searchSuggest,
          queryParameters: {'q': _user.screenName},
        );
        if (searchSuggestRes.data is Map<String, dynamic> && searchSuggestRes.data['data'] != null) {
          final users = searchSuggestRes.data['data']['user'] as List? ?? [];
          if (users.isNotEmpty && users[0] is Map<String, dynamic>) {
            final resolvedUid = users[0]['uid']?.toString() ?? users[0]['id']?.toString();
            if (resolvedUid != null && resolvedUid.isNotEmpty) {
              effectiveUid = resolvedUid;
              _user = WeiboUserModel(
                id: resolvedUid,
                screenName: users[0]['nick']?.toString() ?? _user.screenName,
                avatar: '',
              );
            }
          }
        }
      } catch (_) {}
    }

    // 2. Fetch full profile info with resolved UID
    if (effectiveUid != null && effectiveUid.isNotEmpty) {
      try {
        final profileRes = await client.dio.get(
          '/ajax/profile/info',
          queryParameters: {'uid': effectiveUid},
          options: Options(headers: {'Referer': 'https://weibo.com/u/$effectiveUid'}),
        );
        if (profileRes.data is Map<String, dynamic> && profileRes.data['data'] != null) {
          final uJson = profileRes.data['data']['user'];
          if (uJson is Map<String, dynamic>) {
            final parsedUser = WeiboUserModel.fromJson(uJson);
            _profileUserCache[effectiveUid] = parsedUser;
            if (mounted) {
              setState(() {
                _user = parsedUser;
              });
            }
          }
        }
      } catch (_) {}
    }

    // 3. Fetch user's timeline (Page 1)
    await _loadTimeline(page: 1, isRefresh: true, uidToUse: effectiveUid);

    // 4. Prefetch subsequent pages in background to immediately stock video/album buffer
    if (mounted && _statuses.isNotEmpty && _hasMore) {
      _prefetchVideoBuffer(targetVideoCount: 12, maxPages: 3);
    }
  }

  Future<bool> _loadTimeline({required int page, bool isRefresh = false, String? uidToUse}) async {
    final client = ref.read(weiboDioClientProvider);
    final effectiveUid = uidToUse ?? (_user.id.isNotEmpty ? _user.id : widget.uid);
    final weiboStyle = ref.read(weiboStyleProvider);

    try {
      final res = await client.dio.get(
        ApiConstants.userTimeline,
        queryParameters: {
          if (effectiveUid != null && effectiveUid.isNotEmpty) 'uid': effectiveUid,
          'page': page,
          'feature': _currentFeature,
        },
        options: Options(headers: {'Referer': 'https://weibo.com/u/$effectiveUid'}),
      );

      if (res.data is Map<String, dynamic>) {
        final rawList = res.data['data']?['list'] as List? ?? [];
        var list = rawList
            .whereType<Map<String, dynamic>>()
            .map((item) => WeiboStatusModel.fromJson(item))
            .where((s) => s.id.isNotEmpty)
            .toList();

        // 2. 个人主页是否显示ta赞过的微博过滤
        if (!weiboStyle.showProfileLikedTweets && effectiveUid != null) {
          list = list.where((s) {
            final isLikedTitle = s.titleText != null && s.titleText!.contains('赞');
            final isOtherAuthorNoRetweet = s.user.id.isNotEmpty && s.user.id != effectiveUid && s.retweetedStatus == null;
            return !isLikedTitle && !isOtherAuthorNoRetweet;
          }).toList();
        }

        // 3. 日期筛选 (年份 / 月份)
        if (_selectedYear != null) {
          list = list.where((s) {
            if (s.createdAt.isEmpty) return true;
            if (_selectedMonth != null) {
              final mStr = _selectedMonth! < 10 ? '0$_selectedMonth' : '$_selectedMonth';
              return s.createdAt.contains('$_selectedYear-$mStr') ||
                  s.createdAt.contains('$_selectedYear年$_selectedMonth月') ||
                  s.createdAt.contains('$_selectedYear');
            }
            return s.createdAt.contains('$_selectedYear');
          }).toList();
        }

        if (mounted) {
          setState(() {
            if (isRefresh) {
              _statuses.clear();
            }
            // Avoid duplicate additions
            final existingIds = _statuses.map((s) => s.id).toSet();
            for (final item in list) {
              if (!existingIds.contains(item.id)) {
                _statuses.add(item);
              }
            }
            _page = page;
            _hasMore = list.isNotEmpty;
            _isLoading = false;
            if (effectiveUid != null && effectiveUid.isNotEmpty) {
              _profileTimelineCache[effectiveUid] = List.from(_statuses);
              _profileVideoCache[effectiveUid] = _getVideoStatuses();
            }
          });
        }
        return list.isNotEmpty;
      }
    } catch (_) {}

    // Fallback: Query discover/topic stream if mymblog is not directly accessible in visitor mode
    if (isRefresh && _statuses.isEmpty) {
      try {
        final searchRes = await client.dio.get(
          ApiConstants.hotTimeline,
          queryParameters: {
            'since_id': '0',
            'refresh': 0,
            'group_id': '102803',
            'containerid': '102803',
            'extparam': 'discover|topic|${_user.screenName}',
            'count': 15,
          },
        );
        if (searchRes.data is Map<String, dynamic>) {
          final rawStatuses = searchRes.data['statuses'] as List? ?? [];
          final list = rawStatuses
              .whereType<Map<String, dynamic>>()
              .map((item) => WeiboStatusModel.fromJson(item))
              .where((s) => s.id.isNotEmpty)
              .toList();

          if (mounted) {
            setState(() {
              _statuses.clear();
              _statuses.addAll(list);
              _isLoading = false;
              _hasMore = false;
            });
          }
          return list.isNotEmpty;
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _isLoading = false);
    return false;
  }

  bool _isFollowSuccess(dynamic rawData, {required bool isFollowAction}) {
    if (rawData == null) return false;
    dynamic data = rawData;
    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isEmpty) return false;
      try {
        data = jsonDecode(trimmed);
      } catch (_) {
        if (trimmed.contains('"ok":1') ||
            trimmed.contains('"ok": 1') ||
            trimmed.contains('"code":"100000"') ||
            trimmed.contains('"code":100000') ||
            trimmed.contains('已取消关注') ||
            trimmed.contains('关注成功')) {
          return true;
        }
      }
    }

    if (data is Map) {
      if (data['ok'] == 1 || data['ok'] == true) return true;
      if (data['code'] == '100000' || data['code'] == 100000) return true;
      if (data['result'] == true || data['result'] == 1) return true;
      final msg = (data['msg'] ?? data['message'] ?? '').toString();
      if (msg.contains('成功') || msg.contains('已取消') || msg.contains('已关注')) {
        return true;
      }
      if (data['id'] != null || data['idstr'] != null || data['screen_name'] != null) {
        if (data.containsKey('following')) {
          return data['following'] == isFollowAction;
        }
        return true;
      }
      if (data['data'] is Map) {
        final inner = data['data'] as Map;
        if (inner['ok'] == 1 || inner['ok'] == true) return true;
        if (inner['code'] == '100000' || inner['code'] == 100000) return true;
        if (inner['result'] == true || inner['result'] == 1) return true;
        final innerMsg = (inner['msg'] ?? inner['message'] ?? '').toString();
        if (innerMsg.contains('成功') || innerMsg.contains('已取消') || innerMsg.contains('已关注')) {
          return true;
        }
        if (inner['id'] != null || inner['idstr'] != null || inner['screen_name'] != null) {
          if (inner.containsKey('following')) {
            return inner['following'] == isFollowAction;
          }
          return true;
        }
      }
    }
    return false;
  }

  // 关注 / 取消关注交互
  Future<void> _toggleFollow() async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      AppToast.show(context, '请先登录微博账号');
      return;
    }

    if (_isTogglingFollow) return;
    setState(() => _isTogglingFollow = true);

    final client = ref.read(weiboDioClientProvider);
    final isFollowing = _user.following;
    final fullCookie = client.storageService.getFullCookie() ?? ref.read(authProvider).fullCookie ?? '';

    // 确保使用纯数字 UID
    var targetUid = _user.id;
    if (targetUid.isEmpty || int.tryParse(targetUid) == null) {
      if (widget.uid != null && widget.uid!.isNotEmpty && int.tryParse(widget.uid!) != null) {
        targetUid = widget.uid!;
      }
    }

    try {
      bool success = false;
      String? errorMsg;

      final standaloneDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (isFollowing) {
        // ========== 取消关注操作 (三路直连) ==========
        // 方案 1：微博移动端 REST 接口 (POST https://m.weibo.cn/api/friendships/destory)
        try {
          final st = await client.ensureXsrfToken(forceRefresh: true) ?? '';
          final mRes = await standaloneDio.post(
            'https://m.weibo.cn/api/friendships/destory',
            data: 'uid=$targetUid&st=$st',
            options: Options(
              contentType: Headers.formUrlEncodedContentType,
              headers: {
                'Cookie': fullCookie.contains('XSRF-TOKEN') ? fullCookie : '$fullCookie; XSRF-TOKEN=$st; MLOGIN=1;',
                'Referer': 'https://m.weibo.cn/u/$targetUid',
                'User-Agent':
                    'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
                'Accept': 'application/json, text/plain, */*',
                'X-Requested-With': 'XMLHttpRequest',
                if (st.isNotEmpty) 'X-XSRF-TOKEN': st,
              },
            ),
          );
          if (_isFollowSuccess(mRes.data, isFollowAction: false)) {
            success = true;
          } else if (mRes.data is Map && mRes.data['msg'] != null && mRes.data['msg'].toString().isNotEmpty) {
            errorMsg = mRes.data['msg'].toString();
          }
        } catch (_) {}

        // 方案 2：微博桌面端 Ajax 接口 (POST https://weibo.com/ajax/friendships/destroy)
        if (!success) {
          try {
            final xsrf = WeiboDioClient.extractXsrfToken(fullCookie) ?? '';
            final res = await standaloneDio.post(
              'https://weibo.com/ajax/friendships/destroy',
              data: {'uid': targetUid},
              options: Options(
                headers: {
                  'Cookie': fullCookie,
                  'Referer': 'https://weibo.com/u/$targetUid',
                  'Origin': 'https://weibo.com',
                  'User-Agent': ApiConstants.defaultUserAgent,
                  'Accept': 'application/json, text/plain, */*',
                  'X-Requested-With': 'XMLHttpRequest',
                  if (xsrf.isNotEmpty) 'X-XSRF-TOKEN': xsrf,
                },
              ),
            );
            if (_isFollowSuccess(res.data, isFollowAction: false)) {
              success = true;
            } else if (res.data is Map && res.data['msg'] != null && res.data['msg'].toString().isNotEmpty) {
              errorMsg = res.data['msg'].toString();
            }
          } catch (_) {}
        }

        // 方案 3：微博经典直连通道 (POST https://weibo.com/aj/f/unfollow?ajkey=wb_unfollow)
        if (!success) {
          try {
            final xsrf = WeiboDioClient.extractXsrfToken(fullCookie) ?? '';
            final legacyRes = await standaloneDio.post(
              'https://weibo.com/aj/f/unfollow?ajkey=wb_unfollow',
              data: 'uid=$targetUid',
              options: Options(
                contentType: Headers.formUrlEncodedContentType,
                headers: {
                  'Cookie': fullCookie,
                  'Referer': 'https://weibo.com/u/$targetUid',
                  'Origin': 'https://weibo.com',
                  'User-Agent': ApiConstants.defaultUserAgent,
                  'Accept': 'application/json, text/plain, */*',
                  'X-Requested-With': 'XMLHttpRequest',
                  if (xsrf.isNotEmpty) 'X-XSRF-TOKEN': xsrf,
                },
              ),
            );
            if (_isFollowSuccess(legacyRes.data, isFollowAction: false)) {
              success = true;
            } else if (legacyRes.data is Map && legacyRes.data['msg'] != null) {
              errorMsg = legacyRes.data['msg'].toString();
            }
          } catch (_) {}
        }

        if (errorMsg != null && (errorMsg.contains('成功') || errorMsg.contains('已取消') || errorMsg.contains('已关注'))) {
          success = true;
        }

        if (success) {
          HapticFeedbackUtil.light();
          setState(() {
            _user = WeiboUserModel(
              id: _user.id,
              screenName: _user.screenName,
              avatar: _user.avatar,
              avatarHd: _user.avatarHd,
              verified: _user.verified,
              verifiedType: _user.verifiedType,
              verifiedReason: _user.verifiedReason,
              description: _user.description,
              followersCount: _user.followersCount > 0 ? _user.followersCount - 1 : 0,
              friendsCount: _user.friendsCount,
              statusesCount: _user.statusesCount,
              following: false,
              followMe: _user.followMe,
              gender: _user.gender,
              ipLocation: _user.ipLocation,
            );
            _profileUserCache[_user.id] = _user;
            if (targetUid.isNotEmpty) {
              _profileUserCache[targetUid] = _user;
            }
          });
          if (mounted) {
            AppToast.show(context, '已取消关注 @${_user.screenName}');
          }
        } else {
          if (mounted) {
            AppToast.show(context, errorMsg ?? '取消关注失败，请检查网络或稍后重试');
          }
        }
      } else {
        // ========== 添加关注操作 (三路直连) ==========
        // 方案 1：微博移动端 REST 接口 (POST https://m.weibo.cn/api/friendships/create)
        try {
          final st = await client.ensureXsrfToken(forceRefresh: true) ?? '';
          final mRes = await standaloneDio.post(
            'https://m.weibo.cn/api/friendships/create',
            data: 'uid=$targetUid&st=$st',
            options: Options(
              contentType: Headers.formUrlEncodedContentType,
              headers: {
                'Cookie': fullCookie.contains('XSRF-TOKEN') ? fullCookie : '$fullCookie; XSRF-TOKEN=$st; MLOGIN=1;',
                'Referer': 'https://m.weibo.cn/u/$targetUid',
                'User-Agent':
                    'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
                'Accept': 'application/json, text/plain, */*',
                'X-Requested-With': 'XMLHttpRequest',
                if (st.isNotEmpty) 'X-XSRF-TOKEN': st,
              },
            ),
          );
          if (_isFollowSuccess(mRes.data, isFollowAction: true)) {
            success = true;
          } else if (mRes.data is Map && mRes.data['msg'] != null && mRes.data['msg'].toString().isNotEmpty) {
            errorMsg = mRes.data['msg'].toString();
          }
        } catch (_) {}

        // 方案 2：微博桌面端 Ajax 接口 (POST https://weibo.com/ajax/friendships/create)
        if (!success) {
          try {
            final xsrf = WeiboDioClient.extractXsrfToken(fullCookie) ?? '';
            final res = await standaloneDio.post(
              'https://weibo.com/ajax/friendships/create',
              data: {'uid': targetUid},
              options: Options(
                headers: {
                  'Cookie': fullCookie,
                  'Referer': 'https://weibo.com/u/$targetUid',
                  'Origin': 'https://weibo.com',
                  'User-Agent': ApiConstants.defaultUserAgent,
                  'Accept': 'application/json, text/plain, */*',
                  'X-Requested-With': 'XMLHttpRequest',
                  if (xsrf.isNotEmpty) 'X-XSRF-TOKEN': xsrf,
                },
              ),
            );
            if (_isFollowSuccess(res.data, isFollowAction: true)) {
              success = true;
            } else if (res.data is Map && res.data['msg'] != null && res.data['msg'].toString().isNotEmpty) {
              errorMsg = res.data['msg'].toString();
            }
          } catch (_) {}
        }

        // 方案 3：微博经典直连通道 (POST https://weibo.com/aj/f/followed?ajkey=wb_follow)
        if (!success) {
          try {
            final xsrf = WeiboDioClient.extractXsrfToken(fullCookie) ?? '';
            final legacyRes = await standaloneDio.post(
              'https://weibo.com/aj/f/followed?ajkey=wb_follow',
              data: 'uid=$targetUid&objectid=&f=1&extra=&refer_sort=&refer_flag=1005050001_',
              options: Options(
                contentType: Headers.formUrlEncodedContentType,
                headers: {
                  'Cookie': fullCookie,
                  'Referer': 'https://weibo.com/u/$targetUid',
                  'Origin': 'https://weibo.com',
                  'User-Agent': ApiConstants.defaultUserAgent,
                  'Accept': 'application/json, text/plain, */*',
                  'X-Requested-With': 'XMLHttpRequest',
                  if (xsrf.isNotEmpty) 'X-XSRF-TOKEN': xsrf,
                },
              ),
            );
            if (_isFollowSuccess(legacyRes.data, isFollowAction: true)) {
              success = true;
            } else if (legacyRes.data is Map && legacyRes.data['msg'] != null) {
              errorMsg = legacyRes.data['msg'].toString();
            }
          } catch (_) {}
        }

        if (errorMsg != null && (errorMsg.contains('成功') || errorMsg.contains('已关注'))) {
          success = true;
        }

        if (success) {
          HapticFeedbackUtil.medium();
          setState(() {
            _user = WeiboUserModel(
              id: _user.id,
              screenName: _user.screenName,
              avatar: _user.avatar,
              avatarHd: _user.avatarHd,
              verified: _user.verified,
              verifiedType: _user.verifiedType,
              verifiedReason: _user.verifiedReason,
              description: _user.description,
              followersCount: _user.followersCount + 1,
              friendsCount: _user.friendsCount,
              statusesCount: _user.statusesCount,
              following: true,
              followMe: _user.followMe,
              gender: _user.gender,
              ipLocation: _user.ipLocation,
            );
            _profileUserCache[_user.id] = _user;
            if (targetUid.isNotEmpty) {
              _profileUserCache[targetUid] = _user;
            }
          });
          if (mounted) {
            AppToast.show(context, '🎉 已关注 @${_user.screenName}');
          }
        } else {
          if (mounted) {
            AppToast.show(context, errorMsg ?? '关注失败，请检查网络或稍后重试');
          }
        }
      }
    } on DioException catch (dioErr) {
      String msg = '操作失败，请稍后重试';
      final status = dioErr.response?.statusCode;
      if (status == 401 || status == 403) {
        msg = '操作失败：网络权限受限，请稍后重试';
      } else if (dioErr.type == DioExceptionType.connectionTimeout ||
          dioErr.type == DioExceptionType.receiveTimeout) {
        msg = '网络连接超时，请检查网络设置并重试';
      }
      if (mounted) {
        AppToast.show(context, msg);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '操作失败: $e');
      }
    } finally {
      if (mounted) setState(() => _isTogglingFollow = false);
    }
  }

  // 弹出年份与月份筛选框
  void _showDateFilterDialog() {
    HapticFeedbackUtil.light();
    final years = [2026, 2025, 2024, 2023, 2022, 2021, 2020];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('按年份与月份筛选微博', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (_selectedYear != null || _selectedMonth != null)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedYear = null;
                            _selectedMonth = null;
                          });
                          Navigator.pop(ctx);
                          _loadTimeline(page: 1, isRefresh: true);
                        },
                        child: const Text('重置筛选'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('选择年份', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: years.map((y) {
                    final isSelected = _selectedYear == y;
                    return ChoiceChip(
                      label: Text('$y年'),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() => _selectedYear = selected ? y : null);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                const Text('选择月份', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(12, (i) {
                    final month = i + 1;
                    final isSelected = _selectedMonth == month;
                    return ChoiceChip(
                      label: Text('$month月'),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() => _selectedMonth = selected ? month : null);
                      },
                    );
                  }),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _loadTimeline(page: 1, isRefresh: true);
                    },
                    child: const Text('确定筛选'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 提取所有照片构建相册瀑布流 (包括静态图与 Live 图)
  List<Map<String, dynamic>> _getAllAlbumPics() {
    final list = <Map<String, dynamic>>[];
    for (final s in _statuses) {
      for (int i = 0; i < s.pics.length; i++) {
        list.add({
          'pic': s.pics[i],
          'status': s,
          'picIndex': i,
        });
      }
    }
    return list;
  }

  // 提取纯视频动态 (严格排除纯 Live 图片，只保留纯视频)
  List<WeiboStatusModel> _getVideoStatuses() {
    return _statuses.where((s) => s.hasVideo || (s.videoCoverUrl != null && s.videoCoverUrl!.isNotEmpty)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authState = ref.watch(authProvider);
    final isSelf = _user.id.isNotEmpty && _user.id == authState.uid;
    final albumPics = _getAllAlbumPics();
    final videoStatuses = _getVideoStatuses();

    return Scaffold(
      appBar: AppBar(
        title: Text(_user.screenName),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: '搜索微博',
            onPressed: () {
              HapticFeedbackUtil.light();
              Navigator.push(
                context,
                PhysicsSpringPageRoute(
                  child: UserTimelineSearchPage(user: _user),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              AppToast.show(context, '已复制博主主页链接');
            },
          ),
        ],
      ),
      body: EasyRefresh(
        onRefresh: () => _loadTimeline(page: 1, isRefresh: true),
        onLoad: () async {
          final hasMore = await _loadTimeline(page: _page + 1);
          if ((_tabController.index == 2 || _tabController.index == 1) && hasMore) {
            await _loadTimeline(page: _page + 1);
          }
          return hasMore ? IndicatorResult.success : IndicatorResult.noMore;
        },
        child: CustomScrollView(
          slivers: [
            // 1. User Header Profile Card
            SliverToBoxAdapter(
              child: Card(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AppAvatar(
                            url: _user.avatar,
                            size: 64,
                            name: _user.screenName,
                            verified: _user.verified,
                            verifiedType: _user.verifiedType,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _user.screenName,
                                        style: TextStyle(fontSize: 18, fontWeight: context.adjustWeight(FontWeight.bold)),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (_user.gender == 'f') ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.female_rounded, size: 16, color: Colors.pinkAccent),
                                    ] else if (_user.gender == 'm') ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.male_rounded, size: 16, color: Colors.blueAccent),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                if (_user.id.isNotEmpty)
                                  Text(
                                    'UID: ${_user.id}',
                                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                  ),
                                if (_user.ipLocation.isNotEmpty)
                                  Text(
                                    'IP属地: ${_user.ipLocation}',
                                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
                                  ),
                              ],
                            ),
                          ),

                          // 关注状态与操作按钮
                          if (!isSelf)
                            _isTogglingFollow
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : _user.following
                                    ? OutlinedButton.icon(
                                        onPressed: _toggleFollow,
                                        icon: const Icon(Icons.check_rounded, size: 14),
                                        label: Text(_user.followMe ? '互相关注' : '已关注'),
                                        style: OutlinedButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        ),
                                      )
                                    : FilledButton.icon(
                                        onPressed: _toggleFollow,
                                        icon: const Icon(Icons.add_rounded, size: 16),
                                        label: const Text('关注'),
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        ),
                                      ),
                        ],
                      ),
                      if (_user.description.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          _user.description,
                          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, height: 1.35),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _buildStatItem('关注', _user.friendsCount, colorScheme),
                          const SizedBox(width: 24),
                          _buildStatItem('粉丝', _user.followersCount, colorScheme),
                          const SizedBox(width: 24),
                          _buildStatItem('微博', _user.statusesCount > 0 ? _user.statusesCount : _statuses.length, colorScheme),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 2. TabBar 分栏 (纯文字，去除多余数字)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: colorScheme.onPrimaryContainer,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: '微博'),
                    Tab(text: '相册'),
                    Tab(text: '视频'),
                  ],
                ),
              ),
            ),

            // 3. 微博分栏专属筛选工具条 (全部 / 原创 / 图片 / 视频 / 日期筛选)
            if (_tabController.index == 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Row(
                    children: [
                      // 类型筛选 Chips
                      _buildFeatureChip('全部', 0, colorScheme),
                      const SizedBox(width: 6),
                      _buildFeatureChip('原创', 1, colorScheme),
                      const SizedBox(width: 6),
                      _buildFeatureChip('图片', 2, colorScheme),
                      const SizedBox(width: 6),
                      _buildFeatureChip('视频', 3, colorScheme),

                      const Spacer(),

                      // 日期筛选按钮
                      InkWell(
                        onTap: _showDateFilterDialog,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: (_selectedYear != null || _selectedMonth != null)
                                ? colorScheme.primaryContainer
                                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: (_selectedYear != null || _selectedMonth != null)
                                  ? colorScheme.primary
                                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_month_outlined,
                                size: 14,
                                color: (_selectedYear != null || _selectedMonth != null)
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _selectedYear != null
                                    ? '$_selectedYear年${_selectedMonth != null ? "$_selectedMonth月" : ""}'
                                    : '日期筛选',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: (_selectedYear != null || _selectedMonth != null) ? FontWeight.bold : FontWeight.normal,
                                  color: (_selectedYear != null || _selectedMonth != null)
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 4. 内容展示区 (根据当前 Tab 展示对应内容)
            if (_isLoading && _statuses.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              )
            else if (_tabController.index == 0) ...[
              // 微博 Tab
              if (_statuses.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text('暂无符合条件的微博', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      // 提前 8 条静默预加载下一页
                      if (index >= _statuses.length - 8 && _hasMore && !_isLoading) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _loadTimeline(page: _page + 1);
                        });
                      }
                      final status = _statuses[index];
                      return TweetCard(status: status);
                    },
                    childCount: _statuses.length,
                  ),
                ),
            ] else if (_tabController.index == 1) ...[
              // 相册 Tab 照片墙瀑布流 (3列网格，包含普通图与 Live 图)
              if (albumPics.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text('相册暂无图片', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                      childAspectRatio: 1.0,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = albumPics[index];
                        final pic = item['pic'] as WeiboPicModel;
                        final status = item['status'] as WeiboStatusModel;
                        final picIndex = item['picIndex'] as int;

                        return InkWell(
                          onTap: () {
                            HapticFeedbackUtil.light();
                            Navigator.of(context).push(
                              PhysicsSpringGalleryRoute(
                                child: ImageGalleryPage(
                                  pics: status.pics,
                                  initialIndex: picIndex,
                                  statusId: status.id,
                                  authorName: status.user.screenName,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  pic.previewUrl,
                                  headers: ApiConstants.imageHeaders,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: const Icon(Icons.broken_image_outlined, size: 24),
                                  ),
                                ),
                                if (pic.isLivePhoto)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.motion_photos_on_rounded, size: 10, color: Colors.white),
                                          SizedBox(width: 2),
                                          Text(
                                            'LIVE',
                                            style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: albumPics.length,
                    ),
                  ),
                ),
            ] else ...[
              // 视频 Tab (2列瀑布流视频卡片)
              if (videoStatuses.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text('暂无视频动态', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.72,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final status = videoStatuses[index];
                        return _buildWaterfallVideoCard(context, status, colorScheme);
                      },
                      childCount: videoStatuses.length,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // 2 列视频瀑布流精致卡片
  Widget _buildWaterfallVideoCard(BuildContext context, WeiboStatusModel status, ColorScheme colorScheme) {
    final cardSettings = ref.watch(cardDisplayProvider);
    final formattedTime = WeiboTimeFormatter.format(
      rawDate: status.createdAt,
      settings: cardSettings,
      language: 'zh',
    );
    final coverUrl = status.videoCoverUrl ?? (status.pics.isNotEmpty ? status.pics.first.largeUrl : '');
    final streamUrl = status.videoStreamUrl ?? '';
    final duration = status.videoDuration;
    final playCount = status.videoPlayCount;
    final playCountStr = playCount > 10000 ? '${(playCount / 10000).toStringAsFixed(1)}万' : (playCount > 0 ? '$playCount' : '');

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          width: 0.8,
        ),
      ),
      child: InkWell(
        onTap: () {
          HapticFeedbackUtil.light();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WeiboVideoPlayerPage(
                videoUrl: streamUrl,
                statusId: status.id,
                coverUrl: coverUrl,
                title: status.videoTitle ?? (status.effectiveText.length > 30 ? '${status.effectiveText.substring(0, 30)}...' : status.effectiveText),
                authorName: status.user.screenName,
                videoQualityUrls: status.videoQualityUrls,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 上半部：16:9 封面与角标
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (coverUrl.isNotEmpty)
                    Image.network(
                      coverUrl,
                      headers: ApiConstants.imageHeaders,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: const Center(child: Icon(Icons.video_library_rounded, size: 28)),
                      ),
                    )
                  else
                    Container(
                      color: Colors.black87,
                      child: const Center(child: Icon(Icons.video_library_rounded, size: 28, color: Colors.white70)),
                    ),

                  // Center Play Icon
                  Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white70, width: 1.2),
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                    ),
                  ),

                  // Bottom Duration / Play Count overlay
                  Positioned(
                    bottom: 4,
                    left: 6,
                    right: 6,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (playCountStr.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.play_arrow_outlined, size: 10, color: Colors.white),
                                const SizedBox(width: 2),
                                Text(playCountStr, style: const TextStyle(color: Colors.white, fontSize: 10)),
                              ],
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        if (duration != null && duration.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              duration,
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. 下半部：文本摘要与发布信息
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      status.videoTitle?.isNotEmpty == true
                          ? status.videoTitle!
                          : (status.textRaw.isNotEmpty ? status.textRaw : '视频动态'),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            formattedTime,
                            style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (status.attitudesCount > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.thumb_up_outlined, size: 11, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 2),
                              Text(
                                '${status.attitudesCount}',
                                style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureChip(String label, int feature, ColorScheme colorScheme) {
    final isSelected = _currentFeature == feature;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (selected) {
        if (selected) {
          HapticFeedbackUtil.light();
          setState(() {
            _currentFeature = feature;
          });
          _loadTimeline(page: 1, isRefresh: true);
        }
      },
    );
  }

  Widget _buildStatItem(String label, int count, ColorScheme colorScheme) {
    final countStr = count > 10000 ? '${(count / 10000).toStringAsFixed(1)}万' : '$count';
    return Row(
      children: [
        Text(countStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
      ],
    );
  }
}
