/// 微博话题词条介绍卡片模型 (涵盖封面图、导语简介、阅读量/讨论量、主持人及官方置顶信息)
class WeiboTopicHeaderModel {
  final String topicOri;
  final String displayName;
  final String summary;
  final String imageUrl;
  final int readCount;
  final int mentionCount;
  final String? hostName;
  final String? hostAvatar;
  final String? hostUid;
  final String? hostVerifiedReason;
  final String? toppingMid;
  final String? shareUrl;

  const WeiboTopicHeaderModel({
    required this.topicOri,
    required this.displayName,
    this.summary = '',
    this.imageUrl = '',
    this.readCount = 0,
    this.mentionCount = 0,
    this.hostName,
    this.hostAvatar,
    this.hostUid,
    this.hostVerifiedReason,
    this.toppingMid,
    this.shareUrl,
  });

  String get formattedReadCount {
    if (readCount >= 100000000) {
      final val = (readCount / 100000000).toStringAsFixed(1);
      return '${val.endsWith(".0") ? val.substring(0, val.length - 2) : val}亿';
    } else if (readCount >= 10000) {
      final val = (readCount / 10000).toStringAsFixed(1);
      return '${val.endsWith(".0") ? val.substring(0, val.length - 2) : val}万';
    } else {
      return '$readCount';
    }
  }

  String get formattedMentionCount {
    if (mentionCount >= 100000000) {
      final val = (mentionCount / 100000000).toStringAsFixed(1);
      return '${val.endsWith(".0") ? val.substring(0, val.length - 2) : val}亿';
    } else if (mentionCount >= 10000) {
      final val = (mentionCount / 10000).toStringAsFixed(1);
      return '${val.endsWith(".0") ? val.substring(0, val.length - 2) : val}万';
    } else {
      return '$mentionCount';
    }
  }

  factory WeiboTopicHeaderModel.fromTopicHeads(Map<String, dynamic> json) {
    final topicOri = json['topic_ori']?.toString() ?? '';
    final obj = json['object'] is Map<String, dynamic> ? json['object'] as Map<String, dynamic> : <String, dynamic>{};
    final displayName = obj['display_name']?.toString() ?? (topicOri.isNotEmpty ? topicOri : '');
    final summary = obj['summary']?.toString() ?? '';
    String imgUrl = '';
    if (obj['image'] is Map) {
      final imgMap = obj['image'] as Map;
      imgUrl = imgMap['url']?.toString() ??
          imgMap['pic_big']?.toString() ??
          imgMap['pic_middle']?.toString() ??
          imgMap['pic_small']?.toString() ??
          '';
    } else if (obj['image'] is String) {
      imgUrl = obj['image'].toString();
    }
    if (imgUrl.isEmpty && json['object_attr'] is Map) {
      final oa = json['object_attr'] as Map;
      if (oa['image'] is String) imgUrl = oa['image'].toString();
    }
    if (imgUrl.startsWith('http://')) {
      imgUrl = imgUrl.replaceFirst('http://', 'https://');
    }
    final shareUrl = obj['url']?.toString() ?? obj['target_url']?.toString();

    final countMap = json['count'] is Map<String, dynamic> ? json['count'] as Map<String, dynamic> : <String, dynamic>{};
    final read = countMap['read'] is int
        ? countMap['read'] as int
        : int.tryParse(countMap['read']?.toString() ?? '') ?? 0;
    final mention = countMap['mention'] is int
        ? countMap['mention'] as int
        : int.tryParse(countMap['mention']?.toString() ?? '') ?? 0;

    final claimInfo = json['claim_info'] is Map<String, dynamic> ? json['claim_info'] as Map<String, dynamic> : null;
    final hostName = claimInfo?['screen_name']?.toString() ?? claimInfo?['name']?.toString();
    final hostAvatar = claimInfo?['avatar_hd']?.toString() ?? claimInfo?['profile_image_url']?.toString();
    final hostUid = claimInfo?['id']?.toString() ?? claimInfo?['idstr']?.toString();
    final hostVerifiedReason = claimInfo?['verified_reason']?.toString();

    // Topping status mid
    String? toppingMid;
    final objectAttr = json['object_attr'] is Map ? json['object_attr'] as Map : null;
    final intention = objectAttr?['intention'] is Map ? objectAttr!['intention'] as Map : null;
    final toppingDocs = intention?['topping_docs_topic']?.toString();
    if (toppingDocs != null && toppingDocs.isNotEmpty && toppingDocs != '-1') {
      toppingMid = toppingDocs.split('_').first;
    }

    return WeiboTopicHeaderModel(
      topicOri: topicOri,
      displayName: displayName,
      summary: summary,
      imageUrl: imgUrl,
      readCount: read,
      mentionCount: mention,
      hostName: hostName,
      hostAvatar: hostAvatar,
      hostUid: hostUid,
      hostVerifiedReason: hostVerifiedReason,
      toppingMid: toppingMid,
      shareUrl: shareUrl,
    );
  }
}
