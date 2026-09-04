import '../../../feed/data/models/weibo_status_model.dart';

/// Model representing a user who liked or reacted to a status (点赞名单)
class WeiboAttitudeModel {
  final String id;
  final WeiboUserModel user;
  final String createdAt;
  final String attitude;
  final String? source;

  const WeiboAttitudeModel({
    required this.id,
    required this.user,
    required this.createdAt,
    this.attitude = 'like',
    this.source,
  });

  factory WeiboAttitudeModel.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : <String, dynamic>{};

    return WeiboAttitudeModel(
      id: json['id']?.toString() ?? '',
      user: WeiboUserModel.fromJson(userJson),
      createdAt: json['created_at']?.toString() ?? '',
      attitude: json['attitude']?.toString() ?? json['attitude_type']?.toString() ?? 'like',
      source: json['source']?.toString(),
    );
  }
}

class AttitudeResult {
  final List<WeiboAttitudeModel> attitudes;
  final int totalNumber;
  final int page;
  final bool hasMore;

  const AttitudeResult({
    this.attitudes = const [],
    this.totalNumber = 0,
    this.page = 1,
    this.hasMore = false,
  });
}
