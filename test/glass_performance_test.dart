import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/design_system/components/review_navigation_bar.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/feed/data/feed_repository.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/home/presentation/main_scaffold.dart';
import 'package:review/features/search/data/search_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFeedRepo extends FeedRepository {
  _MockFeedRepo(super.client, super.storage);

  @override
  Future<UserGroupsResult> getUserGroups() async => const UserGroupsResult();

  @override
  Future<TimelineResult> getTimeline({
    required String category,
    String? userUid,
    int page = 1,
    String maxId = '0',
    String sinceId = '0',
  }) async => TimelineResult(
        statuses: [
          WeiboStatusModel.fromJson({
            'id': '101',
            'text': '性能测试时间线微博条目 1',
            'user': {'id': '1', 'screen_name': '测试博主 1'},
          }),
          WeiboStatusModel.fromJson({
            'id': '102',
            'text': '性能测试时间线微博条目 2',
            'user': {'id': '2', 'screen_name': '测试博主 2'},
          }),
        ],
        hasMore: false,
      );
}

class _MockSearchRepo extends SearchRepository {
  _MockSearchRepo(super.client);

  @override
  Future<List<HotSearchItem>> getCategoryHotSearch(String categoryKey) async =>
      [];
}

Future<void> _mountScaffold(
  WidgetTester tester, {
  required bool useLiquidGlass,
}) async {
  SharedPreferences.setMockInitialValues({
    'use_floating_nav_bar': true,
    'use_liquid_glass_effect': useLiquidGlass,
  });
  final storage = StorageService(await SharedPreferences.getInstance());
  final client = WeiboDioClient(storage);
  addTearDown(() => client.dio.close(force: true));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        weiboDioClientProvider.overrideWithValue(client),
        feedRepositoryProvider.overrideWithValue(_MockFeedRepo(client, storage)),
        searchRepositoryProvider.overrideWithValue(_MockSearchRepo(client)),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const MainScaffold(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('measure tab switching frame timings with and without liquid glass',
      (tester) async {
    // 1. 测试普通模式（无液态玻璃）
    await _mountScaffold(tester, useLiquidGlass: false);
    final navWithoutGlass =
        tester.widget<ReviewNavigationBar>(find.byType(ReviewNavigationBar));

    final stopwatchWithoutGlass = Stopwatch()..start();
    navWithoutGlass.onSelected(1);
    await tester.pump();
    // 模拟 120Hz 下 260ms 的帧步进（约 31 帧）
    for (var i = 0; i < 31; i++) {
      await tester.pump(const Duration(microseconds: 8333));
    }
    await tester.pumpAndSettle();
    stopwatchWithoutGlass.stop();
    final durationWithoutGlass = stopwatchWithoutGlass.elapsedMicroseconds;

    debugPrint(
        '[Benchmark] Tab switch WITHOUT liquid glass (31 frames): ${durationWithoutGlass / 1000} ms (avg: ${durationWithoutGlass / 31 / 1000} ms/frame)');

    // 清理
    await tester.pumpWidget(const SizedBox.shrink());

    // 2. 测试开启液态玻璃
    await _mountScaffold(tester, useLiquidGlass: true);
    final navWithGlass =
        tester.widget<ReviewNavigationBar>(find.byType(ReviewNavigationBar));

    final stopwatchWithGlass = Stopwatch()..start();
    navWithGlass.onSelected(1);
    await tester.pump();
    for (var i = 0; i < 31; i++) {
      await tester.pump(const Duration(microseconds: 8333));
    }
    await tester.pumpAndSettle();
    stopwatchWithGlass.stop();
    final durationWithGlass = stopwatchWithGlass.elapsedMicroseconds;

    debugPrint(
        '[Benchmark] Tab switch WITH liquid glass (31 frames): ${durationWithGlass / 1000} ms (avg: ${durationWithGlass / 31 / 1000} ms/frame)');

    expect(find.byType(MainScaffold), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('liquid glass tab click slides indicator smoothly and tap switches tabs',
      (tester) async {
    await _mountScaffold(tester, useLiquidGlass: true);
    expect(find.byType(MainScaffold), findsOneWidget);

    // Click on HotTrends tab (index 1)
    final hotTrendsTab = find.text('热搜').first;
    expect(hotTrendsTab, findsOneWidget);
    await tester.tap(hotTrendsTab);
    await tester.pump();
    // Simulate transition
    for (var i = 0; i < 31; i++) {
      await tester.pump(const Duration(microseconds: 8333));
    }
    await tester.pumpAndSettle();

    final nav = tester.widget<ReviewNavigationBar>(find.byType(ReviewNavigationBar));
    expect(nav.selectedIndex, 1);
    expect(tester.takeException(), isNull);

    // Long press and drag to settings tab (index 2)
    final gesture = await tester.startGesture(tester.getCenter(hotTrendsTab));
    // Hold for > 220ms to enter jelly drag mode
    await tester.pump(const Duration(milliseconds: 250));
    final settingsTab = find.text('设置').first;
    await gesture.moveTo(tester.getCenter(settingsTab));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

