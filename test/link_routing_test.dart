import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/services/link_routing_service.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/detail/presentation/weibo_article_page.dart';

void main() {
  group('LinkRoutingService URL Matching Tests', () {
    test('Normalizes official Weibo HTTP smart links to HTTPS', () {
      expect(
        LinkRoutingService.normalizeOfficialUrl(
          'http://weibo.com/ttarticle/p/show?id=2310475343796384104518',
        ),
        'https://weibo.com/ttarticle/p/show?id=2310475343796384104518',
      );
      expect(
        LinkRoutingService.articleIdFromUrl(
          'http://weibo.com/ttarticle/p/show?id=2310475343796384104518',
        ),
        '2310475343796384104518',
      );
      expect(
        LinkRoutingService.canHandleNatively(
          'https://weibo.com/ttarticle/p/show?id=2310475343796384104518',
        ),
        isTrue,
      );
      expect(
        LinkRoutingService.normalizeOfficialUrl(
          'http://example.com/article?id=1',
        ),
        'http://example.com/article?id=1',
      );
    });

    test('Can correctly identify native status URLs', () {
      expect(
          LinkRoutingService.canHandleNatively(
              'https://m.weibo.cn/status/5012345678901234'),
          isTrue);
      expect(
          LinkRoutingService.canHandleNatively(
              'https://m.weibo.cn/detail/5012345678901234'),
          isTrue);
      expect(
          LinkRoutingService.canHandleNatively(
              'https://weibo.com/1234567890/P2xAbCdEf'),
          isTrue);
      expect(
          LinkRoutingService.canHandleNatively(
              'https://www.weibo.com/detail/5012345678901234'),
          isTrue);
      expect(
          LinkRoutingService.canHandleNatively(
              'https://m.weibo.cn/1234567890/5012345678901234'),
          isTrue);
    });

    test('Can correctly identify user profile URLs', () {
      expect(
          LinkRoutingService.canHandleNatively(
              'https://m.weibo.cn/u/1234567890'),
          isTrue);
      expect(
          LinkRoutingService.canHandleNatively(
              'https://weibo.com/u/1234567890'),
          isTrue);
      expect(
          LinkRoutingService.canHandleNatively(
              'https://m.weibo.cn/profile/1234567890'),
          isTrue);
      expect(
          LinkRoutingService.canHandleNatively(
              'https://weibo.com/n/%E6%88%90%E9%83%BDAG%E6%95%91%E8%B5%8E_'),
          isTrue);
      expect(
          LinkRoutingService.canHandleNatively('https://m.weibo.cn/n/成都AG救赎_'),
          isTrue);
    });

    test('Can correctly identify chaohua URLs', () {
      expect(
          LinkRoutingService.canHandleNatively(
              'https://m.weibo.cn/p/100808abcdef123456'),
          isTrue);
    });

    test('Treats general websites and shortlinks as non-native web links', () {
      expect(LinkRoutingService.canHandleNatively('https://t.cn/A6xyz123'),
          isFalse);
      expect(LinkRoutingService.canHandleNatively('https://www.google.com'),
          isFalse);
      expect(
          LinkRoutingService.canHandleNatively(
              'https://github.com/flutter/flutter'),
          isFalse);
    });
  });

  group('WeiboArticleParser Tests', () {
    test('Parses the official article markers and keeps block order', () {
      final document = WeiboArticleParser.parse('''
        <html><head><title>备用标题 - 微博</title></head><body>
          <div class="authorinfo">
            <span class="author1"><img class="W_face_radius" src="http://wx1.sinaimg.cn/avatar.jpg">
              <a href="/u/6048569942"><em>数码闲聊站</em></a>
            </span>
            <span class="time">09-16 15:30</span><span class="num">阅读数：31万+</span>
          </div>
          <div node-type="articleTitle">官方文章标题</div>
          <div node-type="contentBody">
            <p>第一段 &amp; 正文</p>
            <figure><img src="http://wx1.sinaimg.cn/wap720/pic.jpg" aspect="1.25"></figure>
            <p><strong>一、章节标题</strong></p>
          </div>
        </body></html>
      ''');

      expect(document.title, '官方文章标题');
      expect(document.author, '数码闲聊站');
      expect(document.publishedAt, '09-16 15:30');
      expect(document.readCount, '阅读数：31万+');
      expect(document.blocks, hasLength(3));
      expect(document.blocks[0].value, '第一段 & 正文');
      expect(document.blocks[0].type, WeiboArticleBlockType.text);
      expect(document.blocks[1].value, 'https://wx1.sinaimg.cn/wap720/pic.jpg');
      expect(document.blocks[1].type, WeiboArticleBlockType.image);
      expect(document.blocks[2].type, WeiboArticleBlockType.heading);
    });
  });

  group('WeiboStatusModel Video Quality Parsing Tests', () {
    test('Parses an official live-room link without treating it as a video URL',
        () {
      const liveId = '1022:2321325342407968817159';
      final model = WeiboStatusModel.fromJson({
        'id': '5342410088911421',
        'mid': '5342410088911421',
        'created_at': '刚刚',
        'text_raw': '直播动态',
        'user': {'id': '6593199887', 'screen_name': '原神'},
        'page_info': {
          'type': 'live',
          'page_pic': {'url': 'https://wx1.sinaimg.cn/cover.jpg'},
          'page_url': 'https://weibo.com/l/wblive/p/show/$liveId',
        },
        'url_struct': [
          {
            'url_title': '原神的微博直播',
            'ori_url': 'https://weibo.com/l/wblive/p/show/$liveId',
          },
        ],
      });

      expect(model.liveId, equals(liveId));
      expect(model.isLiveBroadcast, isTrue);
      expect(model.hasVideo, isTrue);
      expect(model.videoCoverUrl, equals('https://wx1.sinaimg.cn/cover.jpg'));
      expect(model.videoStreamUrl, isNull);
    });

    test('Accepts a direct live stream field and normalizes its scheme', () {
      final model = WeiboStatusModel.fromJson({
        'id': '5342410088911421',
        'mid': '5342410088911421',
        'text_raw': '直播流',
        'user': {'id': '6593199887', 'screen_name': '原神'},
        'page_info': {
          'type': 'live',
          'live_id': '1022:live-room',
          'media_info': {
            'live_origin_hls_url': 'http://plwb00.live.weibo.com/live.flv',
          },
        },
      });

      expect(model.liveId, equals('1022:live-room'));
      expect(model.videoStreamUrl,
          equals('https://plwb00.live.weibo.com/live.flv'));
      expect(model.videoQualityUrls?['直播'],
          equals('https://plwb00.live.weibo.com/live.flv'));
    });

    test('Preserves ended live status without promoting its replay stream', () {
      final model = WeiboStatusModel.fromJson({
        'id': '5342410088911421',
        'mid': '5342410088911421',
        'text_raw': '已结束直播',
        'user': {'id': '6593199887', 'screen_name': '原神'},
        'page_info': {
          'type': 'live',
          'live_id': '1022:live-room',
          'status': 3,
          'media_info': {
            'replay_origin_url': 'https://example.com/replay.flv',
          },
        },
      });

      expect(model.liveStatus, equals(3));
      expect(model.isLiveEnded, isTrue);
      expect(model.videoStreamUrl, isNull);
    });

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
      expect(model.videoQualityUrls!['1080P 超清'],
          equals('https://f.video.weibocdn.com/1080p.mp4'));
    });
  });
}
