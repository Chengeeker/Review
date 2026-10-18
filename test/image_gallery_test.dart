import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review/core/storage/storage_service.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

class _DiagnosticImageClient implements HttpClient {
  _DiagnosticImageClient(this.request);

  final Future<HttpClientRequest> Function() request;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => request();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DiagnosticImageRequest implements HttpClientRequest {
  _DiagnosticImageRequest(this.bytes, {this.statusCode = 200});

  final Uint8List bytes;
  final int statusCode;

  @override
  HttpHeaders get headers => _DiagnosticImageHeaders();

  @override
  Future<HttpClientResponse> close() async =>
      _DiagnosticImageResponse(bytes, statusCode: statusCode);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DiagnosticImageHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DiagnosticImageResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _DiagnosticImageResponse(this.bytes, {this.statusCode = 200});

  final Uint8List bytes;
  @override
  final int statusCode;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class RecordingNavigatorObserver extends NavigatorObserver {
  String? poppedRouteName;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    poppedRouteName = route.settings.name;
    super.didPop(route, previousRoute);
  }
}

class _GalleryImageStream extends ImageStreamCompleter {
  void frame(ui.Image image) => setImage(ImageInfo(image: image));
}

Future<List<_GalleryImageStream>> _cacheDecodedGalleryPics(
  WidgetTester tester,
  List<WeiboPicModel> pics,
) async {
  final image = (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(120, 240);
    picture.dispose();
    return image;
  }))!;
  final providers = pics
      .map((pic) => ExtendedNetworkImageProvider(pic.originalUrl, cache: true))
      .toList();
  final streams = <_GalleryImageStream>[];
  for (final provider in providers) {
    final stream = _GalleryImageStream()..frame(image.clone());
    streams.add(stream);
    imageCache.putIfAbsent(provider, () => stream);
  }
  addTearDown(() {
    for (final provider in providers) {
      imageCache.evict(provider);
    }
    image.dispose();
  });
  return streams;
}

late StorageService galleryTestStorage;

