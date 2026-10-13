import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/auth/auth_provider.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/feed/data/feed_repository.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/search/data/following_search_repository.dart';
import 'package:review/features/search/presentation/following_search_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthNotifier {
  _Auth(super.storage) {
    state = const AuthState(isLoggedIn: true);
  }
}

class _Repo extends FollowingSearchRepository {
  _Repo(super.client, super.feed);
  final calls = <(FollowingSearchFilter, int)>[];
  final replies = <Completer<FollowingSearchResult>>[];
  @override
  Future<FollowingSearchResult> search(
    FollowingSearchFilter filter, {
    int page = 1,
  }) {
    calls.add((filter, page));
    final reply = Completer<FollowingSearchResult>();
    replies.add(reply);
    return reply.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StorageService storage;
  late WeiboDioClient client;
  late FeedRepository feed;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService(await SharedPreferences.getInstance());
    client = WeiboDioClient(storage);
    client.dio.interceptors.clear();
    feed = FeedRepository(client, storage);
  });

  FollowingSearchFilter filter({Set<String>? types, DateTime? start}) =>
      FollowingSearchFilter(
        keyword: ' 测试 ',
        types: types ?? followingSearchTypes.keys.toSet(),
        startDate: start,
        endDate: DateTime(2026, 10, 11),
      );

  test(
    'Matches web flags, following scope, count and inclusive date timestamps',
    () {
      final query = filter(start: DateTime(2026, 10, 1)).query(2);
      expect(query, {
        'q': '测试',
        'starttime': DateTime(2026, 10, 1).millisecondsSinceEpoch ~/ 1000,
        'endtime': DateTime(2026, 10, 12).millisecondsSinceEpoch ~/ 1000,
        for (final type in followingSearchTypes.keys) type: 1,
        'atten': 1,
        'count': 10,
        'page': 2,
      });
      final subset = filter(types: {'hasori', 'haspic'}).query(1);
      expect(subset.containsKey('hasret'), false);
      expect(subset.containsKey('starttime'), false);
      expect(() => filter(types: {}).query(1), throwsArgumentError);
      expect(
        () => filter(start: DateTime(2026, 10, 12)).query(1),
        throwsArgumentError,
      );
    },
  );

  test('Uses the exact desktop endpoint and top-level response with total pagination', () async {
    RequestOptions? request;
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'ok': 1,
                'total_number': 11,
                'statuses': [
                  {
                    'id': '1',
                    'text_raw': '正文',
                    'user': {'id': '2', 'screen_name': '作者'},
                  },
                ],
              },
            ),
          );
        },
      ),
    );
    final repo = FollowingSearchRepository(client, feed);
    final first = await repo.search(filter());
    expect(request!.uri.host, 'weibo.com');
    expect(request!.uri.path, '/ajax/statuses/search');
    expect(request!.queryParameters['atten'], 1);
    expect(first.statuses.single.id, '1');
    expect(first.total, 11);
    expect(first.hasMore, true);
    final second = await repo.search(filter(), page: 2);
    expect(second.hasMore, false);
    expect(request!.queryParameters['page'], 2);
  });

  test(
    'Business, login and malformed responses do not become empty results',
    () async {
      Object response = {'ok': 0, 'msg': '请登录'};
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(Response(requestOptions: options, data: response));
          },
        ),
      );
      final repo = FollowingSearchRepository(client, feed);
      await expectLater(repo.search(filter()), throwsFormatException);
      response = '<html>login</html>';
      await expectLater(repo.search(filter()), throwsFormatException);
      response = {
        'ok': 1,
        'data': {'statuses': []},
      };
      await expectLater(repo.search(filter()), throwsFormatException);
      response = {'ok': 1, 'statuses': [], 'total_number': 0};
      expect((await repo.search(filter())).hasMore, false);
    },
  );

  testWidgets(
    'Short first page automatically requests another page and stops at the end',
    (tester) async {
      final repo = _Repo(client, feed);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            authProvider.overrideWith((ref) => _Auth(storage)),
            followingSearchRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: FollowingSearchPage()),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, '搜索'));
      await tester.pump();
      repo.replies[0].complete(
        FollowingSearchResult(
          [
            WeiboStatusModel.fromJson({
              'id': '1',
              'text_raw': '正文',
              'user': {'id': '2', 'screen_name': '作者'},
            }),
          ],
          11,
          true,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(repo.calls.map((call) => call.$2), [1, 2]);
      repo.replies[1].complete(const FollowingSearchResult([], 11, false));
      await tester.pumpAndSettle();
      expect(repo.calls, hasLength(2));
      expect(find.text('没有更多微博了'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Narrow screen auto pagination retains submitted conditions and retries the failed page',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _Repo(client, feed);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            authProvider.overrideWith((ref) => _Auth(storage)),
            followingSearchRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: FollowingSearchPage()),
        ),
      );
      expect(find.byType(FilterChip), findsNWidgets(7));
      await tester.enterText(find.byType(TextField), '测试');
      await tester.tap(find.widgetWithText(FilledButton, '搜索'));
      await tester.pump();
      repo.replies[0].complete(
        FollowingSearchResult(
          [
            for (var i = 0; i < 10; i++)
              WeiboStatusModel.fromJson({
                'id': '$i',
                'text_raw': '正文\n第二行\n第三行\n第四行',
                'user': {'id': '123', 'screen_name': '作者'},
              }),
          ],
          20,
          true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '未提交的新条件');
      expect(find.text('加载更多'), findsNothing);
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      scroll.jumpTo(scroll.position.maxScrollExtent);
      expect(repo.calls, hasLength(2));
      expect(repo.calls[1].$1.keyword, '测试');
      expect(repo.calls[1].$2, 2);
      repo.replies[1].completeError(const FormatException('fixture'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('重试'));
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(repo.calls[2].$2, 2);
      expect(repo.calls[2].$1.keyword, '测试');
      repo.replies[2].complete(const FollowingSearchResult([], 20, false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
