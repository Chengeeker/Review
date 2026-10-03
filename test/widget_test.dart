import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/features/detail/data/detail_repository.dart';
import 'package:review/features/drawer_features/presentation/browsing_history_page.dart';
import 'package:review/features/feed/data/feed_repository.dart';
import 'package:review/features/feed/data/models/weibo_engagement_models.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/tweet_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDetailRepository extends DetailRepository {
  _FakeDetailRepository(this.longText, StorageService storage)
      : super(WeiboDioClient(storage));

  final String? longText;
  int longTextRequestCount = 0;

  @override
  Future<String?> getLongText(String id) async {
    longTextRequestCount++;
    return longText;
  }
}

class _FakeFeedRepository extends FeedRepository {
  _FakeFeedRepository(this.statuses, StorageService storage)
      : super(WeiboDioClient(storage), storage);

  final List<WeiboStatusModel> statuses;
  int parseStatusesRequestCount = 0;

  @override
  Future<List<WeiboStatusModel>> parseStatuses(
    List rawStatuses, {
    bool resolveLongText = false,
  }) async {
    parseStatusesRequestCount++;
    return statuses;
  }
}

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

  testWidgets(
      'TweetCard does not prefetch long text; manual expand still works',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final paragraph = List.filled(55, '正文').join();
    final fullText = List.filled(8, paragraph).join('\n\n');
    final detailRepository = _FakeDetailRepository(fullText, storage);

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
          detailRepositoryProvider.overrideWithValue(detailRepository),
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

    expect(detailRepository.longTextRequestCount, 0);
    expect(find.text('展开全文'), findsOneWidget);
    expect(find.textContaining('这是被截断的长微博前部文本内容...'), findsOneWidget);

    await tester.tap(find.text('展开全文'));
    await tester.pumpAndSettle();

    expect(detailRepository.longTextRequestCount, 1);
    expect(find.text('收起'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == fullText,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'TweetCard hides expand control when fullTextRaw adds no visible content',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    const status = WeiboStatusModel(
      id: 'long-text-with-no-extra-content',
      mid: 'long-text-with-no-extra-content',
      isLongText: true,
      textRaw: '第一段\n\n第二段',
      fullTextRaw: '第一段\n第二段',
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(id: '100', screenName: '测试用户', avatar: ''),
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

    expect(find.text('展开全文'), findsNothing);
    expect(find.text('收起'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText() == '第一段\n第二段',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'TweetCard shows short full-text suffix without a pointless toggle',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    const fullText = '为自己加冕的，小小一圈光。';
    const status = WeiboStatusModel(
      id: 'long-text-suffix-fits-same-line',
      mid: 'long-text-suffix-fits-same-line',
      isLongText: true,
      textRaw: '为自己加冕',
      fullTextRaw: fullText,
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(id: '100', screenName: '测试用户', avatar: ''),
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

    expect(find.text('展开全文'), findsNothing);
    expect(find.text('收起'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == fullText,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'TweetCard shows a one-line tail directly instead of a pointless toggle',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    const paragraph = '这是一段用来测试自动微博长文阈值的正文内容';
    final preview = List.filled(6, paragraph).join();
    final fullText = '$preview，以及最后一点补充。';
    final status = WeiboStatusModel(
      id: 'long-text-single-line-tail',
      mid: 'long-text-single-line-tail',
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: TweetCard(status: status)),
          ),
        ),
      ),
    );

    expect(find.text('展开全文'), findsNothing);
    expect(find.text('收起'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == fullText,
      ),
      findsOneWidget,
    );
  });

  testWidgets('TweetCard collapses only genuinely long full text',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    final fullText = '第一段\n${List.filled(80, '第二段长内容').join()}。\n第三段完整内容。';
    final status = WeiboStatusModel(
      id: 'long-text-with-additional-content',
      mid: 'long-text-with-additional-content',
      isLongText: true,
      textRaw: '第一段',
      fullTextRaw: fullText,
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: const WeiboUserModel(id: '100', screenName: '测试用户', avatar: ''),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: TweetCard(status: status)),
          ),
        ),
      ),
    );

    expect(find.text('展开全文'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == '第一段',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('展开全文'));
    await tester.pump();

    expect(find.text('收起'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == fullText,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'TweetCard renders source-resolved moderate text without a collapse toggle',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    const paragraph = '这是一段处于微博长文阈值附近的示例正文内容';
    final preview = List.filled(8, paragraph).join('\n\n');
    const tailParagraph = '这部分是临界长度之后补充的完整正文内容';
    final fullText = '$preview${List.filled(5, tailParagraph).join()}';
    final detailRepository = _FakeDetailRepository(fullText, storage);
    final status = WeiboStatusModel(
      id: 'long-text-moderate-multiline-tail',
      mid: 'long-text-moderate-multiline-tail',
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          detailRepositoryProvider.overrideWithValue(detailRepository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: TweetCard(status: status)),
          ),
        ),
      ),
    );

    expect(detailRepository.longTextRequestCount, 0);
    expect(find.text('展开全文'), findsNothing);
    expect(find.text('收起'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == fullText,
      ),
      findsOneWidget,
    );
  });

  testWidgets('TweetCard hides expand control when source text is unchanged',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final detailRepository = _FakeDetailRepository('服务端返回的正文', storage);

    const status = WeiboStatusModel(
      id: 'long-text-fetch-same-content',
      mid: 'long-text-fetch-same-content',
      isLongText: true,
      textRaw: '服务端返回的正文',
      fullTextRaw: '服务端返回的正文',
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(id: '100', screenName: '测试用户', avatar: ''),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          detailRepositoryProvider.overrideWithValue(detailRepository),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: TweetCard(status: status)),
          ),
        ),
      ),
    );

    expect(detailRepository.longTextRequestCount, 0);
    expect(find.text('展开全文'), findsNothing);
    expect(find.text('收起'), findsNothing);
  });

  testWidgets(
      'TweetCard shows source-resolved suffix when it adds no rendered line',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    const fullText = '为自己加冕的，小小一圈光。';
    final detailRepository = _FakeDetailRepository(fullText, storage);

    const status = WeiboStatusModel(
      id: 'long-text-fetch-suffix-same-line',
      mid: 'long-text-fetch-suffix-same-line',
      isLongText: true,
      textRaw: '为自己加冕',
      fullTextRaw: fullText,
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(id: '100', screenName: '测试用户', avatar: ''),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          detailRepositoryProvider.overrideWithValue(detailRepository),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: TweetCard(status: status)),
          ),
        ),
      ),
    );

    expect(detailRepository.longTextRequestCount, 0);
    expect(find.text('展开全文'), findsNothing);
    expect(find.text('收起'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == fullText,
      ),
      findsOneWidget,
    );
  });

  testWidgets('TweetCard hides retweet expand control when content is equal',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    const retweet = WeiboStatusModel(
      id: 'retweet-long-text-with-no-extra-content',
      mid: 'retweet-long-text-with-no-extra-content',
      isLongText: true,
      textRaw: '转发正文',
      fullTextRaw: '转发正文\n',
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(id: '200', screenName: '原作者', avatar: ''),
    );
    const status = WeiboStatusModel(
      id: 'retweet-container',
      mid: 'retweet-container',
      textRaw: '转发了微博',
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(id: '100', screenName: '转发者', avatar: ''),
      retweetedStatus: retweet,
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

    expect(find.text('展开全文'), findsNothing);
    expect(find.text('收起'), findsNothing);
  });

  testWidgets('TweetCard renders source-resolved retweet without a toggle',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    const fullText = '这段自动微博的完整正文会在读取后直接展示，不需要再点击展开全文。';
    final detailRepository = _FakeDetailRepository(fullText, storage);
    const retweet = WeiboStatusModel(
      id: 'moderate-long-retweet',
      mid: 'moderate-long-retweet',
      isLongText: true,
      textRaw: '这段自动微博的完整正文会在读取后',
      fullTextRaw: fullText,
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(id: '200', screenName: '原作者', avatar: ''),
    );
    const status = WeiboStatusModel(
      id: 'moderate-retweet-container',
      mid: 'moderate-retweet-container',
      textRaw: '转发了微博',
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(id: '100', screenName: '转发者', avatar: ''),
      retweetedStatus: retweet,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          detailRepositoryProvider.overrideWithValue(detailRepository),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: TweetCard(status: status)),
          ),
        ),
      ),
    );
    expect(detailRepository.longTextRequestCount, 0);
    expect(find.text('展开全文'), findsNothing);
    expect(find.text('收起'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText() == '@原作者：$fullText',
      ),
      findsOneWidget,
    );
  });

  testWidgets('unresolved timeline long text never auto-loads in a card',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final detailRepository = _FakeDetailRepository('完整长微博正文', storage);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    const status = WeiboStatusModel(
      id: 'long-text-prefetch-visible-only',
      mid: 'long-text-prefetch-visible-only',
      isLongText: true,
      textRaw: '微博预览正文',
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(id: '100', screenName: '测试用户', avatar: ''),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          detailRepositoryProvider.overrideWithValue(detailRepository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scrollController,
              child: const Column(
                children: [
                  SizedBox(height: 1200),
                  TweetCard(status: status),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 2));
    expect(detailRepository.longTextRequestCount, 0);
    expect(find.text('微博预览正文'), findsOneWidget);
    expect(find.text('展开全文'), findsOneWidget);

    await tester.dragFrom(const Offset(190, 700), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(scrollController.offset, greaterThan(0));
    expect(detailRepository.longTextRequestCount, 0);
    expect(find.text('微博预览正文'), findsOneWidget);
    expect(find.text('展开全文'), findsOneWidget);
  });

  testWidgets(
      'source-resolved long text stays classified while the list scrolls',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final fullText = List.filled(80, '这是在列表展示之前已解析完成的长微博正文段落').join('\n');
    final detailRepository = _FakeDetailRepository(fullText, storage);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final status = WeiboStatusModel(
      id: 'long-text-response-during-fast-scroll',
      mid: 'long-text-response-during-fast-scroll',
      isLongText: true,
      textRaw: '微博预览正文',
      fullTextRaw: fullText,
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: const WeiboUserModel(id: '100', screenName: '测试用户', avatar: ''),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          detailRepositoryProvider.overrideWithValue(detailRepository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                children: [
                  TweetCard(status: status),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(detailRepository.longTextRequestCount, 0);
    expect(find.text('微博预览正文'), findsOneWidget);
    expect(find.text('展开全文'), findsOneWidget);

    final gesture = await tester.startGesture(const Offset(190, 700));
    await gesture.moveBy(const Offset(0, -180));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));

    expect(detailRepository.longTextRequestCount, 0);
    expect(find.text('微博预览正文'), findsOneWidget);
    expect(find.text('展开全文'), findsOneWidget);
  });

  testWidgets(
      'birthday smart-card greeting is inside the image on cards and details',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    const caption = '今天是我的生日 09月29日，来祝福我吧~';
    const status = WeiboStatusModel(
      id: 'birthday-detail-card',
      mid: 'birthday-detail-card',
      textRaw: caption,
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(id: '6367342728', screenName: '测试用户', avatar: ''),
      pics: [
        WeiboPicModel(
          pid: 'birthday-card',
          thumbnail: 'https://pc.us.sinaimg.cn/birthday-foreground.png',
          large: 'https://pc.us.sinaimg.cn/birthday-foreground.png',
          original: 'https://pc.us.sinaimg.cn/birthday-foreground.png',
          width: 16,
          height: 9,
          isWebpageCard: true,
          webpageCardBackgroundUrl:
              'https://pc.us.sinaimg.cn/birthday-background.png',
        ),
      ],
      urlStruct: [
        {
          'url_type': 39,
          'short_url': 'http://t.cn/birthday',
          'url_title': caption,
        },
      ],
    );

    for (final isDetail in [false, true]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TweetCard(status: status, isDetail: isDetail),
              ),
            ),
          ),
        ),
      );

      expect(find.text(caption), findsOneWidget);
      expect(
          find.byKey(const ValueKey('webpage-card-greeting')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('webpage-card-greeting')),
          matching: find.byType(AspectRatio),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'browsing history hydrates stale birthday cards like the timeline',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    const caption = '今天是我的生日 09月29日，来祝福我吧~';
    const staleStatus = WeiboStatusModel(
      id: '1234567890123456',
      mid: '1234567890123456',
      textRaw: 'http://t.cn/history-birthday',
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(id: '6367342728', screenName: '测试用户', avatar: ''),
      urlStruct: [
        {
          'url_type': 39,
          'short_url': 'http://t.cn/history-birthday',
          'url_title': caption,
        },
      ],
    );
    const normalStatus = WeiboStatusModel(
      id: '2234567890123456',
      mid: '2234567890123456',
      textRaw: '普通微博',
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(id: '200', screenName: '另一位用户', avatar: ''),
    );
    const hydratedStatus = WeiboStatusModel(
      id: '1234567890123456',
      mid: '1234567890123456',
      textRaw: 'http://t.cn/history-birthday',
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(id: '6367342728', screenName: '测试用户', avatar: ''),
      pics: [
        WeiboPicModel(
          pid: 'history-birthday-image',
          thumbnail: 'https://example.invalid/birthday-foreground.png',
          large: 'https://example.invalid/birthday-foreground.png',
          original: 'https://example.invalid/birthday-foreground.png',
          width: 16,
          height: 9,
          isWebpageCard: true,
          webpageCardBackgroundUrl:
              'https://example.invalid/birthday-background.png',
        ),
      ],
      urlStruct: [
        {
          'url_type': 39,
          'short_url': 'http://t.cn/history-birthday',
          'url_title': caption,
        },
      ],
    );
    final feedRepository = _FakeFeedRepository([hydratedStatus], storage);
    await storage.recordViewedStatusJson(
      normalStatus.id,
      jsonEncode(normalStatus.toJson()),
    );
    await storage.recordViewedStatusJson(
      staleStatus.id,
      jsonEncode(staleStatus.toJson()),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          feedRepositoryProvider.overrideWithValue(feedRepository),
        ],
        child: const MaterialApp(home: BrowsingHistoryPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(feedRepository.parseStatusesRequestCount, 1);
    expect(find.text(caption), findsOneWidget);
    expect(
      find.byKey(const ValueKey('webpage-card-greeting')),
      findsOneWidget,
    );
    final savedStatuses = storage.getBrowsingHistoryStatusJsons();
    expect(jsonDecode(savedStatuses[0])['id'], staleStatus.id);
    expect(jsonDecode(savedStatuses[1])['id'], normalStatus.id);
    expect(
      WeiboStatusModel.fromJson(jsonDecode(savedStatuses[0]))
          .pics
          .any((pic) => pic.isWebpageCard),
      isTrue,
    );
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
