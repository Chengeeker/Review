import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/constants/api_constants.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/detail/data/detail_repository.dart';
import 'package:review/features/detail/presentation/widgets/image_gallery_page.dart';
import 'package:review/features/feed/data/feed_repository.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/tweet_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _photoStatus({int count = 18, int? metadataCount}) => {
      'id': '5350504051770130',
      'mid': '5350504051770130',
      'created_at': '刚刚',
      'text_raw': '翻到了古早的记忆',
      'user': {'id': '5512873304', 'screen_name': '测试作者'},
      'isLongText': false,
      'continue_tag': '展开全文',
      'pic_num': count,
      'pic_ids': [for (var i = 0; i < count; i++) 'photo-$i'],
      'pic_infos': {
        for (var i = 0; i < (metadataCount ?? count); i++)
          'photo-$i': {
            'large': {'url': 'https://wx1.sinaimg.cn/large/photo-$i.jpg'},
          },
      },
    };

int _gridCount(WidgetTester tester) =>
    (tester.widget<GridView>(find.byType(GridView)).childrenDelegate
            as SliverChildBuilderDelegate)
        .childCount!;

Future<StorageService> _storage() async {
  SharedPreferences.setMockInitialValues({});
  return StorageService(await SharedPreferences.getInstance());
}

Future<void> _pumpCard(
  WidgetTester tester,
  StorageService storage,
  WeiboStatusModel status, {
  bool isDetail = false,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [storageServiceProvider.overrideWithValue(storage)],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TweetCard(status: status, isDetail: isDetail),
        ),
      ),
    ),
  ));
}

