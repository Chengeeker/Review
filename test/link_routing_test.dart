import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/services/link_routing_service.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';

void main() {
  group('LinkRoutingService URL Matching Tests', () {
    test('Can correctly identify native status URLs', () {
      expect(LinkRoutingService.canHandleNatively('https://m.weibo.cn/status/5012345678901234'), isTrue);
      expect(LinkRoutingService.canHandleNatively('https://m.weibo.cn/detail/5012345678901234'), isTrue);
      expect(LinkRoutingService.canHandleNatively('https://weibo.com/1234567890/P2xAbCdEf'), isTrue);
      expect(LinkRoutingService.canHandleNatively('https://www.weibo.com/detail/5012345678901234'), isTrue);
      expect(LinkRoutingService.canHandleNatively('https://m.weibo.cn/1234567890/5012345678901234'), isTrue);
    });

    test('Can correctly identify user profile URLs', () {
      expect(LinkRoutingService.canHandleNatively('https://m.weibo.cn/u/1234567890'), isTrue);
      expect(LinkRoutingService.canHandleNatively('https://weibo.com/u/1234567890'), isTrue);
      expect(LinkRoutingService.canHandleNatively('https://m.weibo.cn/profile/1234567890'), isTrue);
    });

    test('Can correctly identify chaohua URLs', () {
      expect(LinkRoutingService.canHandleNatively('https://m.weibo.cn/p/100808abcdef123456'), isTrue);
    });

    test('Treats general websites and shortlinks as non-native web links', () {
      expect(LinkRoutingService.canHandleNatively('https://t.cn/A6xyz123'), isFalse);
      expect(LinkRoutingService.canHandleNatively('https://www.google.com'), isFalse);
      expect(LinkRoutingService.canHandleNatively('https://github.com/flutter/flutter'), isFalse);
    });
  });

  group('WeiboStatusModel Video Quality Parsing Tests', () {
    test('Parses multiple resolutions from playback_list and media_info', () {
      final json = {
        'id': '123456',
        'mid': '123456',
        'created_at': 'Wed Sep 02 12:00:00 +0800 2026',
        'text_raw': '测试视频微博',
        'source': 'iPhone',
        'reposts_count': 10,
        'comments_count': 20,
        'attitudes_count': 30,
        'user': {
          'id': 1001,
          'screen_name': '测试博主',
        },
        'page_info': {
          'type': 'video',
          'page_title': '高清短片',
          'media_info': {
            'duration': 125,
            'play_count': 50000,
            'playback_list': [
              {
                'play_info': {
                  'label': 'mp4_1080p',
                  'url': 'https://f.video.weibocdn.com/1080p.mp4',
                }
              },
              {
                'play_info': {
                  'label': 'mp4_720p',
                  'url': 'https://f.video.weibocdn.com/720p.mp4',
                }
              },
              {
                'play_info': {
                  'label': 'mp4_480p',
                  'url': 'https://f.video.weibocdn.com/480p.mp4',
                }
              }
            ]
          }
        }
      };

      final model = WeiboStatusModel.fromJson(json);
      expect(model.hasVideo, isTrue);
      expect(model.videoDuration, equals('02:05'));
      expect(model.videoQualityUrls, isNotNull);
      expect(model.videoQualityUrls!.containsKey('1080P 超清'), isTrue);
      expect(model.videoQualityUrls!.containsKey('720P 高清'), isTrue);
      expect(model.videoQualityUrls!.containsKey('480P 标清'), isTrue);
      expect(model.videoQualityUrls!['1080P 超清'], equals('https://f.video.weibocdn.com/1080p.mp4'));
    });
  });
}
