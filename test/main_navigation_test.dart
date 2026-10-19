import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassTabBar;
import 'package:liquid_glass_widgets/utils/draggable_indicator_physics.dart';
import 'package:review/core/design_system/components/review_navigation_bar.dart';
import 'package:review/core/utils/haptic_feedback_util.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/feed/presentation/feed_controller.dart';
import 'package:review/features/feed/data/feed_repository.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/group_dropdown_panel.dart';
import 'package:review/features/home/presentation/main_scaffold.dart';
import 'package:review/features/search/data/search_repository.dart';
import 'package:review/features/search/presentation/hot_trends_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Feed extends FeedRepository {
  _Feed(super.client, super.storage, {this.statusCount = 1});

  final int statusCount;
  int timelineRequests = 0;

  @override
  Future<UserGroupsResult> getUserGroups() async => const UserGroupsResult();

  @override
  Future<TimelineResult> getTimeline({
    required String category,
    String? userUid,
    int page = 1,
    String maxId = '0',
    String sinceId = '0',
  }) async {
    timelineRequests++;
    return TimelineResult(
      statuses: List.generate(
        statusCount,
        (index) => WeiboStatusModel.fromJson({
          'id': '${index + 1}',
          'text': '静态时间线 $index',
          'user': {'id': '1', 'screen_name': '作者'},
        }),
      ),
      hasMore: false,
    );
  }
}

class _Search extends SearchRepository {
  _Search(super.client);

  @override
  Future<List<HotSearchItem>> getCategoryHotSearch(String categoryKey) async =>
      [];
}