void main() {
  test('media continuation is not long text and all official PIDs survive', () {
    final status = WeiboStatusModel.fromJson(_photoStatus(metadataCount: 9));
    expect(status.isLongText, isFalse);
    expect(status.needsLongText, isFalse);
    expect(status.pics, hasLength(18));
    expect(status.pics.last.previewUrl,
        'https://wx1.sinaimg.cn/orj960/photo-17.jpg');
    final restored = WeiboStatusModel.fromJson(status.toJson());
    expect(
        restored.pics.map((pic) => pic.pid), status.pics.map((pic) => pic.pid));
    expect(restored.isLongText, isFalse);
    expect(
        WeiboStatusModel.fromJson({..._photoStatus(), 'isLongText': true})
            .needsLongText,
        isTrue);
  });

  test('short 18-photo feed does not request the text endpoint', () async {
    final storage = await _storage();
    final client = WeiboDioClient(storage);
    client.dio.interceptors.clear();
    var requestCount = 0;
    client.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        requestCount++;
        handler.resolve(Response<dynamic>(requestOptions: options, data: {}));
      },
    ));
    final rows = await FeedRepository(client, storage).parseStatuses(
      [_photoStatus()],
      resolveLongText: true,
    );
    expect(rows.single.pics, hasLength(18));
    expect(rows.single.needsLongText, isFalse);
    expect(requestCount, 0);
  });

  test('detail enrichment preserves 18 photos when mobile returns nine',
      () async {
    final storage = await _storage();
    final client = WeiboDioClient(storage);
    client.dio.interceptors.clear();
    final paths = <String>[];
    client.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        paths.add(options.path);
        final isDesktop = options.path == ApiConstants.statusDetail;
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          data: isDesktop ? _photoStatus() : {'data': _photoStatus(count: 9)},
        ));
      },
    ));
    final status =
        await DetailRepository(client).getStatusDetail('5350504051770130');
    expect(status, isNotNull);
    expect(status!.pics.map((pic) => pic.pid),
        [for (var i = 0; i < 18; i++) 'photo-$i']);
    expect(paths, hasLength(2));
    expect(paths, isNot(contains(ApiConstants.longText)));
  });

  test('feed engagement enrichment also preserves all desktop photos',
      () async {
    final storage = await _storage();
    final client = WeiboDioClient(storage);
    client.dio.interceptors.clear();
    client.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(Response<dynamic>(
        requestOptions: options,
        data: {'data': _photoStatus(count: 9)},
      )),
    ));
    final rows = await FeedRepository(client, storage).parseStatuses([
      {..._photoStatus(), 'is_vote': true},
    ]);
    expect(rows.single.pics.map((pic) => pic.pid),
        [for (var i = 0; i < 18; i++) 'photo-$i']);
  });

  for (final retweeted in [false, true]) {
    testWidgets('list shows nine with overflow overlay, retweet=$retweeted',
        (tester) async {
      final storage = await _storage();
      final original = WeiboStatusModel.fromJson(_photoStatus());
      final status = retweeted
          ? original.copyWith(
              id: 'wrapper', pics: [], retweetedStatus: original)
          : original;
      await _pumpCard(tester, storage, status);
      expect(_gridCount(tester), 9);
      expect(find.text('展开全文'), findsNothing);
      expect(find.text('+9'), findsOneWidget);
      final overlay = find.byKey(ValueKey('media-overflow-${original.id}'));
      expect(overlay, findsOneWidget);
      await tester.tapAt(tester.getCenter(overlay));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final gallery =
          tester.widget<ImageGalleryPage>(find.byType(ImageGalleryPage));
      expect(gallery.pics, hasLength(18));
      expect(gallery.initialIndex, 8);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'detail immediately displays eighteen photos, retweet=$retweeted',
        (tester) async {
      final storage = await _storage();
      final original = WeiboStatusModel.fromJson(_photoStatus());
      final status = retweeted
          ? original.copyWith(
              id: 'wrapper',
              pics: [],
              isLongText: false,
              retweetedStatus: original)
          : original;
      await _pumpCard(tester, storage, status, isDetail: true);
      expect(_gridCount(tester), 18);
      expect(find.text('展开全文'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('collapsed grid still opens the complete gallery',
      (tester) async {
    final storage = await _storage();
    final status = WeiboStatusModel.fromJson(_photoStatus());
    await _pumpCard(tester, storage, status);
    final photo = find
        .descendant(
          of: find.byType(GridView),
          matching: find.byWidgetPredicate(
              (widget) => widget is GestureDetector && widget.onTap != null),
        )
        .first;
    await tester.tap(photo);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final gallery =
        tester.widget<ImageGalleryPage>(find.byType(ImageGalleryPage));
    expect(gallery.pics, hasLength(18));
    expect(gallery.initialIndex, 0);
  });

  testWidgets('text-only expansion follows media and does not expand grid',
      (tester) async {
    final storage = await _storage();
    final fullText = List.filled(10, List.filled(50, '长文').join()).join('\n');
    final status = WeiboStatusModel.fromJson(_photoStatus()).copyWith(
      isLongText: true,
      fullTextRaw: fullText,
    );
    await _pumpCard(tester, storage, status);
    final body = find.byWidgetPredicate((widget) =>
        widget is RichText && widget.text.toPlainText() == status.textRaw);
    expect(body, findsOneWidget);
    expect(find.text('展开全文'), findsOneWidget);
    final button = find.text('展开全文');
    expect(tester.getTopLeft(button).dy,
        greaterThan(tester.getBottomLeft(find.byType(GridView)).dy));
    await tester.tap(button);
    await tester.pump();
    expect(_gridCount(tester), 9);
    expect(body, findsNothing);
    expect(find.text('收起'), findsOneWidget);
  });

  for (final retweeted in [false, true]) {
    testWidgets(
        'legacy short multi-photo caption has no fake text toggle, retweet=$retweeted',
        (tester) async {
      final original =
          WeiboStatusModel.fromJson(_photoStatus()).copyWith(isLongText: true);
      final status = retweeted
          ? original.copyWith(
              id: 'wrapper',
              pics: [],
              isLongText: false,
              retweetedStatus: original)
          : original;
      await _pumpCard(tester, await _storage(), status);
      expect(find.text('展开全文'), findsNothing);
      expect(find.text('+9'), findsOneWidget);
    });
  }

  testWidgets('nine photos have no media expansion control', (tester) async {
    await _pumpCard(tester, await _storage(),
        WeiboStatusModel.fromJson(_photoStatus(count: 9)));
    expect(_gridCount(tester), 9);
    expect(find.text('展开全文'), findsNothing);
  });
}
