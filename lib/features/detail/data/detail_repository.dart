import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../feed/data/models/weibo_status_model.dart';
import 'models/weibo_comment_model.dart';
import 'models/weibo_attitude_model.dart';
import 'models/weibo_edit_history_model.dart';

class CommentResult {
  final List<WeiboCommentModel> comments;
  final String maxId;
  final bool hasMore;

  const CommentResult({
    required this.comments,
    this.maxId = '0',
    this.hasMore = true,
  });
}

/// Playback metadata returned by Weibo's official H5 video component API.
/// The URLs are short-lived signed CDN URLs and are intentionally kept only
/// in memory for the current player session.
class WeiboVideoComponent {
  final String primaryUrl;
  final Map<String, String> qualityUrls;
  final String? coverUrl;
  final String? title;
  final String? authorName;

  const WeiboVideoComponent({
    required this.primaryUrl,
    required this.qualityUrls,
    this.coverUrl,
    this.title,
    this.authorName,
  });
}

class CommentActionResult {
  final bool success;
  final String? message;

  const CommentActionResult({
    required this.success,
    this.message,
  });
}

class RepostResult {
  final List<WeiboStatusModel> reposts;
  final int totalNumber;
  final int page;
  final bool hasMore;

  const RepostResult({
    this.reposts = const [],
    this.totalNumber = 0,
    this.page = 1,
    this.hasMore = false,
  });
}

class _LivePlayback {
  final int status;
  final String? coverUrl;
  final String? streamUrl;
  final String? title;

  const _LivePlayback({
    required this.status,
    this.coverUrl,
    this.streamUrl,
    this.title,
  });
}

/// Detail Repository for Fetching Status Detail, Comments, and Posting Comments
class DetailRepository {
  final WeiboDioClient _client;

  DetailRepository(this._client);

