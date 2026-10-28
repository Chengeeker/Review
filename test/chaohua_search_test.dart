import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/search/data/search_repository.dart';
import 'package:review/features/search/presentation/chaohua_search_page.dart';
import 'package:review/features/drawer_features/presentation/chaohua_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const topic = '100808aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const other = '100808bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  testWidgets('search button is left of share and opens this topic scope', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final client = WeiboDioClient(storage);
    client.dio.interceptors.clear();
    client.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, data: <String, dynamic>{'items': []}));
    }));
    await tester.pumpWidget(ProviderScope(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      weiboDioClientProvider.overrideWithValue(client),
    ], child: const MaterialApp(home: ChaohuaDetailPage(containerid: topic, title: '社区'))));
    await tester.pumpAndSettle();
    final search = find.byTooltip('搜索本超话');
    final share = find.byTooltip('分享超话');
    expect(tester.getCenter(search).dx, lessThan(tester.getCenter(share).dx));
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(tester.widget<ChaohuaSearchPage>(find.byType(ChaohuaSearchPage)).pageId, topic);
    expect(find.text('仅搜索「社区」内的帖子'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('scope cannot be inherited from a retweeted post', () {
    expect(SearchRepository.isChaohuaPost({'url_struct': [{'url_title': topic}]}, topic), isFalse);
    expect(SearchRepository.isChaohuaPost({'title_source': {'url':
      'sinaweibo://pageinfo?pageid=$topic&extparam=社区'}}, topic), isTrue);
    expect(
      SearchRepository.isChaohuaPost({
        'retweeted_status': {
          'url_struct': [
            {'page_id': topic},
          ],
        },
      }, topic),
      isFalse,
    );
    expect(
      SearchRepository.isChaohuaPost({
        'url_struct': [
          {'page_id': topic},
        ],
      }, topic),
      isTrue,
    );
  });

  test(
    'scoped search excludes recommendations and foreign topic results',
    () async {
      SharedPreferences.setMockInitialValues({});
      final client = WeiboDioClient(
        StorageService(await SharedPreferences.getInstance()),
      );
      client.dio.interceptors.clear();
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            if (request.uri.host == 's.weibo.com') {
              expect(request.queryParameters['q'], '社区 合影');
              handler.resolve(
                Response(
                  requestOptions: request,
                  data:
                      '<div id="pl_feedlist_index"><div class="card-wrap" mid="1"></div>'
                      '<div class="card-wrap" mid="2"></div><div class="card-wrap" mid="3"></div></div>'
                      '<a class="next" href="?page=2"></a>',
                ),
              );
            } else {
              final id = request.queryParameters['id'];
              handler.resolve(
                Response(
                  requestOptions: request,
                  data: {
                    'id': id,
                    'text_raw': id == '3' ? '无关热门推荐' : '合影',
                    'created_at': '刚刚',
                    'user': {'id': 'owner', 'screen_name': 'owner'},
                    'url_struct': [
                      {'page_id': id == '2' ? other : topic},
                    ],
                    if (id == '2')
                      'retweeted_status': {
                        'url_struct': [
                          {'page_id': topic},
                        ],
                      },
                  },
                ),
              );
            }
          },
        ),
      );
      final result = await SearchRepository(client)
          .searchChaohuaPosts(pageId: topic, title: '社区超话', keyword: '合影');
      expect(result.statuses.map((s) => s.id), ['1']);
      expect(result.hasMore, isTrue);
      await expectLater(
        SearchRepository(client)
            .searchChaohuaPosts(pageId: 'invalid', title: '社区', keyword: '合影'),
        throwsStateError,
      );
    },
  );
}
