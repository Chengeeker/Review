import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:review/features/compose/data/weibo_compose_models.dart';

void main() {
  test('builds the public web payload with the current fields', () {
    final payload = buildWeiboComposePayload(text: 'hello');

    expect(payload['content'], 'hello');
    expect(payload['visible'], 0);
    expect(payload['share_id'], '');
    expect(payload['vote'], '');
    expect(payload.containsKey('pic_id'), isFalse);
  });

  test('encodes web visibility and image media objects', () {
    final payload = buildWeiboComposePayload(
      text: 'hello',
      visibility: WeiboVisibility.friends,
      imageIds: const ['p1', 'p2'],
      imageTypes: const ['image/png', 'image/jpeg'],
    );

    expect(payload['visible'], 6);
    final media = jsonDecode(payload['pic_id'] as String) as List;
    expect(media.first['pid'], 'p1');
    expect(media.first['type'], 'image/png');
    expect(media.last['type'], 'image/jpeg');
  });

  test('encodes the web video media object and declaration', () {
    final payload = buildWeiboComposePayload(
      text: 'hello',
      videoId: 'v1',
      mblogStatement: 7,
    );

    final media = jsonDecode(payload['pic_id'] as String) as List;
    expect(media.single['type'], 'video');
    expect(media.single['media_id'], 'v1');
    expect(payload['need_transcode'], 1);
    expect(payload['mblog_statement'], 7);
  });

  test('keeps official location and attached publish metadata in the payload', () {
    final payload = buildWeiboComposePayload(
      text: 'hello',
      position: const {
        'poiid': 'B2094755F8',
        'poititle': '微博总部',
        'pc_title': ' 北京·微博总部',
        'long': '116.4',
        'lat': '39.9',
        'spot_type': 1,
      },
      monograph: const {
        'id': '12',
        'url': 'https://weibo.com/collection/12',
        'title': '我的专栏',
      },
      ratingObjectId: '1022:1001201',
      score: 4,
      topicId: '100808123',
      syncMblog: true,
    );

    expect(payload['poiid'], 'B2094755F8');
    expect(payload['lat'], '39.9');
    expect(jsonDecode(payload['monograph'] as String)['title'], '我的专栏');
    expect(payload['rating_object_id'], '1022:1001201');
    expect(payload['score'], 4);
    expect(payload['topic_id'], '100808123');
    expect(payload['sync_mblog'], 1);
  });
}
