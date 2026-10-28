import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:review/features/detail/presentation/widgets/hdr_gallery_image.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/detail/presentation/widgets/image_gallery_page.dart';
import 'package:review/core/constants/api_constants.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/nine_grid_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;
  @override
  Future<String> getTemporaryPath() async => path;
}

class _HdrRangeAdapter implements HttpClientAdapter {
  _HdrRangeAdapter(
    this.responseBytes, {
    this.statusCode = 206,
    this.failures = 0,
    this.responseReady,
  });

  final List<int> responseBytes;
  final int statusCode;
  final int failures;
  final Future<void>? responseReady;
  int requests = 0;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    requests++;
    if (requests <= failures) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    await responseReady;
    return ResponseBody.fromBytes(responseBytes, statusCode);
  }

  @override
  void close({bool force = false}) {}
}

class _ImageStream extends ImageStreamCompleter {
  void frame(ui.Image image) => setImage(ImageInfo(image: image));
}

void main() {
  testWidgets('feed photo holds its decoded frame while its replacement loads', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final oldImage = await tester.runAsync(() => picture.toImage(16, 16));
    picture.dispose();
    const oldUrl = 'https://example.com/preview-old.gif';
    const newUrl = 'https://example.com/preview-new.gif';
    final oldProvider = ExtendedNetworkImageProvider(
      oldUrl,
      headers: ApiConstants.imageHeaders,
      cache: true,
    );
    final newProvider = ExtendedNetworkImageProvider(
      newUrl,
      headers: ApiConstants.imageHeaders,
      cache: true,
    );
    final oldStream = _ImageStream()..frame(oldImage!.clone());
    final pendingStream = _ImageStream();
    imageCache.putIfAbsent(oldProvider, () => oldStream);
    imageCache.putIfAbsent(newProvider, () => pendingStream);
    final currentPic = ValueNotifier(
      const WeiboPicModel(
        pid: 'stable-photo-id',
        thumbnail: oldUrl,
        large: oldUrl,
        original: oldUrl,
        isGif: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<WeiboPicModel>(
              valueListenable: currentPic,
              builder: (context, pic, _) => SizedBox(
                width: 220,
                height: 220,
                child: NineGridView(
                  statusId: 'gapless-feed-photo',
                  pics: [pic],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final image = find.byType(ExtendedImage);
    expect(
      (tester.state(image) as ExtendedImageState).extendedImageInfo,
      isNotNull,
    );
    currentPic.value = const WeiboPicModel(
      pid: 'stable-photo-id',
      thumbnail: newUrl,
      large: newUrl,
      original: newUrl,
      isGif: true,
    );
    await tester.pump();
    final imageState = tester.state(image) as ExtendedImageState;
    expect(
      (tester.widget<ExtendedImage>(image).image as ExtendedNetworkImageProvider)
          .url,
      newUrl,
    );
    expect(imageState.extendedImageInfo!.image.width, 16);
    final paintedImage = find.descendant(
      of: image,
      matching: find.byType(ExtendedRawImage),
    );
    expect(paintedImage, findsOneWidget);
    expect(
      tester.widget<ExtendedRawImage>(paintedImage).image,
      same(imageState.extendedImageInfo!.image),
    );
    final retainedBytes = await tester.runAsync(
      () => imageState.extendedImageInfo!.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ),
    );
    expect(retainedBytes!.buffer.asUint8List().sublist(0, 4), [0x21, 0x96, 0xf3, 0xff]);

    final nextRecorder = ui.PictureRecorder();
    Canvas(nextRecorder).drawColor(Colors.red, BlendMode.src);
    final nextPicture = nextRecorder.endRecording();
    final newImage = await tester.runAsync(() => nextPicture.toImage(16, 16));
    nextPicture.dispose();
    pendingStream.frame(newImage!.clone());
    await tester.pump();
    final replacement = (tester.state(image) as ExtendedImageState)
        .extendedImageInfo!.image;
    final replacementBytes = await tester.runAsync(
      () => replacement.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(
      replacementBytes!.buffer.asUint8List().sublist(0, 4),
      [0xf4, 0x43, 0x36, 0xff],
    );

    currentPic.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    imageCache.evict(oldProvider);
    imageCache.evict(newProvider);
    oldImage.dispose();
    newImage.dispose();
  });

  testWidgets('gallery inherits HDR badges for all known thumbnails without reprobes', (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final oldAdapter = hdrThumbnailProbeClient.httpClientAdapter;
    final adapter = _HdrRangeAdapter([0xff, 0xd8, ...latin1.encode('urn:iso:std:iso:ts:21496:-1')]);
    hdrThumbnailProbeClient.httpClientAdapter = adapter;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previousPlatform;
      hdrThumbnailProbeClient.httpClientAdapter = oldAdapter;
    });
    final pics = List.generate(3, (i) => WeiboPicModel(pid: 'known-gallery-$i',
      thumbnail: 'https://example.com/preview-$i.jpg',
      large: 'https://example.com/preview-$i.jpg',
      original: 'https://wx3.sinaimg.cn/large/known-gallery-$i.jpg'));
    await tester.runAsync(() async {
      for (final pic in pics) { expect(await cachedSinaHdrGainMapProbe(pic.originalUrl), isTrue); }
    });
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    await tester.pumpWidget(ProviderScope(overrides: [storageServiceProvider.overrideWithValue(storage)],
      child: MaterialApp(home: ImageGalleryPage(pics: pics, initialIndex: 0, statusId: 'known-hdr'))));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      expect(find.descendant(of: find.byKey(ValueKey('gallery-thumbnail-$i')),
        matching: find.byWidgetPredicate((w) => w is GalleryHdrBadge && w.thumbnail)), findsOneWidget);
    }
    expect(adapter.requests, 3, reason: 'opening the gallery must not probe known neighbors again');
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = previousPlatform;
  });

  testWidgets('gallery joins a pending feed HDR probe for an unselected image', (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final oldAdapter = hdrThumbnailProbeClient.httpClientAdapter;
    final ready = Completer<void>();
    final adapter = _HdrRangeAdapter([0xff, 0xd8, ...latin1.encode('urn:iso:std:iso:ts:21496:-1')], responseReady: ready.future);
    hdrThumbnailProbeClient.httpClientAdapter = adapter;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previousPlatform;
      hdrThumbnailProbeClient.httpClientAdapter = oldAdapter;
    });
    const url = 'https://wx3.sinaimg.cn/large/pending-gallery-hdr.jpg';
    final pending = cachedSinaHdrGainMapProbe(url);
    expect(pendingSinaHdrGainMapProbe(url), same(pending));
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    await tester.pumpWidget(ProviderScope(overrides: [storageServiceProvider.overrideWithValue(storage)],
      child: const MaterialApp(home: ImageGalleryPage(pics: [
        WeiboPicModel(pid: 'sdr', thumbnail: 'https://example.com/sdr.jpg', large: 'https://example.com/sdr.jpg', original: 'https://example.com/sdr.jpg'),
        WeiboPicModel(pid: 'pending', thumbnail: 'https://example.com/pending.jpg', large: 'https://example.com/pending.jpg', original: url),
      ], initialIndex: 0, statusId: 'pending-hdr'))));
    await tester.pump();
    expect(find.byType(GalleryHdrBadge), findsNothing);
    ready.complete();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(isKnownSinaHdrGainMap(url), isTrue);
    await tester.pump();
    expect(find.descendant(of: find.byKey(const ValueKey('gallery-thumbnail-1')),
      matching: find.byType(GalleryHdrBadge)), findsOneWidget);
    expect(adapter.requests, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = previousPlatform;
  });
  test(
    'gallery HDR warmup uses the exact cache file and shares both probes',
    () async {
      final dir = await Directory.systemTemp.createTemp('review-hdr-warmup');
      const url = 'https://wx3.sinaimg.cn/large/warmup.jpg';
      final oldPaths = PathProviderPlatform.instance;
      final oldAdapter = hdrThumbnailProbeClient.httpClientAdapter;
      PathProviderPlatform.instance = _TestPaths(dir.path);
      final rangeAdapter = _HdrRangeAdapter([
        0xff,
        0xd8,
        ...latin1.encode('urn:iso:std:iso:ts:21496:-1'),
      ]);
      hdrThumbnailProbeClient.httpClientAdapter = rangeAdapter;
      final cache = await Directory('${dir.path}/cacheimage').create();
      final file = File('${cache.path}/${keyToMd5(url)}');
      await file.writeAsBytes([0xff, 0xd8]);
      var calls = 0;
      final response = Completer<Map<String, dynamic>?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(hdrGalleryChannel, (call) {
            calls++;
            return response.future;
          });
      addTearDown(() async {
        PathProviderPlatform.instance = oldPaths;
        hdrThumbnailProbeClient.httpClientAdapter = oldAdapter;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(hdrGalleryChannel, null);
        await dir.delete(recursive: true);
      });

      final cached = await cachedHdrImageFile(url);
      expect(cached?.path, endsWith(keyToMd5(url)));
      expect(await cached?.exists(), isTrue);
      final first = primeCachedSinaHdrImage(url);
      final second = primeCachedSinaHdrImage(url);
      for (var attempt = 0; calls == 0 && attempt < 20; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(calls, 1);
      response.complete({'hasGainMap': true, 'displaySupported': true});
      expect(await first, {'hasGainMap': true, 'displaySupported': true});
      expect(await second, {'hasGainMap': true, 'displaySupported': true});
      expect(rangeAdapter.requests, 1);
    },
  );

  testWidgets('feed HDR badge matches GreenNote compact size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: GalleryHdrBadge(feed: true))),
    );
    final badge = tester.widget<Container>(
      find
          .ancestor(of: find.text('HDR'), matching: find.byType(Container))
          .first,
    );
    final text = tester.widget<Text>(find.text('HDR'));
    final decoration = badge.decoration! as BoxDecoration;
    expect(
      badge.padding,
      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    );
    expect(decoration.borderRadius, BorderRadius.circular(4));
    expect((decoration.border! as Border).top.width, .8);
    expect(text.style!.fontSize, 10);
    expect(text.style!.letterSpacing, .4);
  });

  Future<void> mountGrid(
    WidgetTester tester,
    String original, {
    int count = 1,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: NineGridView(
                statusId: 'cold-hdr',
                pics: [
                  for (var i = 0; i < count; i++)
                    WeiboPicModel(
                      pid: 'cold-hdr-$i',
                      thumbnail: 'https://example.com/preview-$i.jpg',
                      large: 'https://example.com/preview-$i.jpg',
                      original: original,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final hasHdr in [false, true]) {
    testWidgets('cold nine-grid shows HDR without opening ($hasHdr)', (
      tester,
    ) async {
      final ready = Completer<void>();
      final adapter = _HdrRangeAdapter([
        0xff,
        0xd8,
        ...latin1.encode(hasHdr ? 'urn:iso:std:iso:ts:21496:-1' : 'SDR'),
      ], responseReady: ready.future);
      final previousAdapter = hdrThumbnailProbeClient.httpClientAdapter;
      hdrThumbnailProbeClient.httpClientAdapter = adapter;
      final previousPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPaths(Directory.systemTemp.path);
      addTearDown(() {
        hdrThumbnailProbeClient.httpClientAdapter = previousAdapter;
        PathProviderPlatform.instance = previousPaths;
      });
      final url = 'https://wx3.sinaimg.cn/large/cold-$hasHdr.jpg';
      await mountGrid(tester, url, count: 9);
      await tester.pump();
      expect(find.text('HDR'), findsNothing);
      ready.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ImageGalleryPage), findsNothing);
      expect(find.text('HDR'), hasHdr ? findsNWidgets(9) : findsNothing);
      expect(await cachedSinaHdrGainMapProbe(url), hasHdr);
      expect(adapter.requests, 1, reason: 'the nine waiters share one request');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('failed cached HDR probe completes and permits a new request', () async {
    final adapter = _HdrRangeAdapter([
      0xff,
      0xd8,
      ...latin1.encode('urn:iso:std:iso:ts:21496:-1'),
    ], failures: 1);
    final previousAdapter = hdrThumbnailProbeClient.httpClientAdapter;
    hdrThumbnailProbeClient.httpClientAdapter = adapter;
    addTearDown(() {
      hdrThumbnailProbeClient.httpClientAdapter = previousAdapter;
    });
    const url = 'https://wx3.sinaimg.cn/large/retry-after-failure.jpg';
    expect(
      await cachedSinaHdrGainMapProbe(url).timeout(const Duration(seconds: 1)),
      isFalse,
    );
    expect(
      await cachedSinaHdrGainMapProbe(url).timeout(const Duration(seconds: 1)),
      isTrue,
    );
    expect(adapter.requests, 2);
  });

  test('HDR hints require a JPEG and known gain-map metadata', () {
    for (final marker in [
      'http://ns.adobe.com/hdr-gain-map/1.0/',
      'urn:iso:std:iso:ts:21496:-1',
    ]) {
      expect(
        mayContainHdrGainMap([0xff, 0xd8, ...latin1.encode(marker)]),
        isTrue,
      );
      expect(mayContainHdrGainMap(latin1.encode(marker)), isFalse);
    }
    expect(mayContainHdrGainMap([]), isFalse);
    expect(
      mayContainHdrGainMap([0xff, 0xd8, ...latin1.encode('HDR photograph')]),
      isFalse,
    );
  });

  test('feed HDR probe reads only a Sina large-image byte range', () async {
    final marker = latin1.encode('http://ns.adobe.com/hdr-gain-map/1.0/');
    const markerOffset = 96 * 1024;
    final adapter = _HdrRangeAdapter(
      List<int>.filled(markerOffset + marker.length, 0)
        ..[0] = 0xff
        ..[1] = 0xd8
        ..setRange(markerOffset, markerOffset + marker.length, marker),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    expect(
      await probeSinaHdrGainMap(dio, 'https://wx3.sinaimg.cn/large/sample.jpg'),
      isTrue,
    );
    expect(adapter.request?.headers['Range'], 'bytes=0-262143');
    expect(adapter.request?.headers.containsKey('Cookie'), isFalse);
    expect(
      await probeSinaHdrGainMap(dio, 'https://example.com/large/sample.jpg'),
      isFalse,
    );

    final ignoredRange = List<int>.filled(256 * 1024 + marker.length, 0)
      ..[0] = 0xff
      ..[1] = 0xd8
      ..setRange(256 * 1024, 256 * 1024 + marker.length, marker);
    final ignoredRangeAdapter = _HdrRangeAdapter(ignoredRange, statusCode: 200);
    final ignoredRangeDio = Dio()..httpClientAdapter = ignoredRangeAdapter;
    addTearDown(ignoredRangeDio.close);
    expect(
      await probeSinaHdrGainMap(
        ignoredRangeDio,
        'https://wx3.sinaimg.cn/large/sample.jpg',
      ),
      isFalse,
    );
  });

  const viewport = Rect.fromLTWH(0, 0, 1260, 2800);
  for (final size in [const Size(4000, 3000), const Size(3000, 4000)]) {
    test('HDR zoom preserves aspect and focal position for $size', () {
      final fitted = Alignment.center.inscribe(
        applyBoxFit(BoxFit.contain, size, viewport.size).destination,
        viewport,
      );
      for (final scale in [1.0, 2.5, 6.0]) {
        final target = Rect.fromLTWH(
          fitted.left - 130 * (scale - 1),
          fitted.top - 230 * (scale - 1),
          fitted.width * scale,
          fitted.height * scale,
        );
        final matrix = hdrImageViewTransform(viewport, target);
        final actual = MatrixUtils.transformRect(matrix, fitted);
        expect(matrix.entry(0, 0), closeTo(scale, 1e-8));
        expect(matrix.entry(1, 1), closeTo(scale, 1e-8));
        expect(actual.left, closeTo(target.left, 1e-8));
        expect(actual.top, closeTo(target.top, 1e-8));
        expect(actual.width, closeTo(target.width, 1e-8));
        expect(actual.height, closeTo(target.height, 1e-8));
      }
      expect(hdrImageViewTransform(viewport, null), Matrix4.identity());
    });
  }

  for (final hasGainMap in [false, true]) {
    testWidgets('only native-confirmed HDR is reported ($hasGainMap)', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('review-hdr-test'),
      ))!;
      const url = 'https://example.com/hdr-original.jpg';
      await tester.runAsync(() async {
        final cache = await Directory('${dir.path}/cacheimage').create();
        await File('${cache.path}/${keyToMd5(url)}').writeAsBytes([
          0xff,
          0xd8,
          ...latin1.encode('http://ns.adobe.com/hdr-gain-map/1.0/'),
        ]);
      });
      final messenger = tester.binding.defaultBinaryMessenger;
      final previousPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPaths(dir.path);
      var decodes = 0;
      messenger.setMockMethodCallHandler(hdrGalleryChannel, (call) async {
        expect(call.method, 'decode');
        decodes++;
        return {'hasGainMap': hasGainMap, 'displaySupported': false};
      });
      final rect = ValueNotifier<Rect?>(null);
      var detections = 0;
      addTearDown(() async {
        PathProviderPlatform.instance = previousPaths;
        messenger.setMockMethodCallHandler(hdrGalleryChannel, null);
        debugDefaultTargetPlatformOverride = null;
        rect.dispose();
        await dir.delete(recursive: true);
      });
      Widget overlay(bool active) => MaterialApp(
        home: HdrGalleryImage(
          url: url,
          active: active,
          imageRect: rect,
          onDetected: (supported) {
            expect(supported, isFalse);
            detections++;
          },
        ),
      );
      await tester.pumpWidget(overlay(false));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(decodes, 0);
      await tester.pumpWidget(overlay(true));
      for (var i = 0; i < 10 && decodes == 0; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(decodes, 1);
      expect(detections, hasGainMap ? 1 : 0);
      expect(find.byType(PlatformViewLink), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
