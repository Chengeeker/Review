import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/utils/video_quality_utils.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';

void main() {
  test('model does not promote generic HD/default fields to numeric tiers', () {
    final status = WeiboStatusModel.fromJson({
      'id': 'quality-test', 'text_raw': '', 'created_at': '刚刚',
      'user': {'id': '1', 'screen_name': 'test'},
      'page_info': {'type': 'video', 'media_info': {
        'playback_list': [{'play_info': {'label': 'mp4_hd',
          'url': 'https://example.com/hd.mp4'}}],
        'stream_url_hd': 'https://example.com/hd.mp4',
        'stream_url': 'https://example.com/default.mp4',
      }},
    });
    expect(normalizeVideoQualities(status.videoQualityUrls ?? {}),
        {'分辨率未知': 'https://example.com/hd.mp4'});
    expect(status.videoQualityUrls?.keys.any((k) => k.contains('720') || k.contains('480')), isFalse);
  });
  test('only explicit tiers survive mixed API aliases and sort descending', () {
    expect(
      normalizeVideoQualities({
        '480P 标清': '480',
        '720P 高清': '720',
        '1080P 超清': '1080',
        '高清': 'hd',
        '默认画质': 'default',
        '原画': 'original',
        'mp4_720p_mp4': '720-alternate',
        'mp4_hd_mp4': 'hd2',
      }),
      {'1080P': '1080', '720P': '720', '480P': '480'},
    );
  });
  test('unknown preferred stream does not become a fake resolution tier', () {
    expect(
      normalizeVideoQualities({
        '高清': 'hd',
        'mp4_720p_mp4': '720',
      }, preferredUrl: 'hd'),
      {'720P': '720'},
    );
  });
  test(
    'keeps current stream within a resolution and removes duplicate URLs',
    () {
      expect(
        normalizeVideoQualities({
          '720P 高清': 'a',
          'mp4_720p_mp4': 'b',
        }, preferredUrl: 'b'),
        {'720P': 'b'},
      );
      expect(normalizeVideoQualities({'1080P': 'a', '720P': 'a'}), {
        '1080P': 'a',
      });
    },
  );
  test('original and default are not assumed to mean 1080P', () {
    expect(
      normalizeVideoQualities({
        '高清': 'a',
        '原画': 'b',
        '默认画质': 'c',
      }, preferredUrl: 'c'),
      {'分辨率未知': 'c'},
    );
    expect(normalizeVideoQualities({'原画': 'b'}), {'分辨率未知': 'b'});
    expect(normalizeVideoQualities({'mp4_1080p_mp4': ''}), isEmpty);
    expect(normalizeVideoQualities({'直播': 'live'}), {'直播': 'live'});
  });
}
