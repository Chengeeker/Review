import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/tweet_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('timeline card state follows the status when rows reorder', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final statuses = ValueNotifier([
      _status('first', '第一条预览', '第一条完整正文'),
      _status('second', '第二条预览', '第二条完整正文'),
    ]);
    addTearDown(statuses.dispose);

    Widget buildTimeline() => ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
      child: MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: statuses,
            builder: (context, rows, _) {
              final indices = {
                for (var index = 0; index < rows.length; index++)
                  rows[index].id: index,
              };
              return CustomScrollView(
                slivers: [
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final status = rows[index];
                        return TweetCard(
                          key: ValueKey(status.id),
                          status: status,
                        );
                      },
                      childCount: rows.length,
                      findChildIndexCallback: (key) =>
                          key is ValueKey<String> ? indices[key.value] : null,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpWidget(buildTimeline());
    await tester.tap(find.text('展开全文').first);
    await tester.pump();
    expect(find.text('第一条完整正文'), findsOneWidget);

    statuses.value = [statuses.value.last, statuses.value.first];
    await tester.pump();

    expect(find.text('第一条完整正文'), findsOneWidget);
    expect(find.text('第二条预览'), findsOneWidget);
  });
}

WeiboStatusModel _status(String id, String preview, String fullText) =>
    WeiboStatusModel(
      id: id,
      mid: id,
      isLongText: true,
      textRaw: preview,
      fullTextRaw: fullText,
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: const WeiboUserModel(id: '100', screenName: '测试用户', avatar: ''),
    );
