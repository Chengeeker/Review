import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/core/design_system/components/review_frosted_app_bar.dart';
import 'package:review/features/drawer_features/presentation/chaohua_center_page.dart';
import 'package:review/features/search/data/search_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSearchRepository extends SearchRepository {
  _FakeSearchRepository(super.client);

  @override
  Future<List<SearchChaohuaItem>> searchChaohua(
    String keyword, {
    int page = 1,
  }) async => page == 1
      ? const [
          SearchChaohuaItem(
            title: '测试超话',
            pageId: 'test',
            image: '',
            description: '',
          ),
        ]
      : const [];
}

void main() {
  testWidgets('超话固定内容属于磨砂顶栏，列表视口覆盖到顶栏后方', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchRepositoryProvider.overrideWithValue(
            _FakeSearchRepository(WeiboDioClient(storage)),
          ),
        ],
        child: const MaterialApp(home: ChaohuaCenterPage()),
      ),
    );
    await tester.pumpAndSettle();

    final appBarFinder = find.byType(ReviewFrostedAppBar);
    expect(
      find.descendant(of: appBarFinder, matching: find.byType(TextField)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBarFinder, matching: find.text('推荐')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBarFinder, matching: find.text('测试超话')),
      findsNothing,
    );
    expect(find.text('测试超话'), findsOneWidget);

    final appBar = tester.widget<ReviewFrostedAppBar>(appBarFinder);
    expect(appBar.bottom?.preferredSize.height, 108);
    expect(appBar.showBottomBorder, isFalse);
    expect(
      find.descendant(
        of: appBarFinder,
        matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 8,
        ),
      ),
      findsOneWidget,
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.extendBodyBehindAppBar, isTrue);
    final topicListFinder = find.byWidgetPredicate(
      (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
    );
    final topicList = tester.widget<ListView>(topicListFinder);
    expect(
      topicList.padding,
      const EdgeInsets.fromLTRB(16, kToolbarHeight + 108 + 4, 16, 24),
    );
    final viewportFinder = find.descendant(
      of: topicListFinder,
      matching: find.byType(Viewport),
    );
    expect(viewportFinder, findsOneWidget);
    expect(tester.getTopLeft(viewportFinder).dy, 0);
  });
}
