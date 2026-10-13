import 'package:dio/dio.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/search/data/search_repository.dart';
import 'package:review/features/search/presentation/search_results_page.dart';
import 'package:review/features/search/presentation/search_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _blogger = WeiboUserModel(
  id: '123',
  screenName: '巴旦木公主_',
  avatar: '',
  followersCount: 566000,
);

class _SearchRepository extends SearchRepository {
  _SearchRepository(super.client);
  int suggestionsCalls = 0;
  bool failUsers = false;
  List<WeiboUserModel> firstPageUsers = [_blogger];
  final userPages = <int>[];

  @override
  Future<List<HotSearchItem>> getHotSearch() async => [];

  @override
  Future<SearchSuggestResult> getSearchSuggestions(String query) async {
    suggestionsCalls++;
    return const SearchSuggestResult(
      users: [
        WeiboUserModel(
          id: '456',
          screenName: '巴旦木公主',
          avatar: '',
          followersCount: 5,
        ),
      ],
    );
  }

  @override
  Future<List<WeiboUserModel>> searchUsers(String query, {int page = 1}) async {
    userPages.add(page);
    if (failUsers) throw const FormatException('fixture failure');
    if (page == 1) return firstPageUsers;
    if (page == 2) {
      return [
        _blogger,
        const WeiboUserModel(id: '789', screenName: '下一页用户', avatar: ''),
      ];
    }
    return [];
  }

  @override
  Future<List<SearchChaohuaItem>> searchChaohua(
    String keyword, {
    int page = 1,
  }) async => [];

