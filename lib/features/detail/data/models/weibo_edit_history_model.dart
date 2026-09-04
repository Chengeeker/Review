import '../../../feed/data/models/weibo_status_model.dart';

/// Weibo Edit History Model
/// Holds the list of revision versions of a modified Weibo post.
class WeiboEditHistoryModel {
  final int ok;
  final int total;
  final List<WeiboStatusModel> statuses;

  const WeiboEditHistoryModel({
    required this.ok,
    required this.total,
    required this.statuses,
  });

  factory WeiboEditHistoryModel.fromJson(Map<String, dynamic> json) {
    final rawStatuses = json['statuses'];
    final List<WeiboStatusModel> list = [];
    if (rawStatuses is List) {
      for (final item in rawStatuses) {
        if (item is Map<String, dynamic>) {
          list.add(WeiboStatusModel.fromJson(item));
        } else if (item is Map) {
          list.add(WeiboStatusModel.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return WeiboEditHistoryModel(
      ok: json['ok'] is int ? json['ok'] as int : (int.tryParse(json['ok']?.toString() ?? '') ?? 0),
      total: json['total'] is int ? json['total'] as int : (int.tryParse(json['total']?.toString() ?? '') ?? list.length),
      statuses: list,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ok': ok,
      'total': total,
      'statuses': statuses.map((s) => s.toJson()).toList(),
    };
  }
}
