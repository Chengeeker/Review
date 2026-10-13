import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../feed/data/feed_repository.dart';
import '../../feed/data/models/weibo_status_model.dart';

const followingSearchTypes = {
  'hasori': '原创',
  'hasret': '转发',
  'hastext': '纯文字',
  'haspic': '含图片',
  'hasvideo': '含视频',
  'hasmusic': '含音乐',
  'hasv': 'V+微博',
};

class FollowingSearchFilter {
  final String keyword;
  final Set<String> types;
  final DateTime? startDate;
  final DateTime endDate;

  FollowingSearchFilter({
    this.keyword = '',
    required Set<String> types,
    this.startDate,
    required this.endDate,
  }) : types = Set.unmodifiable(types);

  Map<String, dynamic> query(int page) {
    if (page < 1 ||
        types.isEmpty ||
        types.any((type) => !followingSearchTypes.containsKey(type))) {
      throw ArgumentError('请选择微博类型');
    }
    final end = DateTime(endDate.year, endDate.month, endDate.day + 1);
    final start = startDate == null
        ? null
        : DateTime(startDate!.year, startDate!.month, startDate!.day);
    if (start != null && !start.isBefore(end)) {
      throw ArgumentError('开始日期不能晚于结束日期');
    }
    // 网页取消勾选时省略对应参数；结束时间为所选日期次日零点。
    return {
      if (keyword.trim().isNotEmpty) 'q': keyword.trim(),
      if (start != null) 'starttime': start.millisecondsSinceEpoch ~/ 1000,
      'endtime': end.millisecondsSinceEpoch ~/ 1000,
      for (final type in followingSearchTypes.keys)
        if (types.contains(type)) type: 1,
      'atten': 1,
      'count': 10,
      'page': page,
    };
  }
}

class FollowingSearchResult {
  final List<WeiboStatusModel> statuses;
  final int total;
  final bool hasMore;

  const FollowingSearchResult(this.statuses, this.total, this.hasMore);
}

class FollowingSearchRepository {
  final WeiboDioClient _client;
  final FeedRepository _feed;

  FollowingSearchRepository(this._client, this._feed);

  Future<FollowingSearchResult> search(
    FollowingSearchFilter filter, {
    int page = 1,
  }) async {
    final response = await _client.dio.get(
      ApiConstants.searchStatuses,
      queryParameters: filter.query(page),
    );
    final data = response.data;
    if (data is! Map ||
        data['ok']?.toString() != '1' ||
        data['statuses'] is! List) {
      throw const FormatException('关注微博搜索失败，请检查网页端登录状态后重试');
    }
    final raw = data['statuses'] as List;
    final total = int.tryParse(data['total_number']?.toString() ?? '');
    final statuses = await _feed.parseStatuses(raw, resolveLongText: true);
    if (raw.isNotEmpty && statuses.isEmpty) {
      throw const FormatException('微博搜索结果无法解析，请稍后重试');
    }
    return FollowingSearchResult(
      statuses,
      total ?? statuses.length,
      raw.isNotEmpty && (total != null ? page * 10 < total : raw.length >= 10),
    );
  }
}

final followingSearchRepositoryProvider = Provider(
  (ref) => FollowingSearchRepository(
    ref.watch(weiboDioClientProvider),
    ref.watch(feedRepositoryProvider),
  ),
);
