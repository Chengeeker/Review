import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/network/weibo_native_api.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/feed/data/feed_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WeiboNativeApi and FeedRepository Dual-Channel Feed Tests', () {
    late StorageService storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storage = StorageService(prefs);
      await storage.setFullCookie('SUB=dummy_web_cookie; SUBP=dummy_subp');
    });

    test('FeedRepository.getFriendsTimeline prefers Native API when available',
        () async {
      const mockNativeStatuses = {
        'statuses': [
          {
            'id': 'native_status_101',
            'mid': 'native_status_101',
            'text': 'Native following tweet text',
            'created_at': 'Tue Oct 18 10:00:00 +0800 2026',
            'user': {
              'id': 'user_001',
              'screen_name': 'NativeUser',
              'profile_image_url': 'https://example.com/avatar.jpg',
            },
          }
        ],
        'max_id': 'native_status_101',
        'since_id': '0',
        'total_number': 1,
      };

      final client = WeiboDioClient(storage);
      // Dio interceptor throws if called, to prove web channel is not hit
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                error: 'Web channel should not be called when native succeeds',
              ),
            );
          },
        ),
      );

      const channel = MethodChannel('com.review/weibo_auth');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'requestWeiboApi') {
          final endpoint = call.arguments['endpoint'];
          if (endpoint == 'statuses/unread_friends_timeline') {
            return jsonEncode(mockNativeStatuses);
          }
        }
        return null;
      });

      final nativeApi = WeiboNativeApi(channel: channel);
      final repo = FeedRepository(client, storage, nativeApi: nativeApi);

      final result = await repo.getFriendsTimeline(page: 1);

      expect(result.statuses.length, 1);
      expect(result.statuses.first.id, 'native_status_101');
      expect(result.statuses.first.textRaw, 'Native following tweet text');
      expect(result.statuses.first.user.screenName, 'NativeUser');
      expect(result.maxId, 'native_status_101');
      expect(result.hasMore, isTrue);
    });

    test(
        'FeedRepository.getFriendsTimeline seamlessly falls back to Web when Native API fails',
        () async {
      final client = WeiboDioClient(storage);
      var webChannelHit = false;
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.contains('/ajax/feed/friendstimeline')) {
              webChannelHit = true;
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'statuses': [
                      {
                        'id': 'web_status_202',
                        'mid': 'web_status_202',
                        'text': 'Web fallback tweet text',
                        'created_at': 'Tue Oct 18 10:05:00 +0800 2026',
                        'user': {
                          'id': 'user_002',
                          'screen_name': 'WebUser',
                          'profile_image_url': 'https://example.com/avatar2.jpg',
                        },
                      }
                    ],
                    'max_id': 'web_status_202',
                    'since_id': '0',
                  },
                ),
              );
              return;
            }
            handler.next(options);
          },
        ),
      );

      const channel = MethodChannel('com.review/weibo_auth');
      // Native channel throws or returns null (simulating session missing / network error)
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'WEIBO_AUTH_session_missing',
          message: '未登录或缺少原生会话',
        );
      });

      final nativeApi = WeiboNativeApi(channel: channel);
      final repo = FeedRepository(client, storage, nativeApi: nativeApi);

      final result = await repo.getFriendsTimeline(page: 1);

      expect(webChannelHit, isTrue);
      expect(result.statuses.length, 1);
      expect(result.statuses.first.id, 'web_status_202');
      expect(result.statuses.first.textRaw, 'Web fallback tweet text');
      expect(result.statuses.first.user.screenName, 'WebUser');
    });

    test('FeedRepository.getGroupsTimeline prefers Native API and falls back',
        () async {
      const mockNativeGroupStatuses = {
        'statuses': [
          {
            'id': 'group_status_303',
            'text': 'Special group tweet',
            'user': {'id': 'user_003', 'screen_name': 'GroupUser'},
          }
        ],
        'max_id': 'group_status_303',
        'since_id': '0',
      };

      final client = WeiboDioClient(storage);
      const channel = MethodChannel('com.review/weibo_auth');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'requestWeiboApi') {
          final endpoint = call.arguments['endpoint'];
          final params = call.arguments['params'];
          if (endpoint == 'groups/timeline' && params['list_id'] == 'my_gid') {
            return jsonEncode(mockNativeGroupStatuses);
          }
        }
        return null;
      });

      final repo = FeedRepository(
        client,
        storage,
        nativeApi: WeiboNativeApi(channel: channel),
      );

      final result = await repo.getGroupsTimeline(gid: 'my_gid', page: 1);

      expect(result.statuses.length, 1);
      expect(result.statuses.first.id, 'group_status_303');
      expect(result.statuses.first.textRaw, 'Special group tweet');
    });

    test('FeedRepository.getUserTimeline prefers Native API and falls back',
        () async {
      const mockNativeUserStatuses = {
        'statuses': [
          {
            'id': 'user_timeline_404',
            'text': 'Blogger latest tweet',
            'user': {'id': '123456', 'screen_name': 'Blogger'},
          }
        ],
      };

      final client = WeiboDioClient(storage);
      const channel = MethodChannel('com.review/weibo_auth');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'requestWeiboApi') {
          final endpoint = call.arguments['endpoint'];
          final params = call.arguments['params'];
          if (endpoint == 'statuses/user_timeline' && params['uid'] == '123456') {
            return jsonEncode(mockNativeUserStatuses);
          }
        }
        return null;
      });

      final repo = FeedRepository(
        client,
        storage,
        nativeApi: WeiboNativeApi(channel: channel),
      );

      final result = await repo.getUserTimeline(uid: '123456', page: 1);

      expect(result.length, 1);
      expect(result.first.id, 'user_timeline_404');
      expect(result.first.textRaw, 'Blogger latest tweet');
    });

    test('FeedRepository.getUserGroups parses groups via Native API', () async {
      const mockNativeAllGroups = {
        'groups': [
          {
            'title': '我的分组',
            'group': [
              {
                'gid': 'group_1',
                'title': '科技圈',
                'type': 1,
              }
            ],
          },
          {
            'title': '默认分组',
            'group': [
              {
                'gid': 'group_def',
                'title': '特别关注',
                'type': 0,
              }
            ],
          }
        ]
      };

      final client = WeiboDioClient(storage);
      const channel = MethodChannel('com.review/weibo_auth');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'requestWeiboApi') {
          final endpoint = call.arguments['endpoint'];
          if (endpoint == 'groups/allgroups') {
            return jsonEncode(mockNativeAllGroups);
          }
        }
        return null;
      });

      final repo = FeedRepository(
        client,
        storage,
        nativeApi: WeiboNativeApi(channel: channel),
      );

      final result = await repo.getUserGroups();

      expect(result.loaded, isTrue);
      expect(result.personalGroups.length, 1);
      expect(result.personalGroups.first.gid, 'group_1');
      expect(result.personalGroups.first.title, '科技圈');
      expect(result.defaultGroups.length, 1);
      expect(result.defaultGroups.first.title, '特别关注');
    });
  });
}
