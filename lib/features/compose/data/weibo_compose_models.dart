import 'dart:convert';

/// Visibility values used by Weibo's current web status update endpoint.
enum WeiboVisibility {
  public(0, '公开'),
  fans(10, '粉丝'),
  friends(6, '好友圈'),
  self(1, '仅自己可见'),
  group(5, '群可见');

  const WeiboVisibility(this.code, this.label);

  final int code;
  final String label;
}

class WeiboDeclarationOption {
  const WeiboDeclarationOption({required this.value, required this.label});

  final int value;
  final String label;
}

/// Builds the current web publisher payload for `/ajax/statuses/update`.
///
/// The web publisher sends `visible` on every request and serializes media
/// objects into `pic_id`. The declaration type is obtained from the current
/// server config instead of being guessed locally.
Map<String, dynamic> buildWeiboComposePayload({
  required String text,
  WeiboVisibility visibility = WeiboVisibility.public,
  List<String> imageIds = const <String>[],
  List<String> imageTypes = const <String>[],
  String? videoId,
  String? videoPid,
  String? videoMediaGroupId,
  Map<String, dynamic>? position,
  Map<String, dynamic>? monograph,
  String? ratingObjectId,
  double? score,
  String? topicId,
  bool syncMblog = false,
  int mblogStatement = 0,
}) {
  final payload = <String, dynamic>{
    'content': text,
    'visible': visibility.code,
    'share_id': '',
    'vote': '',
  };

  if (mblogStatement != 0) {
    payload['mblog_statement'] = mblogStatement;
  }
  if (topicId != null && topicId.isNotEmpty) {
    payload['topic_id'] = topicId;
    payload['sync_mblog'] = syncMblog ? 1 : 0;
  }

  if (monograph != null && monograph['title']?.toString().isNotEmpty == true) {
    payload['monograph'] = jsonEncode(monograph);
  }
  if (ratingObjectId != null && ratingObjectId.isNotEmpty) {
    payload['rating_object_id'] = ratingObjectId;
    if (score != null) payload['score'] = score;
  }
  if (position != null) {
    for (final entry in position.entries) {
      if (entry.value != null && entry.value.toString().isNotEmpty) {
        payload[entry.key] = entry.value;
      }
    }
  }

  if (videoId != null && videoId.isNotEmpty) {
    payload['need_transcode'] = 1;
    payload['pic_id'] = jsonEncode([
      {
        'type': 'video',
        'media_id': videoId,
        'pid': videoPid ?? '',
        'short_url': '',
        'media_group_id': videoMediaGroupId ?? '',
        'tags': <dynamic>[],
      }
    ]);
  } else if (imageIds.isNotEmpty) {
    payload['need_transcode'] = 1;
    payload['pic_id'] = jsonEncode(
      imageIds
          .asMap()
          .entries
          .map(
            (entry) => {
              'type': entry.key < imageTypes.length && imageTypes[entry.key].isNotEmpty
                  ? imageTypes[entry.key]
                  : 'image/jpeg',
              'media_id': entry.value,
              'pid': entry.value,
              'short_url': '',
              'media_group_id': '',
              'tags': <dynamic>[],
            },
          )
          .toList(),
    );
  }

  return payload;
}