  Future<String?> getLongText(String id) async {
    try {
      final response = await _client.dio.get(
        ApiConstants.longText,
        queryParameters: {'id': id},
      );
      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        if (data['data'] is Map<String, dynamic>) {
          final inner = data['data'] as Map<String, dynamic>;
          return inner['longTextContent_raw']?.toString() ??
              inner['longTextContent']?.toString() ??
              inner['text_raw']?.toString();
        }
      }
    } catch (e) {
      print('[DetailRepository] getLongText error: $e');
    }
    return null;
  }

  Future<WeiboStatusModel?> getStatusDetail(String id) async {
    try {
      final response = await _client.dio.get(
        ApiConstants.statusDetail,
        queryParameters: {'id': id},
      );
      if (response.data is Map<String, dynamic>) {
        var status =
            WeiboStatusModel.fromJson(response.data as Map<String, dynamic>);
        status = await _enrichOfficialEngagement(status);
        status = await enrichLivePlayback(status);
        if (status.needsLongText) {
          final longText = await getLongText(status.mblogid ?? status.id);
          if (longText != null && longText.isNotEmpty) {
            status = status.copyWith(fullTextRaw: longText);
          }
        }
        if (status.retweetedStatus != null &&
            status.retweetedStatus!.needsLongText) {
          final retweetLongText = await getLongText(
              status.retweetedStatus!.mblogid ?? status.retweetedStatus!.id);
          if (retweetLongText != null && retweetLongText.isNotEmpty) {
            status = status.copyWith(
              retweetedStatus: status.retweetedStatus!
                  .copyWith(fullTextRaw: retweetLongText),
            );
          }
        }
        return status;
      }
    } catch (e) {
      print('[DetailRepository] getStatusDetail error: $e');
    }
    return null;
  }

  /// Resolves a standalone Weibo video component (for example
  /// `h5.video.weibo.com/show/1034:...`) into the signed media URL that the
  /// native video player can consume. The H5 page itself is an HTML shell and
  /// must not be passed to video_player.
  Future<WeiboVideoComponent?> resolveVideoComponent(String objectId) async {
    final normalizedId = objectId.trim();
    if (normalizedId.isEmpty || !normalizedId.contains(':')) return null;

    final requestBody = 'data=${jsonEncode({
          'Component_Play_Playinfo': {'oid': normalizedId},
        })}';
    final requestOptions = Options(
      contentType: Headers.formUrlEncodedContentType,
      headers: {
        'Accept': 'application/json, text/plain, */*',
        'Referer': 'https://h5.video.weibo.com/show/$normalizedId',
        'Origin': 'https://h5.video.weibo.com',
        'PAGE-REFERER': '/show/$normalizedId',
      },
    );

    // This component endpoint is public for public videos.  Do not send the
    // persisted account Cookie to it first: an expired desktop Cookie can
    // make the H5 endpoint return an empty component even though the video
    // itself is still playable.  A session-backed retry remains available for
    // restricted videos.
    final publicClient = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 12),
        headers: {
          'User-Agent': ApiConstants.defaultUserAgent,
          'Accept': 'application/json, text/plain, */*',
        },
      ),
    );
    try {
      final response = await publicClient.post(
        ApiConstants.videoComponent,
        queryParameters: {'page': '/show/$normalizedId'},
        data: requestBody,
        options: requestOptions,
      );
      final parsed = _parseVideoComponentResponse(response.data);
      if (parsed != null) return parsed;
    } catch (_) {
      // The authenticated retry below handles videos with access controls.
    } finally {
      publicClient.close(force: true);
    }

    try {
      final response = await _client.dio.post(
        ApiConstants.videoComponent,
        queryParameters: {'page': '/show/$normalizedId'},
        data: requestBody,
        options: requestOptions,
      );
      return _parseVideoComponentResponse(response.data);
    } catch (_) {
      return null;
    }
  }

  WeiboVideoComponent? _parseVideoComponentResponse(Object? responseData) {
    dynamic payload = responseData;
    if (payload is String) {
      try {
        payload = jsonDecode(payload);
      } catch (_) {
        return null;
      }
    }
    final root = _asMap(payload);
    final data = _asMap(root?['data']);
    final playInfo = _asMap(
      data?['Component_Play_Playinfo'] ?? root?['Component_Play_Playinfo'],
    );
    if (playInfo == null) return null;

    final qualityUrls = <String, String>{};
    void addUrl(String label, Object? value) {
      final candidate = value is Map
          ? (value['url'] ?? value['play_url'] ?? value['src'])
          : value;
      final normalizedUrl = _normalizeVideoMediaUrl(candidate);
      if (normalizedUrl != null && !qualityUrls.containsValue(normalizedUrl)) {
        qualityUrls[label] = normalizedUrl;
      }
    }

    final rawUrls = playInfo['urls'];
    if (rawUrls is Map) {
      for (final entry in rawUrls.entries) {
        addUrl(entry.key.toString(), entry.value);
      }
    } else if (rawUrls is List) {
      for (final item in rawUrls) {
        final itemMap = _asMap(item);
        if (itemMap != null) {
          addUrl(
            _nonEmptyString(itemMap['label']) ?? '默认画质',
            itemMap['url'] ?? itemMap['play_url'] ?? itemMap['play_info'],
          );
        }
      }
    }

    for (final key in const [
      'stream_url',
      'stream_url_hd',
      'mp4_hd_url',
      'mp4_sd_url',
      'h265_mp4_hd',
      'h265_mp4_ld',
      'play_url',
      'media_url',
      'url',
    ]) {
      addUrl(_videoQualityLabel(key), playInfo[key]);
    }

    if (qualityUrls.isEmpty) return null;
    final coverUrl = _normalizeVideoMediaUrl(
      playInfo['cover_image'] ?? playInfo['cover_url'] ?? playInfo['cover'],
    );
    return WeiboVideoComponent(
      primaryUrl: qualityUrls.values.first,
      qualityUrls: Map.unmodifiable(qualityUrls),
      coverUrl: coverUrl,
      title: _nonEmptyString(playInfo['title']),
      authorName: _nonEmptyString(
        playInfo['author'] ?? playInfo['nickname'],
      ),
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  static String? _nonEmptyString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? null : text;
  }

  static String? _normalizeVideoMediaUrl(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final normalized = raw.startsWith('//')
        ? 'https:$raw'
        : raw.startsWith('http://')
            ? raw.replaceFirst('http://', 'https://')
            : raw;
    final uri = Uri.tryParse(normalized);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    final lower = normalized.toLowerCase();
    if (lower.contains('h5.video.weibo.com/show') ||
        lower.contains('weibo.com/tv/show') ||
        lower.contains('video.weibo.com/show')) {
      return null;
    }
    return normalized;
  }

  static String _videoQualityLabel(String key) {
    switch (key) {
      case 'stream_url_hd':
      case 'mp4_hd_url':
      case 'h265_mp4_hd':
        return '高清';
      case 'mp4_sd_url':
      case 'h265_mp4_ld':
        return '标清';
      default:
        return '默认画质';
    }
  }

  /// Resolves a live post's room page into the current official playback
  /// stream. The normal status response only contains a `wblive` page link;
  /// passing that HTML URL to video_player is what caused the endless loading
  /// state reported for live updates.
  Future<WeiboStatusModel> enrichLivePlayback(
    WeiboStatusModel status,
  ) async {
    final liveId = status.liveId?.trim() ?? '';
    if (liveId.isEmpty) return status;

    final playback = await _getLivePlayback(liveId);
    if (playback == null) return status;

    final isLive = playback.status == 1;
    final mergedQualityUrls = <String, String>{
      if (isLive) ...?status.videoQualityUrls,
    };
    if (isLive &&
        playback.streamUrl != null &&
        playback.streamUrl!.isNotEmpty) {
      mergedQualityUrls['直播'] = playback.streamUrl!;
    }

    return status.copyWith(
      videoCoverUrl: status.videoCoverUrl?.isNotEmpty == true
          ? status.videoCoverUrl
          : playback.coverUrl,
      // status=3 is a replay and status=5 is an ended room. Neither should
      // be handed to the native player as if it were the current live feed.
      videoStreamUrl:
          isLive ? (playback.streamUrl ?? status.videoStreamUrl) : '',
      videoTitle: status.videoTitle?.isNotEmpty == true
          ? status.videoTitle
          : playback.title,
      videoQualityUrls: isLive && mergedQualityUrls.isNotEmpty
          ? mergedQualityUrls
          : (isLive ? status.videoQualityUrls : const <String, String>{}),
      liveStatus: playback.status,
    );
  }

  Future<String?> getLiveStreamUrl(String liveId) async {
    final playback = await _getLivePlayback(liveId.trim());
    return playback?.streamUrl;
  }

  Future<_LivePlayback?> _getLivePlayback(String liveId) async {
    try {
      final response = await _client.dio.get(
        ApiConstants.liveRoom,
        queryParameters: {'live_id': liveId},
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/l/wblive/p/show/$liveId',
            'Accept': 'application/json, text/plain, */*',
          },
        ),
      );

      final body = response.data;
      final data = body is Map ? body['data'] : null;
      if (data is! Map) return null;
      final dataMap = Map<String, dynamic>.from(data);
      final liveStatus = int.tryParse(dataMap['status']?.toString() ?? '') ?? 0;

      // The official endpoint currently labels the live FLV stream as
      // `live_origin_hls_url` in some responses. Keep the official field
      // order and accept both transport variants; video_player/Android's
      // ExoPlayer can detect the FLV container from the URL/content type.
      final streamUrl = liveStatus == 1
          ? _firstPlayableMediaUrl([
              dataMap['live_origin_hls_url'],
              dataMap['live_origin_flv_url'],
              dataMap['hls_url'],
              dataMap['m3u8_url'],
              dataMap['stream_url'],
              dataMap['play_url'],
            ])
          : null;

      return _LivePlayback(
        status: liveStatus,
        coverUrl: _firstNonEmptyString([
          dataMap['cover'],
          dataMap['cover_url'],
          dataMap['poster'],
        ]),
        streamUrl: streamUrl,
        title: _firstNonEmptyString([
          dataMap['title'],
          dataMap['desc'],
        ]),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _firstNonEmptyString(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static String? _firstPlayableMediaUrl(List<Object?> values) {
    for (final value in values) {
      final raw = value?.toString().trim() ?? '';
      if (raw.isEmpty) continue;
      final normalized = raw.startsWith('http://')
          ? raw.replaceFirst('http://', 'https://')
          : raw;
      final uri = Uri.tryParse(normalized);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        continue;
      }
      final lower = normalized.toLowerCase();
      if (lower.contains('weibo.com/l/wblive/') ||
          lower.contains('weibo.cn/l/wblive/')) {
        continue;
      }
      return normalized;
    }
    return null;
  }

  /// The desktop detail response can render a poll as a plain smart link and
  /// omit the native card payload. Enrich only the detail page in that case,
  /// using the same official mobile status response as Weibo's own clients.
  Future<WeiboStatusModel> _enrichOfficialEngagement(
    WeiboStatusModel status,
  ) async {
    if (status.poll != null && status.hotTopic != null) return status;
    final id = status.mid.isNotEmpty ? status.mid : status.id;
    if (id.isEmpty) return status;

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
      Map<String, dynamic>? officialJson;
      if (body is Map) {
        final data = body['data'];
        if (data is Map) {
          officialJson = Map<String, dynamic>.from(data);
        } else if (body['id'] != null || body['idstr'] != null) {
          officialJson = Map<String, dynamic>.from(body);
        }
      }
      if (officialJson == null) return status;

      final official = WeiboStatusModel.fromJson(officialJson);
      return status.copyWith(
        poll: status.poll ?? official.poll,
        hotTopic: status.hotTopic ?? official.hotTopic,
        visibilityType: status.visibilityType ?? official.visibilityType,
        liveId: status.liveId ?? official.liveId,
        liveStatus: status.liveStatus ?? official.liveStatus,
        videoCoverUrl: status.videoCoverUrl ?? official.videoCoverUrl,
        videoStreamUrl: status.videoStreamUrl ?? official.videoStreamUrl,
        videoDuration: status.videoDuration ?? official.videoDuration,
        videoPlayCount: status.videoPlayCount != 0
            ? status.videoPlayCount
            : official.videoPlayCount,
        videoTitle: status.videoTitle ?? official.videoTitle,
        videoQualityUrls: status.videoQualityUrls ?? official.videoQualityUrls,
      );
    } catch (_) {
      // Enrichment is best effort; the already-renderable desktop status wins.
      return status;
    }
  }

  Future<CommentResult> getComments({
    required String id,
    required String uid,
    String maxId = '0',
    int count = 10,
    int flow = 0,
  }) async {
    try {
      final normalizedMaxId = maxId.trim().isEmpty ? '0' : maxId.trim();
      final isFirstPage = normalizedMaxId == '0';
      // Match the current desktop web client: it keeps reload/mix stable
      // across cursor pages and requests a larger continuation page.
      final requestCount = isFirstPage ? count : (count < 20 ? 20 : count);
      final response = await _client.dio.get(
        ApiConstants.buildComments,
        queryParameters: {
          'id': id,
          'uid': uid,
          'is_reload': 1,
          'is_show_bulletin': 2,
          // `is_mix=1` is not the desktop continuation mode.  On busy posts
          // it can return only a small subset or fail to advance max_id.
          'is_mix': 0,
          'count': requestCount,
          'flow': flow,
          'fetch_level': 0,
          'locale': 'zh-CN',
          if (!isFirstPage) 'max_id': normalizedMaxId,
        },
      );

      if (response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        // Different web responses use either `data: [...]` or a nested
        // `data: {data: [...], max_id: ...}` envelope.  Use the same tolerant
        // extraction as second-level comments so a valid page is not treated
        // as empty just because the envelope changed.
        final rawComments = _extractCommentList(data);
        final comments = rawComments
            .whereType<Map>()
            .map((c) => WeiboCommentModel.fromJson(
                  Map<String, dynamic>.from(c),
                ))
            .toList();

        final nextMaxId = _normalizeMaxId(_extractMaxId(data));
        final hasMore = comments.isNotEmpty &&
            !_isTerminalMaxId(nextMaxId) &&
            nextMaxId != normalizedMaxId;

        return CommentResult(
          comments: comments,
          maxId: nextMaxId,
          hasMore: hasMore,
        );
      }
    } catch (_) {}
    return const CommentResult(comments: [], hasMore: false);
  }

  /// Repost Timeline for Status (转发名单与微博)
  Future<RepostResult> getReposts({
    required String id,
    int page = 1,
    int count = 20,
  }) async {
    try {
      final response = await _client.dio.get(
        '/ajax/statuses/repostTimeline',
        queryParameters: {
          'id': id,
          'page': page,
          'count': count,
        },
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final rawList = data['data'] as List? ?? [];
        final reposts = rawList
            .whereType<Map<String, dynamic>>()
            .map((e) => WeiboStatusModel.fromJson(e))
            .toList();

        final total =
            data['total_number'] is int ? data['total_number'] as int : 0;
        final maxPage = data['max_page'] is int ? data['max_page'] as int : 1;
        final hasMore = page < maxPage && reposts.isNotEmpty;

        return RepostResult(
          reposts: reposts,
          totalNumber: total,
          page: page,
          hasMore: hasMore,
        );
      }
    } catch (e) {
      print('[DetailRepository] getReposts error: $e');
    }
    return const RepostResult();
  }

  /// Attitudes / Liked Users List (赞的名单)
  Future<AttitudeResult> getAttitudes({
    required String id,
    int page = 1,
    int count = 20,
  }) async {
    // Channel 1: Mobile Web attitudes show (stable, zero-login fallback)
    try {
      final response = await _client.dio.get(
        'https://m.weibo.cn/api/attitudes/show',
        queryParameters: {
          'id': id,
          'page': page,
          'count': count,
        },
      );

      if (response.data is Map<String, dynamic>) {
        final resMap = response.data as Map<String, dynamic>;
        final dataField = resMap['data'];
        if (dataField is Map<String, dynamic>) {
          final rawList = dataField['data'] as List? ?? [];
          final attitudes = rawList
              .whereType<Map<String, dynamic>>()
              .map((e) => WeiboAttitudeModel.fromJson(e))
              .toList();

          final total = dataField['total_number'] is int
              ? dataField['total_number'] as int
              : (resMap['total_number'] is int
                  ? resMap['total_number'] as int
                  : attitudes.length);
          final maxPage = dataField['max'] is int ? dataField['max'] as int : 1;

          return AttitudeResult(
            attitudes: attitudes,
            totalNumber: total,
            page: page,
            hasMore: page < maxPage && attitudes.isNotEmpty,
          );
        }
      }
    } catch (_) {}

    // Channel 2: Desktop likeShow fallback
    try {
      final response = await _client.dio.get(
        '/ajax/statuses/likeShow',
        queryParameters: {
          'id': id,
          'page': page,
          'count': count,
        },
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final rawList = data['data'] as List? ?? [];
        final attitudes = rawList
            .whereType<Map<String, dynamic>>()
            .map((e) => WeiboAttitudeModel.fromJson(e))
            .toList();

        final total = data['total_number'] is int
            ? data['total_number'] as int
            : attitudes.length;
        return AttitudeResult(
          attitudes: attitudes,
          totalNumber: total,
          page: page,
          hasMore: attitudes.isNotEmpty,
        );
      }
    } catch (_) {}

    return const AttitudeResult();
  }

  /// Second-level nested subcomments (楼中楼)
  Future<CommentResult> getSecondComments({
    required String commentId,
    String uid = '',
    String maxId = '0',
    int count = 20,
    int flow = 0,
  }) async {
    try {
      final normalizedMaxId = _normalizeMaxId(maxId);
      final response = await _client.dio.get(
        // The desktop web client does not use the old
        // `/ajax/statuses/getSecondComment` endpoint for the complete
        // thread. It uses the same official cursor endpoint as top-level
        // comments, with fetch_level=1. The legacy endpoint commonly
        // returned only the inline preview (usually two or three rows).
        ApiConstants.buildComments,
        queryParameters: {
          'id': commentId,
          if (uid.trim().isNotEmpty) 'uid': uid.trim(),
          'is_reload': 1,
          'is_show_bulletin': 2,
          'is_mix': normalizedMaxId == '0' ? 0 : 1,
          'fetch_level': 1,
          'flow': flow,
          'count': count,
          'max_id': normalizedMaxId,
          'locale': 'zh-CN',
        },
      );

      if (response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final rawComments = _extractCommentList(data);
        final comments = rawComments
            .whereType<Map<String, dynamic>>()
            .map((c) => WeiboCommentModel.fromJson(c))
            .toList();

        final nextMaxId = _normalizeMaxId(_extractMaxId(data));
        return CommentResult(
          comments: comments,
          maxId: nextMaxId,
          hasMore: comments.isNotEmpty &&
              !_isTerminalMaxId(nextMaxId) &&
              nextMaxId != normalizedMaxId,
        );
      }
    } catch (_) {}
    return const CommentResult(comments: [], hasMore: false);
  }

  static List<dynamic> _extractCommentList(
    Object? payload, {
    int depth = 0,
  }) {
    if (depth > 4) return const [];
    if (payload is List) return payload;
    if (payload is! Map) return const [];

    List<dynamic>? emptyList;
    for (final key in const [
      'data',
      'comments',
      'list',
      'comment_list',
      'commentList',
    ]) {
      final value = payload[key];
      final extracted = _extractCommentList(value, depth: depth + 1);
      if (extracted.isNotEmpty) return extracted;
      if (value is List) emptyList ??= value;
    }
    return emptyList ?? const [];
  }

  static String _extractMaxId(Object? payload, {int depth = 0}) {
    if (depth > 4 || payload is! Map) return '0';

    // The fetch_level=1 response puts the cursor on its outer envelope. Do
    // not descend into `data` first: nested comment objects can themselves
    // carry a max_id and that is not the cursor for the current page.
    for (final key in const ['max_id', 'maxId']) {
      final value = payload[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }

    // Keep compatibility with older/nested response envelopes.
    for (final key in const ['data', 'meta', 'pagination']) {
      final nested = payload[key];
      if (nested is Map) {
        final nestedMaxId = _extractMaxId(nested, depth: depth + 1);
        if (nestedMaxId != '0') return nestedMaxId;
        if (nested['max_id']?.toString().trim() == '0' ||
            nested['maxId']?.toString().trim() == '0') {
          return '0';
        }
      }
    }

    return '0';
  }

  static String _normalizeMaxId(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ||
            normalized == '-1' ||
            normalized.toLowerCase() == 'null'
        ? '0'
        : normalized;
  }

  static bool _isTerminalMaxId(String value) {
    return value.isEmpty || value == '0' || value == '-1';
  }

  /// Send a comment on a Weibo Status (发评论)
  Future<CommentActionResult> sendComment({
    required String id,
    required String content,
  }) async {
    try {
      final numericId = WeiboStatusModel.mblogidToMid(id);
      final response = await _client.dio.post(
        ApiConstants.createComment,
        data: {
          'id': numericId,
          'comment': content,
        },
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/',
          },
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        if (response.data is Map) {
          final map = response.data as Map;
          if (map['ok'] == 1 || map['id'] != null || map['mid'] != null) {
            return const CommentActionResult(success: true);
          }
          final msg = map['msg']?.toString() ?? map['message']?.toString();
          return CommentActionResult(success: false, message: msg);
        }
        return const CommentActionResult(success: true);
      }
    } on DioException catch (e) {
      final resData = e.response?.data;
      String? msg;
      if (resData is Map) {
        msg = resData['msg']?.toString() ??
            resData['message']?.toString() ??
            resData['error']?.toString();
      }
      return CommentActionResult(success: false, message: msg);
    } catch (e) {
      print('[DetailRepository] sendComment error: $e');
    }
    return const CommentActionResult(success: false);
  }

  /// Reply to a specific comment (回复评论)
  Future<CommentActionResult> replyComment({
    required String statusId,
    required String commentId,
    required String content,
  }) async {
    try {
      final numericStatusId = WeiboStatusModel.mblogidToMid(statusId);
      final numericCommentId = WeiboStatusModel.mblogidToMid(commentId);
      final response = await _client.dio.post(
        ApiConstants.replyComment,
        data: {
          'id': numericStatusId,
          'cid': numericCommentId,
          'comment': content,
        },
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/',
          },
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        if (response.data is Map) {
          final map = response.data as Map;
          if (map['ok'] == 1 || map['id'] != null || map['mid'] != null) {
            return const CommentActionResult(success: true);
          }
          final msg = map['msg']?.toString() ?? map['message']?.toString();
          return CommentActionResult(success: false, message: msg);
        }
        return const CommentActionResult(success: true);
      }
    } on DioException catch (e) {
      final resData = e.response?.data;
      String? msg;
      if (resData is Map) {
        msg = resData['msg']?.toString() ??
            resData['message']?.toString() ??
            resData['error']?.toString();
      }
      return CommentActionResult(success: false, message: msg);
    } catch (e) {
      print('[DetailRepository] replyComment error: $e');
    }
    return const CommentActionResult(success: false);
  }

  /// Delete a comment (删除评论：自己发表的评论，或博主在自己微博下删除他人评论)
  Future<CommentActionResult> destroyComment({
    required String cid,
  }) async {
    try {
      final numericCid = WeiboStatusModel.mblogidToMid(cid);
      final response = await _client.dio.post(
        ApiConstants.destroyComment,
        data: {
          'cid': numericCid,
        },
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/',
          },
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        if (response.data is Map) {
          final map = response.data as Map;
          if (map['ok'] == 1 ||
              (map['data'] != null && map['data']['id'] != null)) {
            return const CommentActionResult(success: true);
          }
          final msg = map['msg']?.toString() ?? map['message']?.toString();
          return CommentActionResult(success: false, message: msg);
        }
        return const CommentActionResult(success: true);
      }
    } on DioException catch (e) {
      final resData = e.response?.data;
      String? msg;
      if (resData is Map) {
        msg = resData['msg']?.toString() ??
            resData['message']?.toString() ??
            resData['error']?.toString();
      }
      return CommentActionResult(success: false, message: msg);
    } catch (e) {
      print('[DetailRepository] destroyComment error: $e');
    }
    return const CommentActionResult(success: false);
  }

  /// Fetch Weibo Edit History revisions (获取微博历史编辑版本列表)
  Future<WeiboEditHistoryModel?> getEditHistory(String mid,
      {int page = 1}) async {
    try {
      final response = await _client.dio.get(
        ApiConstants.editHistory,
        queryParameters: {
          'mid': mid,
          'page': page,
        },
        options: Options(
          headers: {
            'Referer': 'https://weibo.com/',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final Map<String, dynamic> json = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : (response.data is Map
                ? Map<String, dynamic>.from(response.data as Map)
                : {});
        return WeiboEditHistoryModel.fromJson(json);
      }
    } catch (e) {
      print('[DetailRepository] getEditHistory error: $e');
    }
    return null;
  }
}

final detailRepositoryProvider = Provider<DetailRepository>((ref) {
  final client = ref.watch(weiboDioClientProvider);
  return DetailRepository(client);
});