Future<_Feed> _mount(WidgetTester tester, {bool reduceMotion = false, int statusCount = 1}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService(await SharedPreferences.getInstance());
  final client = WeiboDioClient(storage);
  final feed = _Feed(client, storage, statusCount: statusCount);
  addTearDown(() => client.dio.close(force: true));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        weiboDioClientProvider.overrideWithValue(client),
        feedRepositoryProvider.overrideWithValue(feed),
        searchRepositoryProvider.overrideWithValue(_Search(client)),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: const MainScaffold(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return feed;
}

void main() {
  testWidgets('timeline app bar title single tap scrolls to top and double tap refreshes', (tester) async {
    final feed = await _mount(tester, statusCount: 50);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MainScaffold)),
    );
    await container
        .read(feedControllerProvider.notifier)
        .setCategory('recommend', '推荐');
    await tester.pumpAndSettle();
    final scrollController = container
        .read(timelineScrollProvider.notifier)
        .scrollController!;

    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(scrollController.offset, greaterThan(0));
    final requestsBeforeSingleTap = feed.timelineRequests;
    await tester.tap(find.text('推荐').first);
    await tester.pumpAndSettle();
    expect(scrollController.offset, 0);
    expect(feed.timelineRequests, requestsBeforeSingleTap);

    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(scrollController.offset, greaterThan(0));
    final requestsBeforeDoubleTap = feed.timelineRequests;
    await tester.tap(find.text('推荐').first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('推荐').first);
    await tester.pumpAndSettle();
    expect(scrollController.offset, 0);
    expect(feed.timelineRequests, requestsBeforeDoubleTap + 1);

    await tester.tap(find.byIcon(Icons.arrow_drop_down_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(GroupDropdownPanel), findsOneWidget);
  });

  testWidgets('tab translation reuses page paint at 120 Hz-sized steps', (
    tester,
  ) async {
    await _mount(tester);
    void select(int index) => tester
        .widget<ReviewNavigationBar>(find.byType(ReviewNavigationBar))
        .onSelected(index);
    select(1);
    await tester.pumpAndSettle();
    final hotPage = tester.element(find.byType(HotTrendsView));
    final source = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('main-tab-paint-1')),
    );
    select(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final destination = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('main-tab-paint-2')),
    );
    source.debugResetMetrics();
    destination.debugResetMetrics();
    final initialPosition = source.localToGlobal(Offset.zero).dx;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(microseconds: 8333));
    }
    expect(source.localToGlobal(Offset.zero).dx, lessThan(initialPosition));
    expect(source.debugSymmetricPaintCount, 0);
    expect(destination.debugSymmetricPaintCount, 0);
    expect(source.debugAsymmetricPaintCount, greaterThan(0));
    expect(destination.debugAsymmetricPaintCount, greaterThan(0));
    // Retarget before completion, retaining the same mounted page state.
    select(0);
    await tester.pump(const Duration(microseconds: 8333));
    select(1);
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(HotTrendsView)), same(hotPage));
    expect(
      tester
          .widget<ReviewNavigationBar>(find.byType(ReviewNavigationBar))
          .selectedIndex,
      1,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'reduced motion switches tabs immediately and keeps the indicator in bounds',
    (tester) async {
      await _mount(tester, reduceMotion: true);
      final nav = tester.widget<ReviewNavigationBar>(
        find.byType(ReviewNavigationBar),
      );
      nav.onSelected(2);
      await tester.pump();
      expect(find.text('偏好与功能'), findsOneWidget);
      expect(find.byType(HotTrendsView), findsNothing);
      await tester.pumpAndSettle();
      final indicator = find.descendant(
        of: find.byType(AnimatedSlide),
        matching: find.byType(DecoratedBox),
      );
      final slideRect = tester.getRect(find.byType(AnimatedSlide));
      final indicatorRect = tester.getRect(indicator);
      expect(indicatorRect.width, closeTo(slideRect.width, .01));
      expect(
        indicatorRect.left - slideRect.left,
        closeTo(slideRect.width * 2, .01),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'liquid glass forwards single and double taps on the selected tab',
    (tester) async {
      final hapticCalls = <MethodCall>[];
      final originalHapticsEnabled = HapticFeedbackUtil.isEnabled;
      HapticFeedbackUtil.isEnabled = true;
      HapticFeedbackUtil.resetForTesting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            hapticCalls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
        HapticFeedbackUtil.isEnabled = originalHapticsEnabled;
        HapticFeedbackUtil.resetForTesting();
      });
      SharedPreferences.setMockInitialValues({
        StorageService.keyUseFloatingNavBar: true,
        StorageService.keyUseLiquidGlass: true,
      });
      final storage = StorageService(await SharedPreferences.getInstance());
      final selectedTabs = <int>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: MaterialApp(
            home: Scaffold(
              bottomNavigationBar: ReviewNavigationBar(
                selectedIndex: 0,
                onSelected: selectedTabs.add,
                hasBottomInset: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final barRect = tester.getRect(find.byType(GlassTabBar));
      final timelineTabCenter = Offset(
        barRect.left + barRect.width / 6,
        barRect.center.dy,
      );
      await tester.tapAt(timelineTabCenter);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.tapAt(timelineTabCenter);
      await tester.pump();
      expect(selectedTabs, [0, 0]);
      await tester.pump();
      expect(
        hapticCalls.where((call) => call.method == 'HapticFeedback.vibrate'),
        hasLength(2),
      );

      final gesture = await tester.startGesture(timelineTabCenter);
      await tester.pump(const Duration(milliseconds: 250));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selectedTabs, [0, 0]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('jelly transform produces identity matrix without deformation when maxDistortion is 0', () {
    // When pinchStrength / maxDistortion is 0, velocity should not cause any squash or stretch.
    final zeroDistortion = DraggableIndicatorPhysics.buildJellyTransform(
      velocity: const Offset(800, 0),
      maxDistortion: 0.0,
      velocityScale: 10,
    );
    // Values on main diagonal must be strictly 1.0 (no scale / squash / stretch).
    expect(zeroDistortion.storage[0], closeTo(1.0, 0.0001)); // scaleX
    expect(zeroDistortion.storage[5], closeTo(1.0, 0.0001)); // scaleY

    // When maxDistortion is enabled (>0), high velocity squashes X and stretches Y.
    final withDistortion = DraggableIndicatorPhysics.buildJellyTransform(
      velocity: const Offset(800, 0),
      maxDistortion: 0.8,
      velocityScale: 10,
    );
    expect(withDistortion.storage[0], lessThan(1.0)); // squashX
    expect(withDistortion.storage[5], greaterThan(1.0)); // stretchY
  });
}