  @override
  Future<SearchStatusesResult> searchStatusesWithDetails({
    required String keyword,
    int page = 1,
  }) async => const SearchStatusesResult(statuses: []);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StorageService storage;
  late WeiboDioClient client;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService(await SharedPreferences.getInstance());
    client = WeiboDioClient(storage);
    // Isolate fixtures from authentication and the live network.
    client.dio.interceptors.clear();
  });

  test('正式用户卡保留官方顺序、昵称后缀并去重，不混入微博作者', () async {
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
                'data': {
                  'cards': [
                    {
                      'card_type': 11,
                      'card_group': [
                        {
                          'card_type': 10,
                          'user': {
                            'id': 123,
                            'screen_name': '巴旦木公主_',
                            'followers_count': 566000,
                          },
                        },
                        {
                          'card_type': 10,
                          'user': {
                            'id': 456,
                            'screen_name': '巴旦木公主',
                            'followers_count': 5,
                          },
                        },
                        {
                          'card_type': 10,
                          'user': {'id': 123, 'screen_name': '重复'},
                        },
                        {
                          'card_type': 10,
                          'user': {'screen_name': '没有UID'},
                        },
                      ],
                    },
                    {
                      'card_type': 9,
                      'mblog': {
                        'user': {'id': 789, 'screen_name': '无关作者'},
                      },
                    },
                  ],
                },
              },
            ),
          );
        },
      ),
    );
    final users = await SearchRepository(client)
        .searchUsers(' @巴旦木公主 ', page: 2);
    expect(users.map((u) => u.id), ['123', '456']);
    expect(users.first.screenName, '巴旦木公主_');
    expect(users.first.followersCount, 566000);
    expect(request!.uri.host, 'm.weibo.cn');
    expect(request!.queryParameters, {
      'containerid': '100103type=3&q=巴旦木公主',
      'page': 2,
    });
    expect(request!.extra['weiboMobileLogin'], isTrue);
  });

  test('已核对的网页用户卡优先于不可用移动会话，保留网页排名', () async {
    final requests = <RequestOptions>[];
    // 2026-10-11 官方原始 HTML 的必要结构，去掉追踪参数与签名图片地址。
    const html = '''
<div id="pl_user_feedList" class="card-wrap">
  <div class="card card-user-b s-brt1 card-user-b-padding">
    <div class="avator"><img src="https://example.com/avatar.jpg">
      <span title="微博个人认证" class="woo-icon-wrap"></span></div>
    <div class="info"><div><a href="//weibo.com/u/6130897928" class="name">巴旦木公主_</a></div>
      <p>颜值博主</p><p><span class="s-nobr">粉丝：56.6万</span></p></div>
  </div>
  <div class="card card-user-b"><div class="info">
    <a href="//weibo.com/u/6375259541" class="name">巴旦木公主</a>
    <p><span class="s-nobr">粉丝：5</span></p></div></div>
</div>
<div class="card-user-b"><a class="name" href="//weibo.com/u/999">侧栏候选</a></div>
''';
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response(
              requestOptions: options,
              data: options.uri.host == 's.weibo.com' ? html : {'ok': -100},
            ),
          );
        },
      ),
    );
    final users = await SearchRepository(client).searchUsers('巴旦木公主', page: 2);
    expect(users.map((u) => u.id), ['6130897928', '6375259541']);
    expect(users.first.screenName, '巴旦木公主_');
    expect(users.first.followersCount, 566000);
    expect(users.first.verified, isTrue);
    expect(users.first.verifiedReason, '颜值博主');
    expect(users.last.verified, isFalse);
    expect(users.last.followersCount, 5);
    expect(requests.single.uri.path, '/user');
    expect(requests.single.queryParameters, {'q': '巴旦木公主', 'page': 2});
    expect(requests.single.responseType, ResponseType.plain);
  });

  test('网页明确无结果不触发移动回退', () async {
    var calls = 0;
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          handler.resolve(
            Response(
              requestOptions: options,
              data: '<div class="card-no-result">没有找到相关用户</div>',
            ),
          );
        },
      ),
    );
    expect(await SearchRepository(client).searchUsers('没有匹配'), isEmpty);
    expect(calls, 1);
  });

  test('空关键词不请求；空结果和访客/鉴权/结构错误区分', () async {
    dynamic body = {
      'ok': 1,
      'data': {'cards': []},
    };
    var calls = 0;
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          handler.resolve(Response(requestOptions: options, data: body));
        },
      ),
    );
    final repo = SearchRepository(client);
    expect(await repo.searchUsers(' @ '), isEmpty);
    expect(calls, 0);
    expect(await repo.searchUsers('没有匹配'), isEmpty);
    for (final invalid in [
      '<html>Sina Visitor System</html>',
      {'ok': -100},
      {'ok': 1, 'data': {}},
    ]) {
      body = invalid;
      await expectLater(repo.searchUsers('巴旦木公主'), throwsFormatException);
    }
  });

  testWidgets('输入页用户直达使用正式结果，修改或清空输入立即移除旧账号', (tester) async {
    final repo = _SearchRepository(client);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          searchRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: SearchView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '巴旦木公主');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('巴旦木公主_'), findsOneWidget);
    expect(find.text('粉丝 5'), findsNothing);
    expect(repo.userPages, [1]);
    expect(repo.suggestionsCalls, 1);
    await tester.enterText(find.byType(TextField), '另一个名字');
    await tester.pump();
    expect(find.text('巴旦木公主_'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 500));
    expect(repo.userPages, [1]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('用户直达仅取官方排序前3个万粉账号，没有符合条件则隐藏', (tester) async {
    final repo = _SearchRepository(client);
    for (final popularCount in [0, 1, 2, 3, 5]) {
      repo.firstPageUsers = [
        const WeiboUserModel(
          id: 'low',
          screenName: '低粉账号',
          avatar: '',
          followersCount: 9999,
        ),
        for (var i = 0; i < popularCount; i++)
          WeiboUserModel(
            id: 'popular$i',
            screenName: '热门账号$i',
            avatar: '',
            followersCount: 10000 + i * 100000,
          ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            searchRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: SearchView()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '账号');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('低粉账号'), findsNothing);
      expect(
        find.text('用户直达'),
        popularCount == 0 ? findsNothing : findsOneWidget,
      );
      for (var i = 0; i < popularCount; i++) {
        expect(find.text('热门账号$i'), i < 3 ? findsOneWidget : findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('用户直达失败不回退错误联想账号，支持重试', (tester) async {
    final repo = _SearchRepository(client)..failUsers = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          searchRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: SearchView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '巴旦木公主');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('粉丝 5'), findsNothing);
    expect(find.text('用户直达'), findsNothing);
    repo.failUsers = false;
    await tester.tap(find.text('用户直达加载失败，点击重试'));
    await tester.pumpAndSettle();
    expect(find.text('巴旦木公主_'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('综合主账号和用户标签使用正式结果，不使用非空错误联想', (tester) async {
    final repo = _SearchRepository(client);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          searchRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: SearchResultsPage(keyword: '巴旦木公主')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('巴旦木公主_'), findsOneWidget);
    expect(find.text('粉丝 5'), findsNothing);
    await tester.tap(find.text('用户'));
    await tester.pumpAndSettle();
    expect(find.text('巴旦木公主_'), findsOneWidget);
    expect(repo.suggestionsCalls, 0);
    final refresh = tester.widget<EasyRefresh>(find.byType(EasyRefresh));
    expect(await refresh.onLoad!(), IndicatorResult.success);
    await tester.pumpAndSettle();
    expect(find.text('巴旦木公主_'), findsOneWidget);
    expect(find.text('下一页用户'), findsOneWidget);
    expect(repo.userPages, [1, 2]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('用户搜索失败显示重试，恢复后显示正式账号', (tester) async {
    final repo = _SearchRepository(client)..failUsers = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          searchRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: SearchResultsPage(keyword: '巴旦木公主')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('用户'));
    await tester.pumpAndSettle();
    expect(find.text('暂无相关用户'), findsNothing);
    repo.failUsers = false;
    await tester.tap(find.text('用户搜索暂时不可用，点击重试'));
    await tester.pumpAndSettle();
    expect(find.text('巴旦木公主_'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
