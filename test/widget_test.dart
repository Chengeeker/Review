import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/tweet_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('TweetCard renders author, rich text, and actions properly', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    const testStatus = WeiboStatusModel(
      id: '123456',
      mid: '123456',
      textRaw: '这是一条纯原生 Material You 微博卡片测试 #科技# @测试用户',
      createdAt: '刚刚',
      source: '来自 Share Lite',
      repostsCount: 15,
      commentsCount: 30,
      attitudesCount: 99,
      user: WeiboUserModel(
        id: '999',
        screenName: '测试博主小助手',
        avatar: 'https://h5.sinaimg.cn/upload/2016/05/26/319/default_avatar.png',
        verified: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TweetCard(status: testStatus),
            ),
          ),
        ),
      ),
    );

    expect(find.text('测试博主小助手'), findsOneWidget);
    expect(find.textContaining('来自 Share Lite'), findsOneWidget);
    expect(find.textContaining('科技'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('99'), findsOneWidget);
  });

  testWidgets('TweetCard displays expand button when isLongText is true', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    const longStatus = WeiboStatusModel(
      id: '5337364026364289',
      mid: '5337364026364289',
      mblogid: 'RfG0yqHDP',
      isLongText: true,
      textRaw: '这是被截断的长微博前部文本内容...',
      createdAt: '刚刚',
      source: '来自 微博网页版',
      repostsCount: 10,
      commentsCount: 20,
      attitudesCount: 50,
      user: WeiboUserModel(
        id: '6074356560',
        screenName: 'KPL赛事官方',
        avatar: 'https://h5.sinaimg.cn/default.png',
        verified: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TweetCard(status: longStatus),
            ),
          ),
        ),
      ),
    );

    expect(find.text('展开全文'), findsOneWidget);
    expect(find.textContaining('这是被截断的长微博前部文本内容...'), findsOneWidget);
  });
}
