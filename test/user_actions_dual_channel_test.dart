import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/detail/data/detail_repository.dart';
import 'package:review/features/feed/data/feed_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Dual-channel User Actions & Feed Tests', () {
    test('Like and Cancel Like in mobile-only session routes to m.weibo.cn/api/attitudes', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      await storage.setFullCookie('SUB=mobile_sub; XSRF-TOKEN=mobile_xsrf');
      await storage.setMobileCookie('SUB=mobile_sub; XSRF-TOKEN=mobile_xsrf');

      final client = WeiboDioClient(storage);
      RequestOptions? likeReq;
      RequestOptions? cancelReq;

      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path.contains('create')) {
              likeReq = options;
            } else if (options.uri.path.contains('destroy')) {
              cancelReq = options;
            }
            handler.resolve(Response(requestOptions: options, data: {'ok': 1}));
          },
        ),
      );

      final repo = FeedRepository(client, storage);

      // 1. Like
      final likeResult = await repo.setLikeState('12345', like: true);
      expect(likeResult, isTrue);
      expect(likeReq?.uri.host, 'm.weibo.cn');
      expect(likeReq?.uri.path, '/api/attitudes/create');
      expect(likeReq?.headers['Cookie'], contains('SUB=mobile_sub'));
      expect(likeReq?.headers['Cookie'], contains('MLOGIN=1'));
      expect(likeReq?.data, contains('id=12345'));
      expect(likeReq?.data, contains('attitude=heart'));
      expect(likeReq?.data, contains('st=mobile_xsrf'));

      // 2. Cancel Like
      final cancelResult = await repo.setLikeState('12345', like: false);
      expect(cancelResult, isTrue);
      expect(cancelReq?.uri.host, 'm.weibo.cn');
      expect(cancelReq?.uri.path, '/api/attitudes/destroy');
      expect(cancelReq?.headers['Cookie'], contains('SUB=mobile_sub'));
      expect(cancelReq?.data, contains('id=12345'));
      expect(cancelReq?.data, contains('attitude=heart'));
      expect(cancelReq?.data, contains('st=mobile_xsrf'));
    });

    test('Favorite and Destroy Favorite in mobile-only session routes to m.weibo.cn/api/favorites', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      await storage.setFullCookie('SUB=mobile_sub; XSRF-TOKEN=mobile_xsrf');
      await storage.setMobileCookie('SUB=mobile_sub; XSRF-TOKEN=mobile_xsrf');

      final client = WeiboDioClient(storage);
      RequestOptions? favReq;
      RequestOptions? unfavReq;

      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path.contains('create')) {
              favReq = options;
            } else if (options.uri.path.contains('destory')) {
              unfavReq = options;
            }
            handler.resolve(Response(requestOptions: options, data: {'ok': 1}));
          },
        ),
      );

      final repo = FeedRepository(client, storage);

      // 1. Favorite
      final favResult = await repo.setFavoriteState('45678', favorite: true);
      expect(favResult, isTrue);
      expect(favReq?.uri.host, 'm.weibo.cn');
      expect(favReq?.uri.path, '/api/favorites/create');
      expect(favReq?.headers['Cookie'], contains('SUB=mobile_sub'));
      expect(favReq?.headers['Cookie'], contains('MLOGIN=1'));
      expect(favReq?.data, contains('id=45678'));
      expect(favReq?.data, contains('st=mobile_xsrf'));

      // 2. Unfavorite
      final unfavResult = await repo.setFavoriteState('45678', favorite: false);
      expect(unfavResult, isTrue);
      expect(unfavReq?.uri.host, 'm.weibo.cn');
      expect(unfavReq?.uri.path, '/api/favorites/destory');
      expect(unfavReq?.data, contains('id=45678'));
      expect(unfavReq?.data, contains('st=mobile_xsrf'));
    });

    test('Delete Tweet in mobile-only session routes to m.weibo.cn/profile/delMyblog', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      await storage.setFullCookie('SUB=mobile_sub; XSRF-TOKEN=mobile_xsrf');
      await storage.setMobileCookie('SUB=mobile_sub; XSRF-TOKEN=mobile_xsrf');

      final client = WeiboDioClient(storage);
      RequestOptions? delReq;

      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            delReq = options;
            handler.resolve(Response(requestOptions: options, data: {'ok': 1}));
          },
        ),
      );

      final repo = FeedRepository(client, storage);
      final result = await repo.deleteTweet('78901');

      expect(result, isTrue);
      expect(delReq?.uri.host, 'm.weibo.cn');
      expect(delReq?.uri.path, '/profile/delMyblog');
      expect(delReq?.headers['Cookie'], contains('SUB=mobile_sub'));
      expect(delReq?.headers['Cookie'], contains('MLOGIN=1'));
      expect(delReq?.data, contains('mid=78901'));
      expect(delReq?.data, contains('st=mobile_xsrf'));
    });

    test('Comment actions (send, reply, destroy) in mobile-only session route to m.weibo.cn/api/comments', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      await storage.setFullCookie('SUB=mobile_sub; XSRF-TOKEN=mobile_xsrf');
      await storage.setMobileCookie('SUB=mobile_sub; XSRF-TOKEN=mobile_xsrf');

      final client = WeiboDioClient(storage);
      RequestOptions? sendReq;
      RequestOptions? replyReq;
      RequestOptions? destroyReq;

      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path.endsWith('/create')) {
              sendReq = options;
            } else if (options.uri.path.endsWith('/reply')) {
              replyReq = options;
            } else if (options.uri.path.endsWith('/destroy')) {
              destroyReq = options;
            }
            handler.resolve(Response(requestOptions: options, data: {'ok': 1}));
          },
        ),
      );

      final detailRepo = DetailRepository(client);

      // 1. Send Comment
      final sendResult = await detailRepo.sendComment(id: '10001', content: '测试评论');
      expect(sendResult.success, isTrue);
      expect(sendReq?.uri.host, 'm.weibo.cn');
      expect(sendReq?.uri.path, '/api/comments/create');
      expect(sendReq?.data, contains('id=10001'));
      expect(sendReq?.data, contains('st=mobile_xsrf'));

      // 2. Reply Comment
      final replyResult = await detailRepo.replyComment(statusId: '10001', commentId: '20002', content: '测试回复');
      expect(replyResult.success, isTrue);
      expect(replyReq?.uri.host, 'm.weibo.cn');
      expect(replyReq?.uri.path, '/api/comments/reply');
      expect(replyReq?.data, contains('id=10001'));
      expect(replyReq?.data, contains('cid=20002'));
      expect(replyReq?.data, contains('st=mobile_xsrf'));

      // 3. Destroy Comment
      final destroyResult = await detailRepo.destroyComment(cid: '20002');
      expect(destroyResult.success, isTrue);
      expect(destroyReq?.uri.host, 'm.weibo.cn');
      expect(destroyReq?.uri.path, '/api/comments/destroy');
      expect(destroyReq?.data, contains('cid=20002'));
      expect(destroyReq?.data, contains('st=mobile_xsrf'));
    });

    test('Desktop session uses weibo.com endpoints for like and favorite', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      await storage.setFullCookie('SUB=desktop_sub; XSRF-TOKEN=desktop_xsrf');
      await storage.setDesktopCookie('SUB=desktop_sub; XSRF-TOKEN=desktop_xsrf');

      final client = WeiboDioClient(storage);
      RequestOptions? likeReq;
      RequestOptions? favReq;

      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path.contains('setLike')) {
              likeReq = options;
            } else if (options.uri.path.contains('createFavorites')) {
              favReq = options;
            }
            handler.resolve(Response(requestOptions: options, data: {'ok': 1}));
          },
        ),
      );

      final repo = FeedRepository(client, storage);

      final likeResult = await repo.setLikeState('11111', like: true);
      expect(likeResult, isTrue);
      expect(likeReq?.uri.host, 'weibo.com');
      expect(likeReq?.uri.path, '/ajax/statuses/setLike');
      expect(likeReq?.headers['Cookie'], contains('SUB=desktop_sub'));

      final favResult = await repo.setFavoriteState('11111', favorite: true);
      expect(favResult, isTrue);
      expect(favReq?.uri.host, 'weibo.com');
      expect(favReq?.uri.path, '/ajax/statuses/createFavorites');
      expect(favReq?.headers['Cookie'], contains('SUB=desktop_sub'));
    });

    test('getFriendsTimeline falls back to m.weibo.cn/feed/friends when desktop returns empty and session is mobile', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      await storage.setFullCookie('SUB=mobile_sub; XSRF-TOKEN=mobile_xsrf');
      await storage.setMobileCookie('SUB=mobile_sub; XSRF-TOKEN=mobile_xsrf');
      await storage.setLoggedIn(true);

      final client = WeiboDioClient(storage);
      RequestOptions? mobileFeedReq;

      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.host == 'weibo.com') {
              // Desktop endpoints return empty or failure
              handler.resolve(Response(requestOptions: options, data: {'statuses': []}, statusCode: 200));
            } else if (options.uri.host == 'm.weibo.cn' && options.uri.path.contains('/feed/friends')) {
              mobileFeedReq = options;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'ok': 1,
                    'data': {
                      'statuses': [
                        {
                          'id': '998877',
                          'text': '来自移动端关注流的一条微博',
                          'user': {'id': '123', 'screen_name': '测试博主'},
                        }
                      ],
                      'max_id': '998877',
                    },
                  },
                ),
              );
            } else {
              handler.resolve(Response(requestOptions: options, data: {}, statusCode: 200));
            }
          },
        ),
      );

      final repo = FeedRepository(client, storage);
      final timelineResult = await repo.getFriendsTimeline(page: 1);

      expect(timelineResult.statuses.isNotEmpty, isTrue);
      expect(timelineResult.statuses.first.id, '998877');
      expect(mobileFeedReq?.uri.host, 'm.weibo.cn');
      expect(mobileFeedReq?.uri.path, '/feed/friends');
      expect(mobileFeedReq?.headers['Cookie'], contains('SUB=mobile_sub'));
    });
  });
}
