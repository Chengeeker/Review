import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/tweet_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpCard(
  WidgetTester tester,
  String title, {
  bool showFeedReason = true,
  int visibility = 0,
  bool pinned = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService(await SharedPreferences.getInstance());
  final status = WeiboStatusModel.fromJson({
    'id': '123',
    'text_raw': '一条微博',
    'title': {'text': title},
    'visible': {'type': visibility},
    'isTop': pinned,
    'user': {'id': '456', 'screen_name': '原作者'},
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TweetCard(status: status, showFeedReason: showFeedReason),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Pinned cards retain the server reason alongside the badge', (
    tester,
  ) async {
    await pumpCard(tester, '关注的博主赞了这条微博', pinned: true);
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('关注的博主赞了这条微博'), findsOneWidget);
  });
  testWidgets('Special title badges do not duplicate as feed reasons', (
    tester,
  ) async {
    await pumpCard(tester, '热门');
    expect(find.text('热门'), findsOneWidget);
  });
  for (final reason in ['关注的博主关注了', '关注的博主赞了这条微博', '关注的博主评论了']) {
    testWidgets(
      'All-follow shows the server reason with public visibility: $reason',
      (tester) async {
        await pumpCard(tester, reason);
        expect(find.text(reason), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Latest keeps its existing public-card title behavior', (
    tester,
  ) async {
    const reason = '关注的博主赞了这条微博';
    await pumpCard(tester, reason, showFeedReason: false);
    expect(find.text(reason), findsNothing);
  });

  testWidgets('All-follow keeps visibility separate from the server reason', (
    tester,
  ) async {
    const reason = '关注的博主赞了这条微博';
    await pumpCard(tester, reason, visibility: 10);
    expect(find.text(reason), findsOneWidget);
    expect(find.text('仅粉丝可见'), findsOneWidget);
  });

  testWidgets(
    'Named recommendation sits above author with visibility styling',
    (tester) async {
      const reason = '你关注的博主某某某赞了这条微博';
      await pumpCard(tester, reason, visibility: 10);
      final reasonText = tester.widget<Text>(find.text(reason));
      final visibilityText = tester.widget<Text>(find.text('仅粉丝可见'));
      expect(reasonText.style?.fontSize, visibilityText.style?.fontSize);
      expect(reasonText.style?.color, visibilityText.style?.color);
      expect(
        tester.getBottomLeft(find.text(reason)).dy,
        lessThan(tester.getTopLeft(find.text('仅粉丝可见')).dy),
      );
      expect(
        tester.getBottomLeft(find.text('仅粉丝可见')).dy,
        lessThan(tester.getTopLeft(find.text('原作者')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'All-follow does not show a visibility title as a recommendation',
    (tester) async {
      await pumpCard(tester, '公开');
      expect(find.text('公开'), findsNothing);
    },
  );

  testWidgets('Long server reasons wrap and retain text containing 热门', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const reason = '关注的博主甲、关注的博主乙、关注的博主丙等多位博主赞了这条热门微博';
    await pumpCard(tester, reason);
    expect(find.text(reason), findsOneWidget);
    expect(find.text('热门'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
