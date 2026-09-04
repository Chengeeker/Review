import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review/core/network/visitor_token_engine.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/services/webdav_service.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/detail/data/models/weibo_comment_model.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';

void main() {
  group('Weibo Models Serialization Tests', () {
    test('WeiboStatusModel parses from JSON correctly', () {
      final json = {
        'id': '5138327918413158',
        'mid': '5138327918413158',
        'text_raw': '这是测试微博正文 #科技#',
        'created_at': '10分钟前',
        'source': '<a href="...">来自 iPhone 15 Pro</a>',
        'reposts_count': 120,
        'comments_count': 88,
        'attitudes_count': 1500,
        'user': {
          'id': '2803301701',
          'screen_name': '测试博主',
          'avatar_large': 'https://tvax1.sinaimg.cn/default.jpg',
          'verified': true,
          'verified_type': 0,
        },
        'pic_infos': {
          'pic_1': {
            'pid': 'pic_1',
            'thumbnail': {'url': 'https://wx1.sinaimg.cn/thumbnail.jpg'},
            'bmiddle': {'url': 'https://wx1.sinaimg.cn/bmiddle.jpg'},
            'large': {
              'url': 'https://wx1.sinaimg.cn/large.jpg',
              'geo': {'width': 1080, 'height': 1920},
            },
          },
        },
      };

      final status = WeiboStatusModel.fromJson(json);

      expect(status.id, equals('5138327918413158'));
      expect(status.textRaw, contains('这是测试微博正文'));
      expect(status.source, equals('来自 iPhone 15 Pro'));
      expect(status.user.screenName, equals('测试博主'));
      expect(status.user.verified, isTrue);
      expect(status.pics.length, equals(1));
      expect(status.pics[0].largeUrl, contains('large.jpg'));
    });

    test('WeiboCommentModel parses two-level comment structure correctly', () {
      final json = {
        'id': '998877',
        'text_raw': '支持楼主！',
        'created_at': '5分钟前',
        'like_counts': 42,
        'user': {
          'id': '123456',
          'screen_name': '评论用户A',
          'avatar_large': 'https://tvax1.sinaimg.cn/userA.jpg',
        },
        'comments': [
          {
            'id': '998878',
            'text_raw': '我也支持！',
            'user': {
              'id': '654321',
              'screen_name': '楼中楼用户B',
            },
          }
        ],
      };

      final comment = WeiboCommentModel.fromJson(json);

      expect(comment.id, equals('998877'));
      expect(comment.textRaw, equals('支持楼主！'));
      expect(comment.user.screenName, equals('评论用户A'));
      expect(comment.likeCount, equals(42));
      expect(comment.subComments.length, equals(1));
      expect(comment.subComments[0].user.screenName, equals('楼中楼用户B'));
    });

    test('WeiboCommentModel parses comment image attachment and cleans short links', () {
      final json = {
        'id': '778899',
        'text_raw': '这是带图评论 http://t.cn/A6xxxx',
        'created_at': '1分钟前',
        'like_counts': 5,
        'user': {
          'id': '112233',
          'screen_name': '带图用户',
        },
        'pic': {
          'pid': '006pic_comment',
          'thumbnail': {'url': 'https://wx1.sinaimg.cn/thumbnail/006pic_comment.jpg'},
          'large': {'url': 'https://wx1.sinaimg.cn/large/006pic_comment.jpg', 'width': 1080, 'height': 1920},
        },
        'url_struct': [
          {
            'short_url': 'http://t.cn/A6xxxx',
            'url_title': '查看图片',
            'url_type': 39,
          }
        ],
      };

      final comment = WeiboCommentModel.fromJson(json);

      expect(comment.pics.length, equals(1));
      expect(comment.pic?.largeUrl, equals('https://wx1.sinaimg.cn/large/006pic_comment.jpg'));
      expect(comment.textRaw, equals('这是带图评论'));
    });

    test('WeiboCommentModel does not treat Weibo Smart Search (微博智搜) as image attachment', () {
      final json = {
        'id': '665544',
        'text_raw': '这是微博智搜的回复 http://t.cn/A6smartsearch',
        'created_at': '刚刚',
        'like_counts': 0,
        'user': {
          'id': '999888',
          'screen_name': '微博智搜',
        },
        'url_struct': [
          {
            'short_url': 'http://t.cn/A6smartsearch',
            'url_title': '微博智搜',
            'url_type': 36,
            'long_url': 'https://s.weibo.com/weibo?q=%E6%99%BA%E6%90%9C%E7%BB%93%E6%9E%9C',
            'ori_url': 'https://s.weibo.com/weibo?q=%E6%99%BA%E6%90%9C%E7%BB%93%E6%9E%9C',
          }
        ],
      };

      final comment = WeiboCommentModel.fromJson(json);

      expect(comment.pics.isEmpty, isTrue);
      expect(comment.pic, isNull);
      expect(comment.textRaw, equals('这是微博智搜的回复 http://t.cn/A6smartsearch'));
      expect(comment.urlStruct.length, equals(1));
      expect(comment.urlStruct.first['url_title'], equals('微博智搜'));
    });

    test('WeiboPicModel parses Live Photo correctly', () {
      final liveJson = {
        'pid': 'live_pic_1',
        'type': 'livephoto',
        'video': 'https://video.weibo.com/media/livephoto/sample.mp4',
        'thumbnail': {'url': 'https://wx1.sinaimg.cn/thumbnail/live.jpg'},
        'large': {'url': 'https://wx1.sinaimg.cn/large/live.jpg', 'width': 1080, 'height': 1440},
      };

      final pic = WeiboPicModel.fromJson(liveJson);
      expect(pic.isLivePhoto, isTrue);
      expect(pic.isLive, isTrue);
      expect(pic.livePhotoVideoUrl, equals('https://video.weibo.com/media/livephoto/sample.mp4'));
      expect(pic.largeUrl, equals('https://wx1.sinaimg.cn/large/live.jpg'));
    });

    test('WeiboUserModel parses following, followMe, and ipLocation correctly', () {
      final userJson = {
        'id': '6130897928',
        'screen_name': '巴旦木公主',
        'avatar_hd': 'https://tvax1.sinaimg.cn/avatar.jpg',
        'following': true,
        'follow_me': true,
        'location': '北京',
        'gender': 'f',
      };

      final user = WeiboUserModel.fromJson(userJson);
      expect(user.id, equals('6130897928'));
      expect(user.screenName, equals('巴旦木公主'));
      expect(user.following, isTrue);
      expect(user.followMe, isTrue);
      expect(user.gender, equals('f'));
      expect(user.ipLocation, equals('北京'));
    });

    test('WeiboStatusModel parses titleText and isTop banner correctly', () {
      final statusJson = {
        'id': '12345678',
        'mid': '12345678',
        'text_raw': '博主加油努力自信美丽',
        'created_at': '1小时前',
        'source': '微博轻享版',
        'reposts_count': 0,
        'comments_count': 0,
        'attitudes_count': 0,
        'title': {'text': '赞了这条微博'},
        'isTop': 1,
        'user': {
          'id': '999999',
          'screen_name': '路人甲',
        },
      };

      final status = WeiboStatusModel.fromJson(statusJson);
      expect(status.titleText, equals('赞了这条微博'));
      expect(status.user.id, equals('999999'));
      expect(status.isTop, isTrue);
    });

    test('WeiboStatusModel parses native video metadata from page_info correctly', () {
      final videoJson = {
        'id': '88776655',
        'mid': '88776655',
        'text_raw': '这是视频动态',
        'created_at': '2小时前',
        'source': '微博视频号',
        'reposts_count': 10,
        'comments_count': 20,
        'attitudes_count': 30,
        'user': {
          'id': '112233',
          'screen_name': '视频博主',
        },
        'page_info': {
          'type': 'video',
          'page_title': '精选短视频',
          'page_pic': {'url': 'https://wx1.sinaimg.cn/cover.jpg'},
          'media_info': {
            'stream_url': 'https://f.video.weibocdn.com/sample.mp4',
            'duration': 185,
            'play_count': 125000,
          },
        },
      };

      final status = WeiboStatusModel.fromJson(videoJson);
      expect(status.hasVideo, isTrue);
      expect(status.videoCoverUrl, equals('https://wx1.sinaimg.cn/cover.jpg'));
      expect(status.videoStreamUrl, equals('https://f.video.weibocdn.com/sample.mp4'));
      expect(status.videoDuration, equals('03:05'));
      expect(status.videoPlayCount, equals(125000));
      expect(status.videoTitle, equals('精选短视频'));
    });

    test('WeiboPicModel identifies long screenshot correctly', () {
      final picJson = {
        'pid': '6232a59agy1igkj8jvpy9j20k47psb29',
        'large': {
          'url': 'https://wx2.sinaimg.cn/orj960/long.jpg',
          'geo': {'width': 724, 'height': 10000},
          'cut_type': 1,
        },
      };

      final pic = WeiboPicModel.fromJson(picJson);
      expect(pic.isLong, isTrue);
      expect(pic.isLongPic, isTrue);
      expect(pic.height / pic.width, greaterThan(10));
    });

    test('StorageService exportAllData uses strict whitelist and filters sensitive credentials', () async {
      SharedPreferences.setMockInitialValues({
        StorageService.keyThemeMode: 'dark',
        StorageService.keyWeiboFontSize: 16.5,
        StorageService.keyWeiboSuffix: '来自测试客户端',
        StorageService.keySubCookie: 'sensitive_sub_cookie_value',
        StorageService.keyFullCookie: 'sensitive_full_cookie_value',
        StorageService.keyAccessToken: 'sensitive_access_token',
        StorageService.keyWebDavPassword: 'my_super_secret_password',
        StorageService.keyUserUid: '12345678',
      });

      final storage = await StorageService.init();
      final exported = storage.exportAllData();

      final prefs = exported['preferences'] as Map<String, dynamic>;

      // Allowed keys should be present
      expect(prefs[StorageService.keyThemeMode], equals('dark'));
      expect(prefs[StorageService.keyWeiboFontSize], equals(16.5));
      expect(prefs[StorageService.keyWeiboSuffix], equals('来自测试客户端'));

      // Sensitive keys must NEVER be exported
      expect(prefs.containsKey(StorageService.keySubCookie), isFalse);
      expect(prefs.containsKey(StorageService.keyFullCookie), isFalse);
      expect(prefs.containsKey(StorageService.keyAccessToken), isFalse);
      expect(prefs.containsKey(StorageService.keyWebDavPassword), isFalse);
      expect(prefs.containsKey(StorageService.keyUserUid), isFalse);
    });

    test('WeiboStatusModel parses isLongText, mblogid, and effectiveText correctly', () {
      final json = {
        'id': '5337364026364289',
        'mid': '5337364026364289',
        'mblogid': 'RfG0yqHDP',
        'isLongText': true,
        'text_raw': '这是被截断的微博前部内容...全文',
        'created_at': '刚刚',
        'source': '来自 微博网页版',
        'user': {
          'id': '6074356560',
          'screen_name': 'KPL赛事',
        },
      };

      final status = WeiboStatusModel.fromJson(json);

      expect(status.isLongText, isTrue);
      expect(status.mblogid, equals('RfG0yqHDP'));
      expect(status.needsLongText, isTrue);
      expect(status.effectiveText, equals('这是被截断的微博前部内容...全文'));

      final updatedStatus = status.copyWith(
        fullTextRaw: '这是被截断的微博前部内容以及完整的后半部分内容，无任何截断！',
      );

      expect(updatedStatus.needsLongText, isFalse);
      expect(updatedStatus.effectiveText, equals('这是被截断的微博前部内容以及完整的后半部分内容，无任何截断！'));
    });

    test('WeiboPicModel provides high definition orj960 / large previewUrl and upgrades bmiddleUrl', () {
      final json = {
        'pid': '007S8ezcly1igk012345',
        'thumbnail': {'url': 'https://wx1.sinaimg.cn/thumbnail/007S8ezcly1igk012345.jpg'},
        'large': {'url': 'https://wx1.sinaimg.cn/large/007S8ezcly1igk012345.jpg', 'width': 1080, 'height': 1920},
      };

      final pic = WeiboPicModel.fromJson(json);

      expect(pic.previewUrl, equals('https://wx1.sinaimg.cn/large/007S8ezcly1igk012345.jpg'));
      expect(pic.largeUrl, equals('https://wx1.sinaimg.cn/large/007S8ezcly1igk012345.jpg'));
      expect(pic.bmiddleUrl, equals('https://wx1.sinaimg.cn/large/007S8ezcly1igk012345.jpg'));

      // Test fallback replacement from thumbnail to orj960
      const fallbackPic = WeiboPicModel(
        pid: 'pic_test',
        thumbnail: 'https://wx1.sinaimg.cn/thumbnail/pic_test.jpg',
        large: '',
        original: '',
      );
      expect(fallbackPic.previewUrl, equals('https://wx1.sinaimg.cn/orj960/pic_test.jpg'));
      expect(fallbackPic.bmiddleUrl, equals('https://wx1.sinaimg.cn/orj960/pic_test.jpg'));
    });

    test('WebDavService isSecureUrl validates HTTPS and localhost properly', () {
      expect(WebDavService.isSecureUrl('https://dav.jianguoyun.com/dav/'), isTrue);
      expect(WebDavService.isSecureUrl('http://127.0.0.1:8080/webdav'), isTrue);
      expect(WebDavService.isSecureUrl('http://localhost:8080/webdav'), isTrue);
      expect(WebDavService.isSecureUrl('http://insecure-server.com/dav/'), isFalse);
    });

    test('VisitorTokenEngine extractJsonpPayload parses compressed and whitespace JSONP properly', () {
      const compressed = 'window.gen_callback({"msg":"succ","code":100000,"data":{"tid":"TEST_TID_123"}})';
      final payload1 = VisitorTokenEngine.extractJsonpPayload(compressed);
      expect(payload1, isNotNull);
      expect(payload1, contains('"tid":"TEST_TID_123"'));

      const withWhitespace = 'gen_callback( { "msg" : "succ" , "data" : { "tid" : "TEST_TID_456" } } );';
      final payload2 = VisitorTokenEngine.extractJsonpPayload(withWhitespace);
      expect(payload2, isNotNull);
      expect(payload2, contains('"tid" : "TEST_TID_456"'));
    });

    test('WeiboDioClient extractXsrfToken extracts XSRF-TOKEN case-insensitively', () {
      expect(WeiboDioClient.extractXsrfToken('SUB=123; XSRF-TOKEN=test_token_abc; SUBP=456'), equals('test_token_abc'));
      expect(WeiboDioClient.extractXsrfToken('xsrf-token=token_lower_case; Path=/'), equals('token_lower_case'));
      expect(WeiboDioClient.extractXsrfToken('SUB=123; SUBP=456'), isNull);
      expect(WeiboDioClient.extractXsrfToken(''), isNull);
      expect(WeiboDioClient.extractXsrfToken(null), isNull);
    });

    test('WeiboStatusModel parses mix_media_info multi-video correctly', () {
      final json = {
        'id': '5338018862597546',
        'mid': '5338018862597546',
        'text_raw': 'ColorOS 17 多视频微博测试',
        'created_at': '1小时前',
        'source': 'iPhone',
        'reposts_count': 10,
        'comments_count': 20,
        'attitudes_count': 30,
        'user': {
          'id': '1645677583',
          'screen_name': 'ColorOS陈希',
          'avatar_large': 'https://tvax1.sinaimg.cn/default.jpg',
        },
        'mix_media_info': {
          'items': [
            {
              'type': 'video',
              'id': '1034:5338018051981344',
              'data': {
                'page_title': '视频一',
                'page_pic': 'https://wx4.sinaimg.cn/orj480/v1.jpg',
                'media_info': {
                  'duration': 7,
                  'stream_url': 'https://f.video.weibocdn.com/v1.mp4',
                },
              },
            },
            {
              'type': 'video',
              'id': '1034:5338018102312979',
              'data': {
                'page_title': '视频二',
                'page_pic': 'https://wx3.sinaimg.cn/orj480/v2.jpg',
                'media_info': {
                  'duration': 11,
                  'stream_url': 'https://f.video.weibocdn.com/v2.mp4',
                },
              },
            },
          ],
        },
      };

      final status = WeiboStatusModel.fromJson(json);

      expect(status.id, equals('5338018862597546'));
      expect(status.pics.length, equals(2));
      expect(status.pics[0].isVideo, isTrue);
      expect(status.pics[0].videoUrl, equals('https://f.video.weibocdn.com/v1.mp4'));
      expect(status.pics[0].videoDuration, equals('00:07'));
      expect(status.pics[1].isVideo, isTrue);
      expect(status.pics[1].videoDuration, equals('00:11'));
    });

    test('WeiboStatusModel parses chaohua metadata and url_struct correctly', () {
      final json = {
        'id': '5338454088747626',
        'mid': '5338454088747626',
        'text_raw': '#AG晋级夏季赛六强# 一起加油！',
        'created_at': '10分钟前',
        'source': '微博轻享版',
        'reposts_count': 100,
        'comments_count': 50,
        'attitudes_count': 200,
        'user': {'id': '5878848794', 'screen_name': '成都AG超玩会'},
        'title_source': {
          'name': 'AG超玩会超话',
          'url': 'sinaweibo://pageinfo?pageid=100808e42ac86fcd4c91f965e34411bd21f0b0&type=topic',
          'image': 'https://wx3.sinaimg.cn/thumbnail/ag.jpg',
        },
        'url_struct': [
          {
            'url_title': 'AG超玩会超话',
            'page_id': '100808e42ac86fcd4c91f965e34411bd21f0b0',
            'ori_url': 'https://weibo.com/p/100808e42ac86fcd4c91f965e34411bd21f0b0',
          }
        ],
      };

      final status = WeiboStatusModel.fromJson(json);

      expect(status.chaohuaTitle, equals('AG超玩会超话'));
      expect(status.chaohuaContainerId, equals('100808e42ac86fcd4c91f965e34411bd21f0b0'));
      expect(status.chaohuaAvatar, equals('https://wx3.sinaimg.cn/thumbnail/ag.jpg'));
      expect(status.urlStruct, isNotNull);
      expect(status.urlStruct!.length, equals(1));
    });

    test('WeiboStatusModel.mblogidToMid correctly converts base62 mblogid to numeric mid', () {
      expect(WeiboStatusModel.mblogidToMid('RgxuHaukX'), equals('5339420032499899'));
      expect(WeiboStatusModel.mblogidToMid('5339420032499899'), equals('5339420032499899'));
      expect(WeiboStatusModel.mblogidToMid(''), equals(''));

      // Test parsing in fromJson when mid is missing and only mblogid is present
      final status = WeiboStatusModel.fromJson({
        'mblogid': 'RgxuHaukX',
        'text_raw': '测试微博',
        'created_at': '刚刚',
        'source': '微博网页版',
      });
      expect(status.mid, equals('5339420032499899'));
      expect(status.id, equals('5339420032499899'));
      expect(status.mblogid, equals('RgxuHaukX'));
    });
  });
}
