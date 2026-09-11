import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/feed/data/models/weibo_engagement_models.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/tweet_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('TweetCard renders author, rich text, and actions properly',
      (WidgetTester tester) async {
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
        avatar:
            'https://h5.sinaimg.cn/upload/2016/05/26/319/default_avatar.png',
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

  testWidgets('TweetCard displays expand button when isLongText is true',
      (WidgetTester tester) async {
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

  testWidgets('TweetCard shows the full restricted visibility on the timeline',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    const restrictedStatus = WeiboStatusModel(
      id: 'restricted-status',
      mid: 'restricted-status',
      textRaw: '仅粉丝可见的微博',
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      visibilityType: 10,
      user: WeiboUserModel(id: '100', screenName: '测试博主', avatar: ''),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TweetCard(status: restrictedStatus),
            ),
          ),
        ),
      ),
    );

    expect(find.text('仅粉丝可见'), findsOneWidget);
    expect(find.text('粉丝'), findsNothing);
  });

  testWidgets(
      'TweetCard trims timeline trailing whitespace before the action bar',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    const status = WeiboStatusModel(
      id: 'trailing-whitespace',
      mid: 'trailing-whitespace',
      textRaw: '正文最后一行\n\n\u200B\u200B\u200B',
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(
        id: '100',
        screenName: '测试用户',
        avatar: '',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: TweetCard(status: status)),
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == '正文最后一行',
      ),
      findsOneWidget,
    );
  });

  testWidgets('TweetCard renders official poll and hot topic cards',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    const status = WeiboStatusModel(
      id: 'engagement-status',
      mid: 'engagement-status',
      textRaw: '投票和热搜卡片测试',
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(id: '100', screenName: '测试用户', avatar: ''),
      poll: WeiboPollModel(
        id: 'vote-1',
        title: '你今年的购机预算是多少？',
        options: [
          WeiboPollOption(id: '1', text: '2000以内'),
          WeiboPollOption(id: '2', text: '2-4K'),
          WeiboPollOption(id: '3', text: '4-6K'),
          WeiboPollOption(id: '4', text: '6K以上'),
        ],
        voteUrl: 'https://vote.weibo.com/h5/index/index?vote_id=vote-1',
      ),
      hotTopic: WeiboHotTopicModel(
        word: 'iPhone18Pro售价曝光',
        discussionDescription: '6414新讨论',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: TweetCard(status: status)),
          ),
        ),
      ),
    );

    expect(find.text('你今年的购机预算是多少？'), findsOneWidget);
    expect(find.text('2000以内'), findsOneWidget);
    expect(find.text('查看全部选项 ›'), findsOneWidget);
    expect(find.text('查看结果'), findsOneWidget);
    await tester.tap(find.text('查看全部选项 ›'));
    await tester.pump();
    expect(find.text('收起'), findsOneWidget);
    expect(find.text('6K以上'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    final hotTopicText = tester.widget<Text>(find.textContaining('6414新讨论'));
    expect(hotTopicText.style?.fontSize, 13.0);
  });
}
