import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/feed/data/feed_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'mobile-only session uses mobile follow API and its scoped cookie',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      await storage.setFullCookie('SUB=full; XSRF-TOKEN=full-xsrf');
      await storage.setMobileCookie('SUB=mobile; XSRF-TOKEN=mobile-xsrf');

      final client = WeiboDioClient(storage);
      RequestOptions? sent;
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sent = options;
            handler.resolve(Response(requestOptions: options, data: {'ok': 1}));
          },
        ),
      );

      final result = await FeedRepository(client, storage).followUser('12345');

      expect(result.success, isTrue);
      expect(sent?.uri.host, 'm.weibo.cn');
      expect(sent?.uri.path, '/api/friendships/create');
      expect(sent?.headers['Cookie'], contains('SUB=mobile'));
      expect(sent?.headers['Cookie'], contains('MLOGIN=1'));
      expect(sent?.headers['X-XSRF-TOKEN'], 'mobile-xsrf');
      expect(sent?.data, 'uid=12345&st=mobile-xsrf');
    },
  );

  test(
    'desktop session uses desktop endpoint and exposes server rejection',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      await storage.setFullCookie('SUB=full; XSRF-TOKEN=full-xsrf');
      await storage.setDesktopCookie('SUB=desktop; XSRF-TOKEN=desktop-xsrf');
      await storage.setMobileCookie('SUB=mobile; XSRF-TOKEN=mobile-xsrf');

      final client = WeiboDioClient(storage);
      RequestOptions? sent;
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sent = options;
            handler.resolve(
              Response(
                requestOptions: options,
                data: {'ok': 0, 'msg': '操作未成功，验证未通过'},
              ),
            );
          },
        ),
      );

      final result = await FeedRepository(
        client,
        storage,
      ).unfollowUser('54321');

      expect(result.success, isFalse);
      expect(result.message, '操作未成功，验证未通过');
      expect(sent?.uri.host, 'weibo.com');
      expect(sent?.path, '/ajax/friendships/destory');
      expect(sent?.headers['Cookie'], contains('SUB=desktop'));
      expect(sent?.headers['X-XSRF-TOKEN'], 'desktop-xsrf');
    },
  );

  test(
    'mobile-only session uses mobile unfollow endpoint and scoped cookie',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      await storage.setFullCookie('SUB=full; XSRF-TOKEN=full-xsrf');
      await storage.setMobileCookie('SUB=mobile; XSRF-TOKEN=mobile-xsrf');

      final client = WeiboDioClient(storage);
      RequestOptions? sent;
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sent = options;
            handler.resolve(Response(requestOptions: options, data: {'ok': 1}));
          },
        ),
      );

      final result = await FeedRepository(
        client,
        storage,
      ).unfollowUser('12345');

      expect(result.success, isTrue);
      expect(sent?.uri.host, 'm.weibo.cn');
      expect(sent?.uri.path, '/api/friendships/destory');
      expect(sent?.headers['Cookie'], contains('SUB=mobile'));
      expect(sent?.headers['Cookie'], contains('MLOGIN=1'));
      expect(sent?.headers['X-XSRF-TOKEN'], 'mobile-xsrf');
      expect(sent?.data, 'uid=12345&st=mobile-xsrf');
    },
  );

  test(
    'mobile XSRF response does not overwrite desktop session token',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      await storage.setFullCookie('SUB=desktop; XSRF-TOKEN=desktop-xsrf');
      await storage.setDesktopCookie('SUB=desktop; XSRF-TOKEN=desktop-xsrf');
      await storage.setMobileCookie('SUB=mobile; XSRF-TOKEN=mobile-xsrf');

      final client = WeiboDioClient(storage);
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: const {},
                headers: Headers.fromMap({
                  'set-cookie': ['XSRF-TOKEN=mobile-next; Path=/'],
                }),
              ),
              true,
            );
          },
        ),
      );

      await client.dio.get('https://m.weibo.cn/api/config');

      expect(storage.getMobileCookie(), contains('XSRF-TOKEN=mobile-next'));
      expect(storage.getDesktopCookie(), contains('XSRF-TOKEN=desktop-xsrf'));
    },
  );
}
