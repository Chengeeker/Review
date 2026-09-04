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
        var status = WeiboStatusModel.fromJson(response.data as Map<String, dynamic>);
        if (status.needsLongText) {
          final longText = await getLongText(status.mblogid ?? status.id);
          if (longText != null && longText.isNotEmpty) {
            status = status.copyWith(fullTextRaw: longText);
          }
        }
        if (status.retweetedStatus != null && status.retweetedStatus!.needsLongText) {
          final retweetLongText = await getLongText(status.retweetedStatus!.mblogid ?? status.retweetedStatus!.id);
          if (retweetLongText != null && retweetLongText.isNotEmpty) {
            status = status.copyWith(
              retweetedStatus: status.retweetedStatus!.copyWith(fullTextRaw: retweetLongText),
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

  Future<CommentResult> getComments({
    required String id,
    required String uid,
    String maxId = '0',
    int count = 15,
    int flow = 0,
  }) async {
    try {
      final response = await _client.dio.get(
        ApiConstants.buildComments,
        queryParameters: {
          'id': id,
          'uid': uid,
          'is_reload': maxId == '0' ? 1 : 0,
          'is_show_bulletin': 2,
          'is_mix': 0,
          'count': count,
          'flow': flow,
          if (maxId != '0') 'max_id': maxId,
        },
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final rawComments = data['data'] as List? ?? [];
        final comments = rawComments
            .whereType<Map<String, dynamic>>()
            .map((c) => WeiboCommentModel.fromJson(c))
            .toList();

        final nextMaxId = data['max_id']?.toString() ?? '0';
        final hasMore = comments.isNotEmpty && nextMaxId != '0';

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

        final total = data['total_number'] is int ? data['total_number'] as int : 0;
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
              : (resMap['total_number'] is int ? resMap['total_number'] as int : attitudes.length);
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

        final total = data['total_number'] is int ? data['total_number'] as int : attitudes.length;
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
    String maxId = '0',
    int count = 20,
  }) async {
    try {
      final response = await _client.dio.get(
        ApiConstants.secondComment,
        queryParameters: {
          'id': commentId,
          'flow': 0,
          'count': count,
          if (maxId != '0') 'max_id': maxId,
        },
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final rawComments = data['data'] as List? ?? [];
        final comments = rawComments
            .whereType<Map<String, dynamic>>()
            .map((c) => WeiboCommentModel.fromJson(c))
            .toList();

        final nextMaxId = data['max_id']?.toString() ?? '0';
        return CommentResult(
          comments: comments,
          maxId: nextMaxId,
          hasMore: comments.isNotEmpty && nextMaxId != '0',
        );
      }
    } catch (_) {}
    return const CommentResult(comments: [], hasMore: false);
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
        msg = resData['msg']?.toString() ?? resData['message']?.toString() ?? resData['error']?.toString();
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
        msg = resData['msg']?.toString() ?? resData['message']?.toString() ?? resData['error']?.toString();
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
          if (map['ok'] == 1 || (map['data'] != null && map['data']['id'] != null)) {
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
        msg = resData['msg']?.toString() ?? resData['message']?.toString() ?? resData['error']?.toString();
      }
      return CommentActionResult(success: false, message: msg);
    } catch (e) {
      print('[DetailRepository] destroyComment error: $e');
    }
    return const CommentActionResult(success: false);
  }

  /// Fetch Weibo Edit History revisions (获取微博历史编辑版本列表)
  Future<WeiboEditHistoryModel?> getEditHistory(String mid, {int page = 1}) async {
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
            : (response.data is Map ? Map<String, dynamic>.from(response.data as Map) : {});
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
