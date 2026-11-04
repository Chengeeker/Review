import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/constants/api_constants.dart';
import 'package:review/core/design_system/components/review_card.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/core/utils/spring_page_route.dart';
import 'package:review/features/detail/presentation/widgets/image_gallery_page.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/nine_grid_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DecodedFrame extends ImageStreamCompleter {
  _DecodedFrame(ui.Image image) {
    setImage(ImageInfo(image: image));
  }
}

class _Pushes extends NavigatorObserver {
  final galleries = <PhysicsSpringGalleryRoute<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PhysicsSpringGalleryRoute) galleries.add(route);
  }
}

Future<ui.Rect> _blueBounds(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('screen-pixels')),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final rgba = data.buffer.asUint8List();
      var left = image.width;
      var right = -1;
      var top = image.height;
      var bottom = -1;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final i = (y * image.width + x) * 4;
          if (rgba[i] < 30 && rgba[i + 1] < 70 && rgba[i + 2] > 230) {
            if (x < left) left = x;
            if (x > right) right = x;
            if (y < top) top = y;
            if (y > bottom) bottom = y;
          }
        }
      }
      expect(right, greaterThanOrEqualTo(left));
      return Rect.fromLTRB(
        left.toDouble(),
        top.toDouble(),
        (right + 1).toDouble(),
        (bottom + 1).toDouble(),
      );
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  for (final count in [1, 4]) {
    for (final openingMs in [120, 400]) {
      for (final heldMs in [0, 120]) {
        testWidgets(
          'photo reopens during return without entering card: $count photos, opening=$openingMs, hold=$heldMs',
          (tester) async {
            tester.view.physicalSize = const Size(430, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            const paths = MethodChannel('plugins.flutter.io/path_provider');
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              paths,
              (_) async => Directory.systemTemp.path,
            );
            addTearDown(
              () => tester.binding.defaultBinaryMessenger
                  .setMockMethodCallHandler(paths, null),
            );
            SharedPreferences.setMockInitialValues({});
            final storage = await StorageService.init();
            final pics = List.generate(
              count,
              (index) => WeiboPicModel(
                pid: 'reentry-$count-$index',
                thumbnail: 'https://example.com/reentry-$count-$index.jpg',
                large: 'https://example.com/reentry-$count-$index.jpg',
                original: 'https://example.com/reentry-$count-$index.jpg',
                width: 120,
                height: 240,
              ),
            );
            final images = <ui.Image>[];
            final providers = <ExtendedNetworkImageProvider>[];
            for (var i = 0; i < pics.length; i++) {
              final image = (await tester.runAsync(() async {
                final recorder = ui.PictureRecorder();
                Canvas(recorder).drawColor(
                  i == 0 ? const Color(0xFF1234FF) : Colors.green,
                  BlendMode.src,
                );
                final picture = recorder.endRecording();
                final image = await picture.toImage(120, 240);
                picture.dispose();
                return image;
              }))!;
              images.add(image);
              final provider = ExtendedNetworkImageProvider(
                pics[i].originalUrl,
                cache: true,
                headers: ApiConstants.imageHeaders,
              );
              providers.add(provider);
              imageCache.putIfAbsent(
                provider,
                () => _DecodedFrame(image.clone()),
              );
            }
            final navigator = GlobalKey<NavigatorState>();
            final observer = _Pushes();
            var articleOpens = 0;
            try {
              await tester.pumpWidget(
                ProviderScope(
                  overrides: [
                    storageServiceProvider.overrideWithValue(storage),
                  ],
                  child: RepaintBoundary(
                    key: const ValueKey('screen-pixels'),
                    child: MaterialApp(
                      navigatorKey: navigator,
                      navigatorObservers: [observer],
                      home: Scaffold(
                        body: Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 90, 16, 0),
                            child: ReviewCard(
                              margin: EdgeInsets.zero,
                              onTap: () {
                                articleOpens++;
                                navigator.currentState!.push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const Scaffold(
                                      body: Text('article detail'),
                                    ),
                                  ),
                                );
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('article title'),
                                  NineGridView(pics: pics, statusId: 'reentry'),
                                ],
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
              final source = find
                  .descendant(
                    of: find.byType(NineGridView),
                    matching: find.byType(ImageGalleryHeroThumbnail),
                  )
                  .first;
              final point = tester.getCenter(source);
              final initialHandles = images.first
                  .debugGetOpenHandleStackTraces()!
                  .length;
              await tester.tapAt(point);
              await tester.pump();
              await tester.pump(Duration(milliseconds: openingMs));
              expect(observer.galleries, hasLength(1));
              navigator.currentState!.pop();
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 10));
              expect(
                observer.galleries.first.animation!.status,
                AnimationStatus.reverse,
              );
              final checkPixels = heldMs == 0;
              final before = checkPixels ? await _blueBounds(tester) : null;
              final secondTap = await tester.startGesture(point);
              if (heldMs > 0) await tester.pump(Duration(milliseconds: heldMs));
              await secondTap.up();
              await tester.pump();
              await tester.pump();
              expect(
                articleOpens,
                0,
                reason: 'the photo retains the tap during its Hero placeholder',
              );
              expect(observer.galleries, hasLength(2));
              var expectedPushes = 2;
              if (before != null) {
                final after = await _blueBounds(tester);
                expect(after.left, closeTo(before.left, 1));
                expect(after.top, closeTo(before.top, 1));
                expect(after.right, closeTo(before.right, 1));
                expect(after.bottom, closeTo(before.bottom, 1));
                for (var round = 0; round < 6; round++) {
                  final start = await _blueBounds(tester);
                  var previous = start;
                  final finishOpening = round.isOdd;
                  for (final frameMs
                      in finishOpening ? [30, 40, 80, 180] : [16, 32, 32]) {
                    await tester.pump(Duration(milliseconds: frameMs));
                    final frame = await _blueBounds(tester);
                    expect(
                      frame.center.dx,
                      inInclusiveRange(start.center.dx - 1, 216),
                      reason: 'round $round must move toward screen center',
                    );
                    expect(
                      frame.center.dy,
                      inInclusiveRange(start.center.dy - 1, 451),
                      reason: 'round $round must not drift to the top',
                    );
                    expect(
                      frame.width,
                      greaterThanOrEqualTo(previous.width - 1),
                    );
                    expect(
                      frame.height,
                      greaterThanOrEqualTo(previous.height - 1),
                    );
                    previous = frame;
                  }
                  if (finishOpening) {
                    expect(previous.center.dx, closeTo(215, 1));
                    expect(previous.center.dy, closeTo(450, 1));
                  }
                  if (round == 5) break;
                  navigator.currentState!.pop();
                  await tester.pump();
                  await tester.pump();
                  await tester.pump(
                    Duration(milliseconds: [10, 70, 150][round % 3]),
                  );
                  await tester.tapAt(point);
                  await tester.pump();
                  await tester.pump();
                  expectedPushes++;
                  expect(observer.galleries, hasLength(expectedPushes));
                  expect(articleOpens, 0);
                }
              }
              // Gallery thumbnails may still be reading their resize cache.
              await tester.pump(const Duration(milliseconds: 500));
              await tester.pump(const Duration(milliseconds: 200));
              expect(
                observer.galleries.last.animation!.status,
                AnimationStatus.completed,
              );
              expect(find.byType(ImageGalleryPage), findsOneWidget);
              expect(navigator.currentState!.canPop(), isTrue);
              navigator.currentState!.pop();
              await tester.pump();
              if (checkPixels) {
                await tester.pump(const Duration(milliseconds: 10));
                final drag = await tester.startGesture(point);
                await drag.moveBy(const Offset(70, 0));
                await tester.pump(const Duration(milliseconds: 20));
                await drag.up();
              }
              await tester.pump(const Duration(milliseconds: 500));
              await tester.pump();
              expect(navigator.currentState!.canPop(), isFalse);
              expect(observer.galleries, hasLength(expectedPushes));
              expect(articleOpens, 0);
              if (checkPixels) {
                for (var rapid = 0; rapid < 80; rapid++) {
                  await tester.tapAt(point);
                  await tester.pump();
                  await tester.pump(
                    Duration(milliseconds: [0, 1, 8, 16, 32, 60][rapid % 6]),
                  );
                  if (navigator.currentState!.canPop()) {
                    navigator.currentState!.pop();
                  }
                  if (rapid.isEven) await tester.pump();
                  await tester.tapAt(point);
                  if (rapid % 3 == 0 && navigator.currentState!.canPop()) {
                    navigator.currentState!.pop();
                  }
                  await tester.pump(
                    Duration(milliseconds: [0, 1, 8, 16][rapid % 4]),
                  );
                  expect(
                    tester.takeException(),
                    isNull,
                    reason:
                        'rapid cycle $rapid must not corrupt the Hero flight',
                  );
                }
                await tester.pump(const Duration(milliseconds: 500));
                await tester.pump();
                if (navigator.currentState!.canPop()) {
                  await _blueBounds(tester);
                  navigator.currentState!.pop();
                }
                await tester.pump(const Duration(milliseconds: 500));
                await tester.pump();
                expect(navigator.currentState!.canPop(), isFalse);
                expect(PhysicsSpringGalleryRoute.hasActiveRoutes, isFalse);
                expect(find.byType(ImageGalleryPage), findsNothing);
                final restored = await _blueBounds(tester);
                expect(restored.contains(point), isTrue);
                expect(
                  images.first.debugGetOpenHandleStackTraces()!.length,
                  initialHandles,
                  reason:
                      'closed flights must release their shared image handles',
                );
              }
              await tester.tap(find.text('article title'));
              await tester.pumpAndSettle();
              expect(
                articleOpens,
                1,
                reason: 'normal card navigation still works',
              );
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              for (final provider in providers) {
                imageCache.evict(provider);
              }
              for (final image in images) {
                image.dispose();
              }
            }
          },
        );
      }
    }
  }
}
