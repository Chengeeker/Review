import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/storage/storage_service.dart';
import 'models/weibo_status_model.dart';

class WeiboGroupModel {
  final String gid;
  final String title;
  final String containerid;
  final int type;

  const WeiboGroupModel({
    required this.gid,
    required this.title,
    this.containerid = '',
    this.type = 0,
  });

  factory WeiboGroupModel.fromJson(Map<String, dynamic> json) {
    return WeiboGroupModel(
      gid: json['gid']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? json['name']?.toString() ?? '',
      containerid: json['containerid']?.toString() ?? '',
      type: json['type'] is int ? json['type'] as int : 0,
    );
  }
}

class TimelineResult {
  final List<WeiboStatusModel> statuses;
  final String maxId;
  final String sinceId;
  final bool hasMore;
  final String? error;

  const TimelineResult({
    required this.statuses,
    this.maxId = '0',
    this.sinceId = '0',
    this.hasMore = true,
    this.error,
  });
}

class UserGroupsResult {
  final List<WeiboGroupModel> defaultGroups;
  final List<WeiboGroupModel> personalGroups;
  final List<WeiboGroupModel> hotGroups;

  const UserGroupsResult({
    this.defaultGroups = const [],
    this.personalGroups = const [],
    this.hotGroups = const [],
  });
}

/// Repository for Fetching Pure Following (关注), Special Following (特别关注), Groups, and Hot Feeds
class FeedRepository {
  final WeiboDioClient _client;
  final StorageService _storage;

  FeedRepository(this._client, this._storage);

