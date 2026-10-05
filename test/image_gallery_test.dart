import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/features/detail/presentation/widgets/image_gallery_page.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';

const galleryTestPic = WeiboPicModel(
  pid: 'gallery-test',
  thumbnail: 'https://example.com/gallery-test.jpg',
  large: 'https://example.com/gallery-test.jpg',
  original: 'https://example.com/gallery-test.jpg',
);

class RecordingNavigatorObserver extends NavigatorObserver {
  String? poppedRouteName;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    poppedRouteName = route.settings.name;
    super.didPop(route, previousRoute);
  }
}

void main() {
  testWidgets('gallery pairs its fullscreen image with the source thumbnail',
      (tester) async {
    final heroScope = Object();
    final heroTag = ImageGalleryHeroTag.forPic(
      scope: heroScope,
      index: 0,
      pic: galleryTestPic,
    );
    final sourceThumbnail = find.byKey(const ValueKey('hero-source-thumbnail'));

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: GestureDetector(
              key: const ValueKey('hero-source-thumbnail'),
              onTap: () => Navigator.of(context).push<void>(
                PageRouteBuilder<void>(
                  opaque: false,
                  barrierColor: Colors.black,
                  transitionDuration: const Duration(milliseconds: 220),
                  pageBuilder: (_, __, ___) => ImageGalleryPage(
                    pics: const [galleryTestPic],
                    initialIndex: 0,
                    statusId: 'hero-test',
                    heroScope: heroScope,
                  ),
                ),
              ),
              child: ImageGalleryHeroThumbnail(
                scope: heroScope,
                index: 0,
                pic: galleryTestPic,
                child: const SizedBox(
                  width: 80,
                  height: 80,
                  child: ColoredBox(color: Colors.blue),
                ),
              ),
            ),
          ),
        ),
      ),
    ));

    Finder matchingHero() => find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == heroTag,
        );

    expect(matchingHero(), findsOneWidget);
    await tester.tap(sourceThumbnail);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(matchingHero(), findsWidgets);
    // Gallery networking/gesture widgets may keep frames scheduled, so finish
    // the 220 ms route transition with bounded pumps instead of settling all.
    await tester.pump(const Duration(milliseconds: 250));
    expect(matchingHero(), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('thumbnail decoding preserves aspect ratio before cover crop',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: ImageGalleryPage(
      pics: [galleryTestPic, galleryTestPic],
      initialIndex: 0,
      statusId: 'crop',
    )));
    final images = tester.widgetList<ExtendedImage>(find.descendant(
      of: find.byKey(const ValueKey('gallery-thumbnail-strip')),
      matching: find.byType(ExtendedImage),
    ));
    expect(images, isNotEmpty);
    for (final image in images) {
      expect(image.fit, BoxFit.cover);
      final provider = image.image as ExtendedResizeImage;
      expect(provider.width, 160);
      expect(provider.height, isNull);
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final direction in [-1.0, 1.0]) {
      testWidgets(
          'fast thumbnail fling keeps main image synchronized without rewind: $platform $direction',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(platform: platform),
          home: ImageGalleryPage(
              pics: List.filled(18, galleryTestPic),
              initialIndex: 8,
              statusId: 'fast'),
        ));
        await tester.pump();
        final strip = find.byKey(const ValueKey('gallery-thumbnail-strip'));
        final thumbnails = tester.widget<PageView>(
            find.descendant(of: strip, matching: find.byType(PageView)));
        final main = tester.widget<ExtendedImageGesturePageView>(
            find.byType(ExtendedImageGesturePageView));
        expect(thumbnails.pageSnapping, isFalse);
        expect(thumbnails.physics, isA<ClampingScrollPhysics>());
        final seen = <String>{'9 / 18'};
        await tester.fling(strip, Offset(direction * 460, 0), 6500);
        for (var frame = 0; frame < 180; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            main.controller.page,
            closeTo(thumbnails.controller!.page!, 0.04),
            reason: 'main and reel should track each other on frame $frame',
          );
          final counter = tester.widget<Text>(find.byWidgetPredicate((widget) =>
              widget is Text && widget.data?.endsWith(' / 18') == true));
          seen.add(counter.data!);
        }
        expect(seen.length, greaterThan(2));
        final finalIndex = thumbnails.controller!.page!.round();
        expect(find.text('${finalIndex + 1} / 18'), findsOneWidget);
        expect(
            thumbnails.controller!.position.isScrollingNotifier.value, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('main image follows thumbnail position throughout a drag',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ImageGalleryPage(
      pics: List.filled(18, galleryTestPic),
      initialIndex: 0,
      statusId: 'drag',
    )));
    await tester.pump();
    final strip = find.byKey(const ValueKey('gallery-thumbnail-strip'));
    final thumbnails = tester.widget<PageView>(
        find.descendant(of: strip, matching: find.byType(PageView)));
    final main = tester.widget<ExtendedImageGesturePageView>(
        find.byType(ExtendedImageGesturePageView));
    final gesture = await tester.startGesture(tester.getCenter(strip));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(main.controller.page, closeTo(thumbnails.controller!.page!, 0.02));
    await gesture.moveBy(const Offset(-240, 0));
    await tester.pump(const Duration(milliseconds: 32));
    expect(main.controller.page, closeTo(thumbnails.controller!.page!, 0.02));
    expect(find.text('1 / 18'), findsNothing);
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 160));
    final finalIndex = thumbnails.controller!.page!.round();
    expect(main.controller.page, closeTo(finalIndex.toDouble(), 0.02));
    expect(find.text('${finalIndex + 1} / 18'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('main navigation cancels old thumbnail inertia', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ImageGalleryPage(
            pics: List.filled(18, galleryTestPic),
            initialIndex: 8,
            statusId: 'interrupt')));
    await tester.pump();
    final strip = find.byKey(const ValueKey('gallery-thumbnail-strip'));
    await tester.fling(strip, const Offset(-220, 0), 2200);
    await tester.pump(const Duration(milliseconds: 32));
    final main = find.byType(ExtendedImageGesturePageView);
    await tester.drag(main, const Offset(500, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    final thumbnails = tester.widget<PageView>(
        find.descendant(of: strip, matching: find.byType(PageView)));
    final mainController =
        tester.widget<ExtendedImageGesturePageView>(main).controller;
    expect(mainController.page, closeTo(thumbnails.controller!.page!, 0.02));
    expect(tester.takeException(), isNull);
  });

  for (final count in [2, 8, 18]) {
    testWidgets(
        'thumbnail roller synchronizes tap and main swipe for $count photos',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: ImageGalleryPage(
        pics: List.filled(count, galleryTestPic),
        initialIndex: 0,
        statusId: 'roller',
      )));
      await tester.pump();
      final strip = find.byKey(const ValueKey('gallery-thumbnail-strip'));
      expect(strip, findsOneWidget);
      expect(tester.getBottomLeft(strip).dy,
          lessThan(tester.view.physicalSize.height));
      await tester.tap(find.byKey(const ValueKey('gallery-thumbnail-1')));
      await tester.pump();
      expect(find.text('2 / $count'), findsOneWidget);
      final selected = tester.widget<Semantics>(find
          .ancestor(
              of: find.byKey(const ValueKey('gallery-thumbnail-1')),
              matching: find.byType(Semantics))
          .first);
      expect(selected.properties.selected, isTrue);
      final main = find.byType(ExtendedImageGesturePageView);
      await tester.drag(main, const Offset(600, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('1 / $count'), findsOneWidget);
      await tester.drag(strip, const Offset(-180, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('1 / $count'), findsNothing);
      expect(find.byType(ImageGalleryPage), findsOneWidget);
      await tester.tapAt(const Offset(400, 200));
      await tester.pump();
      expect(strip, findsNothing);
      await tester.tapAt(const Offset(400, 200));
      await tester.pump();
      expect(strip, findsOneWidget);
      expect(find.text('1 / $count'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('center tap toggles image gallery top controls', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ImageGalleryPage(
          pics: [galleryTestPic],
          initialIndex: 0,
          statusId: 'gallery-test',
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery-thumbnail-strip')), findsNothing);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump();

    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    expect(find.byIcon(Icons.download_rounded), findsNothing);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump();

    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
  });

  testWidgets('side tap exits image gallery', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = RecordingNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('host page')),
      ),
    );
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'image-gallery-test'),
        builder: (_) => const ImageGalleryPage(
          pics: [galleryTestPic],
          initialIndex: 0,
          statusId: 'gallery-test',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tapAt(const Offset(100, 300));
    await tester.pump(const Duration(milliseconds: 500));

    expect(observer.poppedRouteName, 'image-gallery-test');
  });
}
