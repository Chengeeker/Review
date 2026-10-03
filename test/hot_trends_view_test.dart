import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/core/theme/theme_provider.dart';
import 'package:review/features/search/data/search_repository.dart';
import 'package:review/features/search/presentation/hot_trends_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSearchRepository extends SearchRepository {
  final List<HotSearchItem> items;
  final Map<String, List<HotSearchItem>> itemsByCategory;
  final List<String> requestedCategories = [];

  _FakeSearchRepository(
    super.client, {
    this.items = const [],
    this.itemsByCategory = const {},
  });

  @override
  Future<List<HotSearchItem>> getCategoryHotSearch(String categoryKey) async {
    requestedCategories.add(categoryKey);
    return itemsByCategory[categoryKey] ?? items;
  }
}

void main() {
  testWidgets('微博热搜顶栏的选中和未选中文字均跟随字重设置', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final repository = _FakeSearchRepository(WeiboDioClient(storage));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          searchRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: HotTrendsView()),
      ),
    );

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.labelStyle?.fontWeight, FontWeight.w600);
    expect(tabBar.unselectedLabelStyle?.fontWeight, FontWeight.normal);
  });

  testWidgets('微博热搜顶栏直接响应最粗字体设置', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final themeNotifier = ThemeNotifier(storage);
    await themeNotifier.setUseCustomFontWeight(true);
    await themeNotifier.setCustomFontWeightDelta(300);
    final repository = _FakeSearchRepository(WeiboDioClient(storage));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          themeProvider.overrideWith((ref) => themeNotifier),
          searchRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: HotTrendsView()),
      ),
    );

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.labelStyle?.fontWeight, FontWeight.w900);
    expect(tabBar.unselectedLabelStyle?.fontWeight, FontWeight.w700);
  });

  testWidgets('热搜讨论数显示在词条右侧且保留精确数字', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final repository = _FakeSearchRepository(
      WeiboDioClient(storage),
      items: const [
        HotSearchItem(rank: 1, word: '测试热搜词条', num: 12345),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          searchRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: HotTrendsView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('12345 讨论'), findsWidgets);
    expect(find.text('1.2万 讨论'), findsNothing);
  });

  testWidgets('热搜底栏单击回顶，双击只刷新当前分类', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final repository = _FakeSearchRepository(
      WeiboDioClient(storage),
      itemsByCategory: {
        'hot': List.generate(
          40,
          (index) => HotSearchItem(
            rank: index + 1,
            word: 'hot item $index',
            num: 0,
          ),
        ),
        for (final category in [
          'mine',
          'ent',
          'social',
          'tech',
          'life',
          'sports',
          'acg',
        ])
          category: [
            HotSearchItem(rank: 1, word: '$category item', num: 0),
          ],
      },
    );
    final hotTrendsKey = GlobalKey<HotTrendsViewState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          searchRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(home: HotTrendsView(key: hotTrendsKey)),
      ),
    );
    await tester.pumpAndSettle();

    repository.requestedCategories.clear();
    await tester.drag(find.text('hot item 0'), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('hot item 0'), findsNothing);

    hotTrendsKey.currentState!.handleBottomBarSingleTap();
    await tester.pumpAndSettle();
    expect(find.text('hot item 0'), findsOneWidget);
    expect(repository.requestedCategories, isEmpty);

    hotTrendsKey.currentState!.handleBottomBarDoubleTap();
    await tester.pumpAndSettle();
    expect(repository.requestedCategories, ['hot']);
  });

  testWidgets('热搜顶栏双击离顶回顶，在顶部刷新当前分类', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final repository = _FakeSearchRepository(
      WeiboDioClient(storage),
      itemsByCategory: {
        'hot': List.generate(
          40,
          (index) => HotSearchItem(
            rank: index + 1,
            word: 'hot item $index',
            num: 0,
          ),
        ),
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          searchRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: HotTrendsView()),
      ),
    );
    await tester.pumpAndSettle();

    repository.requestedCategories.clear();
    await tester.drag(find.text('hot item 0'), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('hot item 0'), findsNothing);

    await tester.tap(find.text('微博热搜'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('微博热搜'));
    await tester.pumpAndSettle();
    expect(find.text('hot item 0'), findsOneWidget);
    expect(repository.requestedCategories, isEmpty);

    await tester.tap(find.text('微博热搜'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('微博热搜'));
    await tester.pumpAndSettle();
    expect(repository.requestedCategories, ['hot']);
  });
}