Future<void> _pumpGallery(WidgetTester tester, Widget child) => tester.pumpWidget(
  ProviderScope(
    overrides: [storageServiceProvider.overrideWithValue(galleryTestStorage)],
    child: child,
  ),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    galleryTestStorage = StorageService(await SharedPreferences.getInstance());
  });
  testWidgets(
    'decoded gallery paints through actual Hero push, swipe and pop',
    (tester) async {
      const pathProviderChannel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathProviderChannel,
        (_) async => Directory.systemTemp.path,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          pathProviderChannel,
          null,
        ),
      );
      final pics = List.generate(
        2,
        (index) => WeiboPicModel(
          pid: 'hero-decoded-$index',
          thumbnail: 'https://gallery-test.invalid/hero-preview-$index.png',
          large: 'https://gallery-test.invalid/hero-preview-$index.png',
          original: 'https://gallery-test.invalid/hero-decoded-$index.png',
          isWebpageCard: index == 1,
        ),
      );
      await _cacheDecodedGalleryPics(tester, pics);
      await _cacheDecodedGalleryPics(tester, [
        for (final pic in pics)
          WeiboPicModel(
            pid: '${pic.pid}-preview',
            thumbnail: pic.previewUrl,
            large: pic.previewUrl,
            original: pic.previewUrl,
          ),
      ]);
      final scope = Object();
      final navigator = GlobalKey<NavigatorState>();
      final screen = GlobalKey();
      await _pumpGallery(tester,
        RepaintBoundary(
          key: screen,
          child: MaterialApp(
            navigatorKey: navigator,
            home: Scaffold(
              body: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    pics.length,
                    (index) => GestureDetector(
                      key: ValueKey('decoded-hero-source-$index'),
                      onTap: () => navigator.currentState!.push<void>(
                        PhysicsSpringGalleryRoute(
                          child: ImageGalleryPage(
                            pics: pics,
                            initialIndex: index,
                            statusId: 'decoded-hero',
                            heroScope: scope,
                          ),
                        ),
                      ),
                      child: ImageGalleryHeroThumbnail(
                        scope: scope,
                        index: index,
                        pic: pics[index],
                        child: SizedBox(
                          width: 80,
                          height: 80,
                          child: ExtendedImage.network(
                            pics[index].previewUrl,
                            cache: true,
                            fit: pics[index].isWebpageCard
                                ? BoxFit.contain
                                : BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      for (final initialIndex in [0, 1]) {
        final source = find.byKey(
          ValueKey('decoded-hero-source-$initialIndex'),
        );
        final sourceImage = tester.state(
          find.descendant(of: source, matching: find.byType(ExtendedImage)),
        ) as ExtendedImageState;
        final sourcePixels = sourceImage.extendedImageInfo!.image;
        final pendingOriginal = initialIndex == 1
            ? _GalleryImageStream()
            : null;
        if (pendingOriginal != null) {
          final provider = ExtendedNetworkImageProvider(
            pics[initialIndex].originalUrl,
            cache: true,
          );
          imageCache.evict(provider);
          imageCache.putIfAbsent(provider, () => pendingOriginal);
        }
        await tester.tap(source);
        await tester.pump();
        for (var frame = 0; frame < 6; frame++) {
          if (frame == 2 && pendingOriginal != null) {
            pendingOriginal.frame(sourcePixels.clone());
          }
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull);
          expect(find.byType(ErrorWidget), findsNothing);
        }
        final flyingImage = find.byElementPredicate(
          (element) =>
              element.widget is ExtendedRawImage &&
              element.findAncestorStateOfType<ExtendedImageGestureState>() !=
                  null &&
              element
                      .findAncestorStateOfType<
                        ExtendedImageGesturePageViewState
                      >() ==
                  null,
        );
        expect(flyingImage, findsOneWidget);
        final boundary =
            screen.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final point = boundary.globalToLocal(tester.getCenter(flyingImage));
        final pixel = await tester.runAsync(() async {
          final snapshot = await boundary.toImage();
          final bytes = await snapshot.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final offset =
              (point.dy.floor() * snapshot.width + point.dx.floor()) * 4;
          final rgba = bytes!.buffer.asUint8List().sublist(offset, offset + 4);
          snapshot.dispose();
          return rgba;
        });
        expect(pixel, [
          0x21,
          0x96,
          0xf3,
          0xff,
        ], reason: 'the flying image must paint decoded pixels');
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);

        final pager = find.byType(ExtendedImageGesturePageView);
        final controller = tester
            .widget<ExtendedImageGesturePageView>(pager)
            .controller;
        await tester.fling(
          pager,
          Offset(initialIndex == 0 ? -400 : 400, 0),
          6500,
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(controller.page, closeTo(1 - initialIndex, .02));
        navigator.currentState!.pop();
        await tester.pump();
        for (var frame = 0; frame < 16; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull);
          expect(find.byType(ErrorWidget), findsNothing);
        }
        expect(find.byType(ImageGalleryPage), findsNothing);
      }
    },
  );

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

    await _pumpGallery(tester,
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
    await _pumpGallery(tester,
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

    await _pumpGallery(tester,
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
        .where((element) {
          var enabled = true;
          element.visitAncestorElements((ancestor) {
            if (ancestor.widget case HeroMode(enabled: false)) enabled = false;
            return enabled;
          });
          return enabled;
        })
        .length;

    await tester.tap(find.byKey(const ValueKey('source-thumbnail-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(heroCount(0), 2, reason: 'the open image pairs with its source');
    expect(
      heroCount(1),
      1,
      reason: 'the adjacent cached page disables its Hero',
    );
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
          await _pumpGallery(tester,
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
          await _pumpGallery(tester,
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
          await _pumpGallery(tester,
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
          await _pumpGallery(tester, const SizedBox());
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
    await _pumpGallery(tester,
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
    await _pumpGallery(tester,
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
          await _pumpGallery(tester,
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

  testWidgets(
    'decoded image gesture survives Hero selection and interrupted flings',
    (tester) async {
      var pointerDowns = 0;
      var scrollStarts = 0;
      final pics = List.generate(
        8,
        (index) => WeiboPicModel(
          pid: 'decoded-$index',
          thumbnail: 'https://gallery-test.invalid/decoded-$index.png',
          large: 'https://gallery-test.invalid/decoded-$index.png',
          original: 'https://gallery-test.invalid/decoded-$index.png',
        ),
      );
      final streams = await _cacheDecodedGalleryPics(tester, pics);
      await _pumpGallery(tester,
        MaterialApp(
          home: Listener(
            onPointerDown: (_) => pointerDowns++,
            child: NotificationListener<ScrollStartNotification>(
              onNotification: (notification) {
                if (notification.dragDetails != null) scrollStarts++;
                return false;
              },
              child: ImageGalleryPage(
                pics: pics,
                initialIndex: 0,
                statusId: 'decoded',
                heroScope: Object(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final main = find.byType(ExtendedImageGesturePageView);
      final controller = tester
          .widget<ExtendedImageGesturePageView>(main)
          .controller;
      ExtendedImageGestureState imageState(int index) => tester.state(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is ExtendedImage &&
                widget.image ==
                    ExtendedNetworkImageProvider(
                      pics[index].originalUrl,
                      cache: true,
                    ),
          ),
          matching: find.byType(ExtendedImageGesture),
        ),
      );
      final drag = await tester.startGesture(tester.getCenter(main));
      await drag.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await drag.moveBy(const Offset(-160, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await drag.moveBy(const Offset(-160, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(pointerDowns, 1);
      expect(scrollStarts, greaterThan(0));
      expect(controller.page, greaterThan(0));
      final incoming = imageState(1);
      final incomingWidget = incoming.widget;
      await drag.moveBy(const Offset(-400, 0));
      await tester.pump();
      expect(controller.page, greaterThan(.5));
      expect(
        imageState(1),
        same(incoming),
        reason: 'selecting the incoming Hero must preserve its gesture subtree',
      );
      expect(
        incoming.widget,
        same(incomingWidget),
        reason: 'an unchanged decoded frame must not reinitialize gesture animations',
      );
      await drag.up();
      await tester.pump(const Duration(seconds: 1));

      for (final direction in [-1.0, -1.0, 1.0, -1.0, 1.0, 1.0]) {
        final before = controller.page!;
        await tester.fling(main, Offset(direction * 400, 0), 6500);
        await tester.pump(const Duration(milliseconds: 32));
        expect(
          controller.page,
          direction < 0 ? greaterThan(before) : lessThan(before),
        );
      }
      await tester.pump(const Duration(seconds: 2));
      expect(controller.page, closeTo(controller.page!.roundToDouble(), .02));

      final selected = imageState(controller.page!.round());
      final previousFrameWidget = selected.widget;
      streams[controller.page!.round()].frame(
        selected.widget.extendedImageState.extendedImageInfo!.image.clone(),
      );
      await tester.pump();
      expect(
        selected.widget,
        isNot(same(previousFrameWidget)),
        reason: 'a new decoded frame must update animated images',
      );
      Future<void> doubleTap() async {
        await tester.tapAt(tester.getCenter(main));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(tester.getCenter(main));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      await doubleTap();
      expect(selected.gestureDetails!.totalScale, closeTo(2.5, .01));
      final zoomedPage = controller.page!;
      await tester.fling(main, const Offset(-400, 0), 6500);
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.page, closeTo(zoomedPage, .02));
      await doubleTap();
      await doubleTap();
      expect(selected.gestureDetails!.totalScale, closeTo(1, .01));
      await tester.pump();
      final center = tester.getCenter(main);
      final left = await tester.startGesture(
        center - const Offset(40, 0),
        pointer: 10,
      );
      final right = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 11,
      );
      await left.moveBy(const Offset(-40, 0));
      await right.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        controller.page,
        closeTo(zoomedPage, .02),
        reason: 'two-finger translation must not become a page drag',
      );
      await left.moveBy(const Offset(-60, 0));
      await right.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(selected.gestureDetails!.totalScale, greaterThan(1));
      await left.up();
      await right.up();
      selected.reset();
      await tester.pump();
      await tester.fling(main, const Offset(-400, 0), 6500);
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.page, greaterThan(zoomedPage));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'main gallery accepts a reverse fling before the previous fling settles',
    (tester) async {
      var pointerDowns = 0;
      final dragScrollStarts = <ScrollStartNotification>[];
      await _pumpGallery(tester,
        MaterialApp(
          home: Listener(
            onPointerDown: (_) => pointerDowns++,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null) {
                  dragScrollStarts.add(notification);
                }
                return false;
              },
              child: ImageGalleryPage(
                pics: List.filled(18, galleryTestPic),
                initialIndex: 8,
                statusId: 'reverse-fling',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final pager = tester.widget<ExtendedImageGesturePageView>(
        find.byType(ExtendedImageGesturePageView),
      );
      final main = find.byType(ExtendedImageGesturePageView);
      final pagePosition = pager.controller.position;

      // Stage 1: the pointer reaches the gallery. Stage 2/3: its horizontal
      // drag recognizer wins and Scrollable starts a user drag.
      await tester.fling(main, const Offset(-480, 0), 8000);
      await tester.pump(const Duration(milliseconds: 16));
      expect(pointerDowns, 1);
      expect(dragScrollStarts, isNotEmpty);
      expect(pagePosition.isScrollingNotifier.value, isTrue);
      final forwardPage = pager.controller.page!;
      expect(forwardPage, greaterThan(8));

      // Take the still-running ballistic scroll over with the opposite drag.
      final reverse = await tester.startGesture(tester.getCenter(main));
      await reverse.moveBy(const Offset(64, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await reverse.moveBy(const Offset(160, 0));
      await tester.pump(const Duration(milliseconds: 16));
      final reverseDragPage = pager.controller.page!;
      expect(
        reverseDragPage,
        lessThan(forwardPage),
        reason:
            'page position must respond while the reverse finger drag is down',
      );
      await reverse.up();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));

      final reverseFlingPage = pager.controller.page!;
      expect(
        reverseFlingPage,
        lessThan(reverseDragPage),
        reason:
            'the reverse fling should settle backward after pointer-up; '
            'activity=${pagePosition.activity.runtimeType}',
      );
      expect(pointerDowns, 2);
      expect(dragScrollStarts.length, greaterThanOrEqualTo(2));

      await tester.pump(const Duration(seconds: 2));
      final finalPage = pager.controller.page!;
      expect(finalPage, closeTo(finalPage.roundToDouble(), 0.02));
      expect(find.text('${finalPage.round() + 1} / 18'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'main paging works during image loading and after decode failure',
    (tester) async {
      final request = Completer<HttpClientRequest>();
      var requestStarted = false;
      const pathProviderChannel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathProviderChannel,
        (_) async => Directory.systemTemp.path,
      );
      final originalProvider = debugNetworkImageHttpClientProvider;
      debugNetworkImageHttpClientProvider = () => _DiagnosticImageClient(() {
        requestStarted = true;
        return request.future;
      });
      addTearDown(() {
        debugNetworkImageHttpClientProvider = originalProvider;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          pathProviderChannel,
          null,
        );
      });

      await _pumpGallery(tester,
        MaterialApp(
          home: ImageGalleryPage(
            pics: List.generate(
              18,
              (index) => WeiboPicModel(
                pid: 'loading-test-$index',
                thumbnail: 'https://gallery-test.invalid/loading-$index.jpg',
                large: 'https://gallery-test.invalid/loading-$index.jpg',
                original: 'https://gallery-test.invalid/loading-$index.jpg',
              ),
            ),
            initialIndex: 8,
            statusId: 'loading-and-failed-image',
          ),
        ),
      );
      await tester.pump();

      final main = find.byType(ExtendedImageGesturePageView);
      final controller = tester
          .widget<ExtendedImageGesturePageView>(main)
          .controller;
      expect(requestStarted, isTrue, reason: 'the current image is loading');
      expect(request.isCompleted, isFalse, reason: 'the response is held open');

      // Loading placeholder: prove pointer -> user drag -> page position.
      await tester.fling(main, const Offset(-420, 0), 7000);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.page, greaterThan(8));

      // Resolve the pending request with HTTP 404 to force the failed
      // image state, then ensure paging can still be recognized in reverse.
      request.complete(
        _DiagnosticImageRequest(Uint8List(0), statusCode: HttpStatus.notFound),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      final galleryImages = find.descendant(
        of: main,
        matching: find.byType(ExtendedImage),
      );
      final imageState =
          tester.state(galleryImages.first) as ExtendedImageState;
      expect(imageState.extendedImageLoadState, LoadState.failed);

      final pageBeforeReverse = controller.page!;
      await tester.fling(main, const Offset(420, 0), 7000);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.page, lessThan(pageBeforeReverse));
      expect(tester.takeException(), isA<StateError>());
      expect(tester.takeException(), isNull);
      debugNetworkImageHttpClientProvider = originalProvider;
    },
  );

  testWidgets('main image follows thumbnail position throughout a drag', (
    tester,
  ) async {
    await _pumpGallery(tester,
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
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final finalIndex = thumbnails.controller!.page!.round();
    expect(main.controller.page, closeTo(finalIndex.toDouble(), 0.02));
    expect(find.text('${finalIndex + 1} / 18'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thumbnail and main image stay still while drag is held', (
    tester,
  ) async {
    await _pumpGallery(tester,
      MaterialApp(
        home: ImageGalleryPage(
          pics: List.filled(18, galleryTestPic),
          initialIndex: 0,
          statusId: 'held-drag',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final strip = find.byKey(const ValueKey('gallery-thumbnail-strip'));
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(of: strip, matching: find.byType(IgnorePointer))
                .first,
          )
          .ignoring,
      isFalse,
    );
    final thumbnails = tester.widget<PageView>(
      find.descendant(of: strip, matching: find.byType(PageView)),
    );
    final main = tester.widget<ExtendedImageGesturePageView>(
      find.byType(ExtendedImageGesturePageView),
    );
    final gesture = await tester.startGesture(tester.getCenter(strip));
    for (var step = 0; step < 4; step++) {
      await gesture.moveBy(const Offset(-24, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    final heldThumbnailPage = thumbnails.controller!.page!;
    final heldMainPage = main.controller.page!;
    expect(
      tester
          .widget<ExtendedImageGesturePageView>(
            find.byType(ExtendedImageGesturePageView),
          )
          .pageSnapping,
      isFalse,
    );
    expect(
      heldThumbnailPage,
      inInclusiveRange(.4, .6),
      reason:
          'strip=${tester.getRect(strip)}, viewport=${thumbnails.controller!.position.viewportDimension}, pixels=${thumbnails.controller!.position.pixels}',
    );
    expect(heldMainPage, closeTo(heldThumbnailPage, .02));

    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(thumbnails.controller!.page, closeTo(heldThumbnailPage, .001));
      expect(
        main.controller.page,
        closeTo(heldMainPage, .02),
        reason:
            'frame=$frame, mainActivity=${main.controller.position.activity.runtimeType}, mainScrolling=${main.controller.position.isScrollingNotifier.value}, thumbnail=${thumbnails.controller!.page}',
      );
    }

    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final finalIndex = thumbnails.controller!.page!.round();
    expect(thumbnails.controller!.page, closeTo(finalIndex.toDouble(), .02));
    expect(main.controller.page, closeTo(finalIndex.toDouble(), .02));
    expect(
      tester
          .widget<ExtendedImageGesturePageView>(
            find.byType(ExtendedImageGesturePageView),
          )
          .pageSnapping,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('main navigation cancels old thumbnail inertia', (tester) async {
    await _pumpGallery(tester,
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
    final mainController = tester
        .widget<ExtendedImageGesturePageView>(main)
        .controller;
    final thumbnailController = tester
        .widget<PageView>(
          find.descendant(of: strip, matching: find.byType(PageView)),
        )
        .controller!;
    final pageBeforeTakeover = mainController.page!;
    final gesture = await tester.startGesture(tester.getCenter(main));
    await gesture.moveBy(const Offset(180, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      thumbnailController.position.isScrollingNotifier.value,
      isFalse,
      reason: 'main interaction must stop the old thumbnail ballistic activity',
    );
    expect(mainController.page, lessThan(pageBeforeTakeover));
    await gesture.moveBy(const Offset(180, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    final thumbnails = tester.widget<PageView>(
      find.descendant(of: strip, matching: find.byType(PageView)),
    );
    expect(mainController.page, closeTo(thumbnails.controller!.page!, 0.02));
    expect(tester.takeException(), isNull);
  });

  for (final count in [2, 8, 18]) {
    testWidgets(
      'thumbnail roller synchronizes tap and main swipe for $count photos',
      (tester) async {
        await _pumpGallery(tester,
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
        final mainPage = tester.widget<ExtendedImageGesturePageView>(main);
        expect(mainPage.physics.parent, isA<BouncingScrollPhysics>());
        expect(mainPage.canScrollPage(GestureDetails(totalScale: 2)), isFalse);
        expect(
          mainPage.canScrollPage(GestureDetails(totalScale: 1)),
          isTrue,
          reason: 'page swiping must be re-enabled after returning to 1x zoom',
        );
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
        await tester.pump(kDoubleTapTimeout);
        expect(strip, findsNothing);
        await tester.tapAt(const Offset(400, 200));
        await tester.pump(kDoubleTapTimeout);
        expect(strip, findsOneWidget);
        expect(find.text('1 / $count'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('center tap toggles image gallery top controls', (tester) async {
    await _pumpGallery(tester,
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
    await tester.pump(kDoubleTapTimeout);

    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    expect(find.byIcon(Icons.download_rounded), findsNothing);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump(kDoubleTapTimeout);

    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
  });

  testWidgets('double tap does not toggle image gallery chrome', (
    tester,
  ) async {
    await _pumpGallery(tester,
      const MaterialApp(
        home: ImageGalleryPage(
          pics: [galleryTestPic],
          initialIndex: 0,
          statusId: 'gallery-double-tap-test',
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ExtendedImage), findsOneWidget);
    final imageCenter = tester.getCenter(
      find.byType(ExtendedImageGesturePageView),
    );
    await tester.tapAt(imageCenter);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    await tester.tapAt(imageCenter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
  });

  testWidgets('side tap exits image gallery', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = RecordingNavigatorObserver();

    await _pumpGallery(tester,
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
    await tester.pump(kDoubleTapTimeout);
    await tester.pump(const Duration(milliseconds: 500));

    expect(observer.poppedRouteName, 'image-gallery-test');
  });
}
