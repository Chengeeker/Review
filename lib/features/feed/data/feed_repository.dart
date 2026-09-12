import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/storage/storage_service.dart';
import '../../detail/data/detail_repository.dart';
import 'models/weibo_engagement_models.dart';
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

class PollVoteResult {
  final bool success;
  final WeiboPollModel? poll;
  final String? message;

  const PollVoteResult({
    required this.success,
    this.poll,
    this.message,
  });
}

class UserGroupsResult {
  final List<WeiboGroupModel> defaultGroups;
  final List<WeiboGroupModel> personalGroups;
  final List<WeiboGroupModel> hotGroups;
  final bool loaded;

  const UserGroupsResult({
    this.defaultGroups = const [],
    this.personalGroups = const [],
    this.hotGroups = const [],
    this.loaded = false,
  });
}

/// Repository for Fetching Pure Following (关注), Special Following (特别关注), Groups, and Hot Feeds
class FeedRepository {
  final WeiboDioClient _client;
  final StorageService _storage;
  final DetailRepository _detailRepository;

  FeedRepository(this._client, this._storage)
      : _detailRepository = DetailRepository(_client);

  /// Parses desktop timeline statuses and, only when an official engagement
  /// marker is present, fills omitted poll/topic metadata from the official
  /// mobile status endpoint. Desktop responses may keep `is_vote` or
  /// `vote_dynamic` while omitting `url_objects`.
  Future<List<WeiboStatusModel>> _parseStatuses(List rawStatuses) async {
    final statuses = <WeiboStatusModel>[];
    for (final item in rawStatuses) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      try {
        var status = WeiboStatusModel.fromJson(json);
        if (_needsOfficialEngagementHydration(json, status)) {
          final officialJson = await _fetchOfficialStatus(status);
          if (officialJson != null) {
            status = WeiboStatusModel.fromJson({...json, ...officialJson});
          }
        }
        if (status.isLiveBroadcast && !status.hasPlayableVideoStream) {
          status = await _detailRepository.enrichLivePlayback(status);
        }
        if (status.id.isNotEmpty) statuses.add(status);
      } catch (_) {}
    }
    return statuses;
  }

  /// Reuses the same official engagement hydration for other status lists,
  /// including the user profile timeline.
  Future<List<WeiboStatusModel>> parseStatuses(List rawStatuses) {
    return _parseStatuses(rawStatuses);
  }

  bool _needsOfficialEngagementHydration(
    Map<String, dynamic> json,
    WeiboStatusModel status,
  ) {
    final hasVoteMarker = _isTruthy(json['is_vote']) ||
        _isTruthy(json['isVote']) ||
        _isTruthy(json['hasActionTypeCard']) ||
        _isTruthy(json['has_action_type_card']) ||
        json['vote_info'] != null ||
        json['vote_object'] != null ||
        _containsJsonMarker(json['card_info'], 'vote_object') ||
        _containsJsonMarker(json['page_info'], 'vote_object') ||
        _containsJsonMarker(json['vote_dynamic'], 'vote_list') ||
        _hasVoteSmartLink(status);
    final hasHotTopicMarker = _containsHotTopicMarker(json);

    return (status.poll == null && hasVoteMarker) ||
        (status.hotTopic == null && hasHotTopicMarker);
  }

  static bool _hasVoteSmartLink(WeiboStatusModel status) {
    final urlStruct = status.urlStruct;
    if (urlStruct == null) return false;
    return urlStruct.any((item) {
      final values = item.values.map((value) => value.toString()).join(' ');
      return values.contains('vote.weibo.com') ||
          values.contains('投票') ||
          values.toLowerCase().contains('vote');
    });
  }

  Future<Map<String, dynamic>?> _fetchOfficialStatus(
    WeiboStatusModel status,
  ) async {
    final id = status.mid.isNotEmpty ? status.mid : status.id;
    if (id.isEmpty) return null;
    try {
      final response = await _client.dio.get(
        '${ApiConstants.mWeiboUrl}/api/statuses/show',
        queryParameters: {'id': id},
        options: Options(
          headers: {
            'Referer': '${ApiConstants.mWeiboUrl}/',
            'Accept': 'application/json, text/plain, */*',
          },
        ),
      );
      final body = response.data;
      if (body is Map) {
        final data = body['data'];
        if (data is Map) return Map<String, dynamic>.from(data);
        if (body['id'] != null || body['idstr'] != null) {
          return Map<String, dynamic>.from(body);
        }
      }
    } catch (_) {
      // Enrichment failure must leave the original timeline status intact.
    }
    return null;
  }

  static bool _isTruthy(Object? value) {
    return value == true || value == 1 || value == '1';
  }

  static bool _containsJsonMarker(Object? value, String marker) {
    if (value == null) return false;
    if (value is String) return value.contains(marker);
    if (value is Map || value is List) return value.toString().contains(marker);
    return false;
  }

  /// Desktop timeline responses put hot-search metadata in different card
  /// containers. Detect only official hot markers so we can hydrate a missing
  /// card without requesting the mobile endpoint for every normal status.
  static bool _containsHotTopicMarker(Object? value) {
    if (value == null) return false;
    if (value is String) {
      final text = value.toLowerCase();
      return text.contains('热搜') ||
          text.contains('hot_search') ||
          text.contains('hotsearch') ||
          text.contains('new_discuss') ||
          text.contains('discussion_count') ||
          text.contains('discussion_num') ||
          text.contains('discuss_num');
    }
    if (value is List) {
      return value.any(_containsHotTopicMarker);
    }
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        if (key == 'darwin_tags' ||
            key == 'hot_topic' ||
            key == 'hot_topic_info' ||
            key == 'hot_weibo_tags' ||
            key == 'hot_search_topic' ||
            key == 'is_hot_topic' ||
            key == 'is_hot_search' ||
            key == 'new_discuss' ||
            key == 'new_discuss_count' ||
            key == 'new_discuss_num' ||
            key == 'discussion_count' ||
            key == 'discussion_num' ||
            key == 'discuss_num') {
          return true;
        }
        if (_containsHotTopicMarker(entry.value)) return true;
      }
    }
    return false;
  }

  /// Fetch user's custom groups from desktop allGroups endpoint (Structured)
  Future<UserGroupsResult> getUserGroups() async {
    final def = <WeiboGroupModel>[];
    final pers = <WeiboGroupModel>[];
    final hot = <WeiboGroupModel>[];
    var loaded = false;

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
        loaded = true;
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
      loaded: loaded,
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
    if (category.startsWith('102803') &&
        !category.startsWith('102803_ctg1_-_ctg1_')) {
      return getHotTimeline(
          category: category, page: page, maxId: maxId, sinceId: sinceId);
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
    return getGroupsTimeline(
        gid: category, page: page, maxId: maxId, sinceId: sinceId);
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
        final statuses = await _parseStatuses(rawStatuses);

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
          final statuses = await _parseStatuses(rawStatuses);
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
      return getHotTimeline(
          category: '102803', page: page, maxId: maxId, sinceId: sinceId);
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
        final statuses = await _parseStatuses(rawStatuses);

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
        final statuses = await _parseStatuses(rawStatuses);

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

  Future<PollVoteResult> setPollVote({
    required String voteId,
    required List<String> optionIds,
  }) async {
    final normalizedVoteId = voteId.trim();
    final normalizedOptions = optionIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (normalizedVoteId.isEmpty || normalizedOptions.isEmpty) {
      return const PollVoteResult(
        success: false,
        message: '请选择一个投票选项',
      );
    }

    try {
      final response = await _client.dio.post(
        ApiConstants.setVote,
        data: {
          'id': normalizedVoteId,
          'vote_items': normalizedOptions.join(','),
          'ext': '4',
        },
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/',
          },
        ),
      );
      final body = response.data;
      if (!_isSuccessfulResponse(body)) {
        return PollVoteResult(
          success: false,
          message: _responseMessage(body) ?? '投票失败，请检查网络或登录状态',
        );
      }

      final voteObject = _voteObjectFromResponse(body);
      final poll = voteObject == null
          ? null
          : WeiboPollModel.fromVoteObject(
              voteObject,
              fallbackId: normalizedVoteId,
            );
      return PollVoteResult(success: true, poll: poll);
    } catch (_) {
      return const PollVoteResult(
        success: false,
        message: '投票失败，请检查网络或登录状态',
      );
    }
  }

  Future<WeiboPollModel?> getPollResult({
    required String statusId,
    required String pollId,
  }) async {
    final normalizedStatusId = statusId.trim();
    if (normalizedStatusId.isEmpty) return null;

    // The mobile status response is the same official status source already
    // used for engagement hydration and is more reliable for public poll
    // counts. Keep the desktop endpoint as a fallback for web-only sessions.
    final endpoints = [
      (
        url: '${ApiConstants.mWeiboUrl}/api/statuses/show',
        referer: '${ApiConstants.mWeiboUrl}/',
      ),
      (
        url: ApiConstants.statusDetail,
        referer: 'https://weibo.com/',
      ),
    ];
    for (final endpoint in endpoints) {
      try {
        final response = await _client.dio.get(
          endpoint.url,
          queryParameters: {'id': normalizedStatusId},
          options: Options(
            headers: {
              'Referer': endpoint.referer,
              'Accept': 'application/json, text/plain, */*',
            },
          ),
        );
        final poll = _pollFromResponse(response.data, pollId);
        if (poll == null) continue;
        if (_pollHasResultData(poll)) return poll;
      } catch (_) {}
    }
    // A poll shell without option counts is not a result. Returning it would
    // make the UI render every missing count as a misleading 0票/0%.
    return null;
  }

  static WeiboPollModel? _pollFromResponse(
    Object? body,
    String pollId,
  ) {
    final candidates = <Map<String, dynamic>>[];
    void collect(Object? value) {
      if (value is Map) {
        final map = Map<String, dynamic>.from(value);
        candidates.add(map);
        for (final nested in map.values) {
          collect(nested);
        }
      } else if (value is List) {
        for (final nested in value) {
          collect(nested);
        }
      }
    }

    collect(body);

    for (final candidate in candidates) {
      final poll = WeiboPollModel.fromStatusJson(candidate);
      if (poll != null && (pollId.trim().isEmpty || poll.id == pollId.trim())) {
        if (_pollHasResultData(poll)) return poll;
      }
      final voteObject = _voteObjectFromResponse(candidate);
      if (voteObject != null) {
        final directPoll = WeiboPollModel.fromVoteObject(
          voteObject,
          fallbackId: pollId,
        );
        if (directPoll != null &&
            (pollId.trim().isEmpty || directPoll.id == pollId.trim())) {
          if (_pollHasResultData(directPoll)) return directPoll;
        }
      }
    }
    // Do not return the shell: callers use null to distinguish unavailable
    // counts from a genuine result and avoid rendering fake zero values.
    return null;
  }

  static bool _pollHasResultData(WeiboPollModel poll) {
    // participantCount can be present in a lightweight shell while the
    // per-option result fields are omitted. Require at least one real
    // option-level value before treating the response as usable results.
    return poll.options.any(
      (option) =>
          option.votes > 0 || (option.percent != null && option.percent! > 0),
    );
  }

  static Map<String, dynamic>? _voteObjectFromResponse(Object? body) {
    if (body is! Map) return null;
    final root = Map<String, dynamic>.from(body);
    final direct = root['vote_object'];
    if (direct is Map) return Map<String, dynamic>.from(direct);

    final data = root['data'];
    if (data is Map) {
      final nested = Map<String, dynamic>.from(data);
      final dataVote = nested['vote_object'];
      if (dataVote is Map) return Map<String, dynamic>.from(dataVote);
      final cardInfo = nested['card_info'];
      if (cardInfo is Map && cardInfo['vote_object'] is Map) {
        return Map<String, dynamic>.from(cardInfo['vote_object'] as Map);
      }
      final status = nested['status'];
      if (status is Map) {
        final statusVote = _voteObjectFromResponse(status);
        if (statusVote != null) return statusVote;
      }
    }

    final cardInfo = root['card_info'];
    if (cardInfo is Map && cardInfo['vote_object'] is Map) {
      return Map<String, dynamic>.from(cardInfo['vote_object'] as Map);
    }
    return null;
  }

  static bool _isSuccessfulResponse(Object? body) {
    if (body is! Map) return false;
    final ok = body['ok'];
    if (ok == true) return true;
    if (ok is num) return ok > 0;
    final parsed = num.tryParse(ok?.toString() ?? '');
    return parsed != null && parsed > 0;
  }

  static String? _responseMessage(Object? body) {
    if (body is! Map) return null;
    for (final key in const ['msg', 'message', 'error_msg', '提示']) {
      final value = body[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
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

  Future<bool> toggleFavorite(String mid,
      {required bool currentlyFavorited}) async {
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
        final ok = res.data['ok'] == 1 ||
            res.data['result'] == true ||
            res.data['status'] == 1;
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
