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

  _FakeSearchRepository(super.client, {this.items = const []});

  @override
  Future<List<HotSearchItem>> getCategoryHotSearch(String categoryKey) async =>
      items;
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
}