  /// Fetch user's custom groups from desktop allGroups endpoint (Structured)
  Future<UserGroupsResult> getUserGroups() async {
    final def = <WeiboGroupModel>[];
    final pers = <WeiboGroupModel>[];
    final hot = <WeiboGroupModel>[];

    try {
      final response = await _client.dio.get(
        '/ajax/feed/allGroups',
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/',
          },
        ),
      );
      if (response.data is Map<String, dynamic>) {
        final rawGroups = response.data['groups'] as List? ?? [];
        for (final item in rawGroups) {
          if (item is Map<String, dynamic>) {
            final title = item['title']?.toString() ?? '';
            final groupList = item['group'] as List? ?? [];
            for (final g in groupList) {
              if (g is Map<String, dynamic>) {
                final model = WeiboGroupModel.fromJson(g);
                if (model.gid.isNotEmpty && model.title.isNotEmpty) {
                  if (title == '我的分组') {
                    pers.add(model);
                  } else if (title == '默认分组') {
                    def.add(model);
                  } else if (title == '我的频道' || title == '频道推荐') {
                    hot.add(model);
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    return UserGroupsResult(
      defaultGroups: def,
      personalGroups: pers,
      hotGroups: hot,
    );
  }

  /// Fetch user's custom groups from desktop allGroups endpoint (Legacy compatible)
  Future<List<WeiboGroupModel>> getAllGroups() async {
    final res = await getUserGroups();
    return [...res.defaultGroups, ...res.personalGroups, ...res.hotGroups];
  }

  Future<TimelineResult> getTimeline({
    required String category,
    String? userUid,
    int page = 1,
    String maxId = '0',
    String sinceId = '0',
  }) async {
    // 1. Hot Public Categories (102803...)
    if (category.startsWith('102803') && !category.startsWith('102803_ctg1_-_ctg1_')) {
      return getHotTimeline(category: category, page: page, maxId: maxId, sinceId: sinceId);
    }

    // 2. Primary Followed Timeline (关注 / 全部关注 / friends / all_follow / 11000... / 10001...)
    if (category == 'friends' ||
        category == 'all_follow' ||
        category.startsWith('11000') ||
        category.startsWith('10001') ||
        category == '10001') {
      return getFriendsTimeline(page: page, maxId: maxId, sinceId: sinceId);
    }

    // 3. User Group (特别关注 4152890832681124, 自定义分组等)
    return getGroupsTimeline(gid: category, page: page, maxId: maxId, sinceId: sinceId);
  }

  /// 100% Pure Following Feed via /ajax/feed/friendstimeline with Dual-Engine Multi-Pathway Support
  Future<TimelineResult> getFriendsTimeline({
    int page = 1,
    String maxId = '0',
    String sinceId = '0',
  }) async {
    // 方案 1: 桌面端 Ajax 直连通道 (GET /ajax/feed/friendstimeline 带 list_id=10001 与 refresh 标识)
    try {
      final queryParams = <String, dynamic>{
        'list_id': '10001',
        'page': page,
        'count': 25,
      };
      if (page == 1 && (maxId == '0' || maxId.isEmpty)) {
        queryParams['refresh'] = 0;
      } else {
        queryParams['refresh'] = 4;
      }
      if (maxId != '0' && maxId.isNotEmpty) {
        queryParams['max_id'] = maxId;
      }

      final response = await _client.dio.get(
        '/ajax/feed/friendstimeline',
        queryParameters: queryParams,
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/',
            'Accept': 'application/json, text/plain, */*',
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final rawStatuses = data['statuses'] as List? ?? [];
        final statuses = <WeiboStatusModel>[];
        for (final item in rawStatuses) {
          if (item is Map<String, dynamic>) {
            try {
              final status = WeiboStatusModel.fromJson(item);
              if (status.id.isNotEmpty) statuses.add(status);
            } catch (_) {}
          }
        }

        if (statuses.isNotEmpty) {
          final nextMaxId = data['max_id'] != null && data['max_id'] != 0
              ? data['max_id'].toString()
              : (statuses.last.id.isNotEmpty ? statuses.last.id : maxId);

          return TimelineResult(
            statuses: statuses,
            maxId: nextMaxId,
            sinceId: data['since_id']?.toString() ?? '0',
            hasMore: true,
          );
        }
      }
    } catch (_) {}

    // 方案 2: 桌面未读加速通道 (GET /ajax/feed/unreadfriendstimeline) - 仅在首屏使用
    if (page == 1 && (maxId == '0' || maxId.isEmpty)) {
      try {
        final unreadRes = await _client.dio.get(
          '/ajax/feed/unreadfriendstimeline',
          queryParameters: {'count': 25},
          options: Options(
            headers: {
              'Referer': 'https://weibo.com/',
              'Accept': 'application/json, text/plain, */*',
              'X-Requested-With': 'XMLHttpRequest',
            },
          ),
        );
        if (unreadRes.data is Map<String, dynamic>) {
          final data = unreadRes.data as Map<String, dynamic>;
          final rawStatuses = data['statuses'] as List? ?? [];
          final statuses = <WeiboStatusModel>[];
          for (final item in rawStatuses) {
            if (item is Map<String, dynamic>) {
              try {
                final status = WeiboStatusModel.fromJson(item);
                if (status.id.isNotEmpty) statuses.add(status);
              } catch (_) {}
            }
          }
          if (statuses.isNotEmpty) {
            return TimelineResult(
              statuses: statuses,
              maxId: data['max_id']?.toString() ?? statuses.last.id,
              sinceId: data['since_id']?.toString() ?? '0',
              hasMore: true,
            );
          }
        }
      } catch (_) {}
    }

    // Fallback: If not logged in or in visitor mode, fallback to hot timeline
    final fullCookie = _storage.getFullCookie();
    if (fullCookie == null || fullCookie.isEmpty) {
      return getHotTimeline(category: '102803', page: page, maxId: maxId, sinceId: sinceId);
    }

    return const TimelineResult(statuses: [], hasMore: false);
  }

  Future<TimelineResult> getHotTimeline({
    String category = '102803',
    int page = 1,
    String maxId = '0',
    String sinceId = '0',
  }) async {
    try {
      final response = await _client.dio.get(
        ApiConstants.hotTimeline,
        queryParameters: {
          'page': page,
          'since_id': sinceId,
          'refresh': page == 1 && sinceId == '0' && maxId == '0' ? 0 : 3,
          'group_id': category,
          'containerid': category,
          'extparam': 'discover|new_feed',
          if (maxId != '0') 'max_id': maxId,
          'count': 15,
        },
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final rawStatuses = data['statuses'] as List? ?? [];
        final statuses = <WeiboStatusModel>[];
        for (final item in rawStatuses) {
          if (item is Map<String, dynamic>) {
            try {
              final status = WeiboStatusModel.fromJson(item);
              if (status.id.isNotEmpty) statuses.add(status);
            } catch (_) {}
          }
        }

        if (statuses.isNotEmpty) {
          final nextMaxId = data['max_id'] != null && data['max_id'] != 0
              ? data['max_id'].toString()
              : (statuses.last.id.isNotEmpty ? statuses.last.id : maxId);

          return TimelineResult(
            statuses: statuses,
            maxId: nextMaxId,
            sinceId: data['since_id']?.toString() ?? sinceId,
            hasMore: true,
          );
        }
      }
    } on DioException catch (dioErr) {
      final msg = (dioErr.type == DioExceptionType.connectionTimeout ||
              dioErr.type == DioExceptionType.receiveTimeout)
          ? '网络连接超时，请检查网络并下拉重试'
          : '网络连接异常，请检查网络设置并重试';
      return TimelineResult(statuses: const [], hasMore: false, error: msg);
    } catch (_) {}
    return const TimelineResult(statuses: [], hasMore: false);
  }

  /// Direct Weibo Group Timeline (特别关注, 互相关注, 自定义分组等) with Page & Refresh Pagination
  Future<TimelineResult> getGroupsTimeline({
    required String gid,
    int page = 1,
    String maxId = '0',
    String sinceId = '0',
  }) async {
    try {
      final response = await _client.dio.get(
        '/ajax/feed/groupstimeline',
        queryParameters: {
          'list_id': gid,
          'page': page,
          if (page == 1 && maxId == '0') 'refresh': 0,
          if (page > 1 || maxId != '0') 'refresh': 4,
          if (sinceId != '0') 'since_id': sinceId,
          if (maxId != '0') 'max_id': maxId,
          'count': 25,
        },
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/mygroups?gid=$gid',
          },
        ),
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final rawStatuses = data['statuses'] as List? ?? [];
        final statuses = <WeiboStatusModel>[];
        for (final item in rawStatuses) {
          if (item is Map<String, dynamic>) {
            try {
              final status = WeiboStatusModel.fromJson(item);
              if (status.id.isNotEmpty) statuses.add(status);
            } catch (_) {}
          }
        }

        if (statuses.isNotEmpty) {
          final nextMaxId = data['max_id'] != null && data['max_id'] != 0
              ? data['max_id'].toString()
              : (statuses.last.id.isNotEmpty ? statuses.last.id : maxId);

          return TimelineResult(
            statuses: statuses,
            maxId: nextMaxId,
            sinceId: data['since_id']?.toString() ?? sinceId,
            hasMore: true,
          );
        }
      }
    } on DioException catch (dioErr) {
      final msg = (dioErr.type == DioExceptionType.connectionTimeout ||
              dioErr.type == DioExceptionType.receiveTimeout)
          ? '网络连接超时，请检查网络并下拉重试'
          : '网络连接异常，请检查网络设置并重试';
      return TimelineResult(statuses: const [], hasMore: false, error: msg);
    } catch (_) {}

    return const TimelineResult(statuses: [], hasMore: false);
  }

  Future<bool> setLike(String mid) async {
    try {
      final res = await _client.dio.post(
        ApiConstants.setLike,
        data: {'id': mid},
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/',
          },
        ),
      );
      return res.data?['ok'] == 1 || res.data?['id'] != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelLike(String mid) async {
    try {
      final res = await _client.dio.post(
        ApiConstants.cancelLike,
        data: {'id': mid},
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/',
          },
        ),
      );
      return res.data?['ok'] == 1 || res.data?['result'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleLike(String mid, {required bool currentlyLiked}) async {
    if (currentlyLiked) {
      return cancelLike(mid);
    } else {
      return setLike(mid);
    }
  }

  Future<bool> createFavorite(String mid) async {
    try {
      final res = await _client.dio.post(
        ApiConstants.createFavorites,
        data: {'id': mid},
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/',
          },
        ),
      );
      return res.data?['ok'] == 1 || res.data?['status'] != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> destroyFavorite(String mid) async {
    try {
      final res = await _client.dio.post(
        ApiConstants.destroyFavorites,
        data: {'id': mid},
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/',
          },
        ),
      );
      return res.data?['ok'] == 1 || res.data?['status'] != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleFavorite(String mid, {required bool currentlyFavorited}) async {
    if (currentlyFavorited) {
      return destroyFavorite(mid);
    } else {
      return createFavorite(mid);
    }
  }

  /// Delete status by MID
  Future<bool> deleteTweet(String mid) async {
    try {
      final res = await _client.dio.post(
        '/ajax/statuses/destroy',
        data: {'id': mid},
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/',
          },
        ),
      );
      return res.data?['ok'] == 1 || res.data?['id'] != null;
    } catch (_) {
      return false;
    }
  }

  /// Unfollow user by UID (支持多路直连)
  Future<bool> unfollowUser(String uid) async {
    if (uid.isEmpty) return false;
    // 1. Desktop Ajax endpoint
    try {
      final res = await _client.dio.post(
        ApiConstants.destroyFollow,
        data: {'uid': uid},
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/u/$uid',
          },
        ),
      );
      if (res.data is Map) {
        final ok = res.data['ok'] == 1 || res.data['result'] == true || res.data['status'] == 1;
        if (ok) return true;
      }
    } catch (_) {}

    // 2. Mobile REST fallback
    try {
      final res = await _client.dio.post(
        'https://m.weibo.cn/api/friendships/destory',
        data: {'uid': uid},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Referer': 'https://m.weibo.cn/profile/$uid',
          },
        ),
      );
      if (res.data is Map) {
        return res.data['ok'] == 1 || res.data['result'] == true;
      }
    } catch (_) {}

    return false;
  }
}

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  final client = ref.watch(weiboDioClientProvider);
  final storage = ref.watch(storageServiceProvider);
  return FeedRepository(client, storage);
});
