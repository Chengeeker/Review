import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:review/core/utils/spring_page_route.dart';
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

const portraitGalleryTestPic = WeiboPicModel(
  pid: 'portrait-gallery-test',
  thumbnail: 'https://example.com/portrait-gallery-test.jpg',
  large: 'https://example.com/portrait-gallery-test.jpg',
  original: 'https://example.com/portrait-gallery-test.jpg',
  width: 9,
  height: 16,
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
  testWidgets('gallery pairs its fullscreen image with the source thumbnail', (
    tester,
  ) async {
    final heroScope = Object();
    final heroTag = ImageGalleryHeroTag.forPic(
      scope: heroScope,
      index: 0,
      pic: galleryTestPic,
    );
    final sourceThumbnail = find.byKey(const ValueKey('hero-source-thumbnail'));

    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );

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

  testWidgets('gallery chrome fades after route open and as pop begins', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('host page')),
      ),
    );

    navigatorKey.currentState!.push<void>(
      PhysicsSpringGalleryRoute(
        child: const ImageGalleryPage(
          pics: [galleryTestPic, galleryTestPic],
          initialIndex: 0,
          statusId: 'thumbnail-transition',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    final fade = find.byKey(const ValueKey('gallery-thumbnail-strip-fade'));
    final backButtonFade = find.byKey(
      const ValueKey('gallery-back-button-opacity'),
    );
    final counterFade = find.byKey(const ValueKey('gallery-counter-opacity'));
    final downloadButtonFade = find.byKey(
      const ValueKey('gallery-download-button-opacity'),
    );
    final topControlsGate = find.byKey(
      const ValueKey('gallery-top-controls-pointer-gate'),
    );
    final pageView = find.byType(ExtendedImageGesturePageView);
    expect(pageView, findsOneWidget);
    final pageSize = tester.getSize(pageView);
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);
    expect(tester.widget<Opacity>(backButtonFade).opacity, 0);
    expect(tester.widget<Opacity>(counterFade).opacity, 0);
    expect(tester.widget<Opacity>(downloadButtonFade).opacity, 0);
    expect(tester.widget<IgnorePointer>(topControlsGate).ignoring, isTrue);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byTooltip('保存高清大图 / 实况到相册'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 220));
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);
    expect(tester.widget<IgnorePointer>(topControlsGate).ignoring, isFalse);
    await tester.pump(const Duration(milliseconds: 70));
    expect(
      tester.widget<Opacity>(backButtonFade).opacity,
      allOf(greaterThan(0), lessThan(1)),
    );
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.widget<Opacity>(backButtonFade).opacity, 1);
    expect(tester.widget<Opacity>(counterFade).opacity, 1);
    expect(tester.widget<Opacity>(downloadButtonFade).opacity, 1);
    expect(tester.getSize(pageView), pageSize);

    navigatorKey.currentState!.pop();
    await tester.pump();
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);
    expect(tester.widget<IgnorePointer>(topControlsGate).ignoring, isTrue);
    await tester.pump(const Duration(milliseconds: 70));
    expect(
      tester.widget<Opacity>(backButtonFade).opacity,
      allOf(greaterThan(0), lessThan(1)),
    );
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.widget<Opacity>(backButtonFade).opacity, 0);
    expect(tester.widget<Opacity>(counterFade).opacity, 0);
    expect(tester.widget<Opacity>(downloadButtonFade).opacity, 0);
    expect(tester.getSize(pageView), pageSize);

    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the selected gallery image pairs with its source Hero', (
    tester,
  ) async {
    final heroScope = Object();
    const pics = [galleryTestPic, galleryTestPic, galleryTestPic];
    ImageGalleryHeroTag tagFor(int index) => ImageGalleryHeroTag.forPic(
      scope: heroScope,
      index: index,
      pic: galleryTestPic,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                pics.length,
                (index) => ImageGalleryHeroThumbnail(
                  scope: heroScope,
                  index: index,
                  pic: pics[index],
                  child: GestureDetector(
                    key: ValueKey('source-thumbnail-$index'),
                    onTap: () => Navigator.of(context).push<void>(
                      PageRouteBuilder<void>(
                        opaque: false,
                        transitionDuration: const Duration(milliseconds: 220),
                        pageBuilder: (_, __, ___) => ImageGalleryPage(
                          pics: pics,
                          initialIndex: index,
                          statusId: 'multi-hero-test',
                          heroScope: heroScope,
                        ),
                      ),
                    ),
                    child: const SizedBox(
                      width: 72,
                      height: 72,
                      child: ColoredBox(color: Colors.blue),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    int heroCount(int index) => find
        .byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == tagFor(index),
        )
        .evaluate()
        .length;

    await tester.tap(find.byKey(const ValueKey('source-thumbnail-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(heroCount(0), 2, reason: 'the open image pairs with its source');
    expect(heroCount(1), 1, reason: 'the adjacent cached page has no Hero');
    expect(heroCount(2), 1);

    await tester.tap(find.byKey(const ValueKey('gallery-thumbnail-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('2 / 3'), findsOneWidget);
    expect(heroCount(0), 1, reason: 'the previous image stays at its source');
    expect(heroCount(1), 2, reason: 'only the selected image pairs');
    expect(heroCount(2), 1);

    await tester.tap(find.byKey(const ValueKey('gallery-thumbnail-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('3 / 3'), findsOneWidget);
    expect(heroCount(0), 1);
    expect(heroCount(1), 1, reason: 'the previously visited page is cached');
    expect(heroCount(2), 2, reason: 'return animates only the visible image');
    expect(tester.takeException(), isNull);
  });

  for (final pixels in [const Size(240, 120), const Size(120, 240)]) {
    for (final zoom in [1.0, 1.8]) {
      testWidgets(
        'return endpoints match ExtendedImage crop for $pixels zoom $zoom',
        (tester) async {
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          // Patterned pixels expose wrong fit/crop, unlike a solid-colour image.
          for (var x = 0; x < pixels.width; x += 10) {
            for (var y = 0; y < pixels.height; y += 10) {
              canvas.drawRect(
                Rect.fromLTWH(x.toDouble(), y.toDouble(), 10, 10),
                Paint()
                  ..color = Color.fromARGB(
                    255,
                    x % 256,
                    y % 256,
                    (x + y) % 256,
                  ),
              );
            }
          }
          final picture = recorder.endRecording();
          final image = (await tester.runAsync(
            () => picture.toImage(pixels.width.toInt(), pixels.height.toInt()),
          ))!;
          picture.dispose();
          final navigatorKey = GlobalKey<NavigatorState>();
          final sourceKey = GlobalKey();
          final galleryKey = GlobalKey();
          final boundaryKey = GlobalKey();
          final galleryBoundaryKey = GlobalKey();
          final tag = ImageGalleryHeroTag.forPic(
            scope: Object(),
            index: 0,
            pic: galleryTestPic,
          );
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigatorKey,
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: Hero(
                      key: sourceKey,
                      tag: tag,
                      flightShuttleBuilder:
                          imageGalleryHeroFlightShuttleBuilder,
                      child: SizedBox(
                        width: 100,
                        height: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ExtendedRawImage(
                            image: image,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          Future<List<int>> screenshot(GlobalKey key) async {
            final boundary =
                key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final snapshot = await boundary.toImage(pixelRatio: 1);
            final data = await snapshot.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            snapshot.dispose();
            return data!.buffer.asUint8List().toList();
          }

          final expected = await tester.runAsync(() => screenshot(boundaryKey));
          navigatorKey.currentState!.push<void>(
            PhysicsSpringGalleryRoute(
              child: Scaffold(
                body: Center(
                  child: Hero(
                    key: galleryKey,
                    tag: tag,
                    flightShuttleBuilder: imageGalleryHeroFlightShuttleBuilder,
                    child: RepaintBoundary(
                      key: galleryBoundaryKey,
                      child: SizedBox(
                        width: 300,
                        height: 400,
                        child: ExtendedRawImage(
                          image: image,
                          fit: BoxFit.contain,
                          gestureDetails: GestureDetails(
                            totalScale: zoom,
                            offset: const Offset(-25, -35),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final expectedStart = await tester.runAsync(
            () => screenshot(galleryBoundaryKey),
          );
          final startShuttle = imageGalleryHeroFlightShuttleBuilder(
            galleryKey.currentContext!,
            const AlwaysStoppedAnimation(1),
            HeroFlightDirection.pop,
            galleryKey.currentContext!,
            sourceKey.currentContext!,
          );
          // Explicit endpoint painting lets us compare every pixel at handoff;
          // the source and destination are real ExtendedRenderImage objects.
          final shuttle = imageGalleryHeroFlightShuttleBuilder(
            galleryKey.currentContext!,
            const AlwaysStoppedAnimation(0),
            HeroFlightDirection.pop,
            galleryKey.currentContext!,
            sourceKey.currentContext!,
          );
          navigatorKey.currentState!.pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            find.byKey(const ValueKey('gallery-return-image-plane')),
            findsOneWidget,
          );
          await tester.pumpAndSettle();
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: SizedBox(width: 300, height: 400, child: startShuttle),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            await tester.runAsync(() => screenshot(boundaryKey)),
            expectedStart,
            reason: 'first flight pixels must keep current zoom/pan and paint offset',
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: SizedBox(width: 100, height: 100, child: shuttle),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            await tester.runAsync(() => screenshot(boundaryKey)),
            expected,
            reason: 'last flight pixels must equal the rounded cover thumbnail',
          );
          await tester.pumpWidget(const SizedBox());
          image.dispose();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('return without decoded pixels keeps existing gallery fallback', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    final tag = ImageGalleryHeroTag.forPic(
      scope: Object(),
      index: 0,
      pic: portraitGalleryTestPic,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: Center(
          child: Hero(
            tag: tag,
            flightShuttleBuilder: imageGalleryHeroFlightShuttleBuilder,
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      ),
    );
    nav.currentState!.push<void>(
      PhysicsSpringGalleryRoute(
        child: Center(
          child: Hero(
            tag: tag,
            flightShuttleBuilder: imageGalleryHeroFlightShuttleBuilder,
            child: const SizedBox(
              key: ValueKey('fallback-gallery'),
              width: 280,
              height: 420,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('fallback-gallery')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('thumbnail decoding preserves aspect ratio before cover crop', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ImageGalleryPage(
          pics: [galleryTestPic, galleryTestPic],
          initialIndex: 0,
          statusId: 'crop',
        ),
      ),
    );
    final images = tester.widgetList<ExtendedImage>(
      find.descendant(
        of: find.byKey(const ValueKey('gallery-thumbnail-strip')),
        matching: find.byType(ExtendedImage),
      ),
    );
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
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: ImageGalleryPage(
                pics: List.filled(18, galleryTestPic),
                initialIndex: 8,
                statusId: 'fast',
              ),
            ),
          );
          await tester.pump();
          final strip = find.byKey(const ValueKey('gallery-thumbnail-strip'));
          final thumbnails = tester.widget<PageView>(
            find.descendant(of: strip, matching: find.byType(PageView)),
          );
          final main = tester.widget<ExtendedImageGesturePageView>(
            find.byType(ExtendedImageGesturePageView),
          );
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
            final counter = tester.widget<Text>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Text && widget.data?.endsWith(' / 18') == true,
              ),
            );
            seen.add(counter.data!);
          }
          expect(seen.length, greaterThan(2));
          final finalIndex = thumbnails.controller!.page!.round();
          expect(find.text('${finalIndex + 1} / 18'), findsOneWidget);
          expect(
            thumbnails.controller!.position.isScrollingNotifier.value,
            isFalse,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('main image follows thumbnail position throughout a drag', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImageGalleryPage(
          pics: List.filled(18, galleryTestPic),
          initialIndex: 0,
          statusId: 'drag',
        ),
      ),
    );
    await tester.pump();
    final strip = find.byKey(const ValueKey('gallery-thumbnail-strip'));
    final thumbnails = tester.widget<PageView>(
      find.descendant(of: strip, matching: find.byType(PageView)),
    );
    final main = tester.widget<ExtendedImageGesturePageView>(
      find.byType(ExtendedImageGesturePageView),
    );
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
    await tester.pumpWidget(
      MaterialApp(
        home: ImageGalleryPage(
          pics: List.filled(18, galleryTestPic),
          initialIndex: 8,
          statusId: 'interrupt',
        ),
      ),
    );
    await tester.pump();
    final strip = find.byKey(const ValueKey('gallery-thumbnail-strip'));
    await tester.fling(strip, const Offset(-220, 0), 2200);
    await tester.pump(const Duration(milliseconds: 32));
    final main = find.byType(ExtendedImageGesturePageView);
    await tester.drag(main, const Offset(500, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    final thumbnails = tester.widget<PageView>(
      find.descendant(of: strip, matching: find.byType(PageView)),
    );
    final mainController = tester
        .widget<ExtendedImageGesturePageView>(main)
        .controller;
    expect(mainController.page, closeTo(thumbnails.controller!.page!, 0.02));
    expect(tester.takeException(), isNull);
  });

  for (final count in [2, 8, 18]) {
    testWidgets(
      'thumbnail roller synchronizes tap and main swipe for $count photos',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ImageGalleryPage(
              pics: List.filled(count, galleryTestPic),
              initialIndex: 0,
              statusId: 'roller',
            ),
          ),
        );
        await tester.pump();
        final strip = find.byKey(const ValueKey('gallery-thumbnail-strip'));
        expect(strip, findsOneWidget);
        expect(
          tester.getBottomLeft(strip).dy,
          lessThan(tester.view.physicalSize.height),
        );
        await tester.tap(find.byKey(const ValueKey('gallery-thumbnail-1')));
        await tester.pump();
        expect(find.text('2 / $count'), findsOneWidget);
        final selected = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('gallery-thumbnail-1')),
                matching: find.byType(Semantics),
              )
              .first,
        );
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
      },
    );
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
