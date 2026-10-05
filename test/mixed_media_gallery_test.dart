import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/features/detail/presentation/widgets/image_gallery_page.dart';
import 'package:review/features/feed/presentation/widgets/weibo_video_player_page.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
// Existing video_player backend is replaced only for lifecycle/gesture tests.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

const _photo = WeiboPicModel(
    pid: 'photo',
    thumbnail: 'https://example.com/photo.jpg',
    large: 'https://example.com/photo.jpg',
    original: 'https://example.com/photo.jpg');
const _video = WeiboPicModel(
    pid: 'video',
    thumbnail: 'https://example.com/cover.jpg',
    large: 'https://example.com/cover.jpg',
    original: 'https://example.com/cover.jpg',
    isVideo: true,
    videoUrl: 'https://example.com/video.mp4');

class _ImageClient implements HttpClient {
  _ImageClient(this.bytes);
  final Uint8List bytes;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _ImageRequest(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ImageRequest implements HttpClientRequest {
  _ImageRequest(this.bytes);
  final Uint8List bytes;
  @override
  HttpHeaders get headers => _ImageHeaders();
  @override
  Future<HttpClientResponse> close() async => _ImageResponse(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ImageHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  _ImageResponse(this.bytes);
  final Uint8List bytes;
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(bytes).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeVideoPlatform extends VideoPlayerPlatform {
  final created = <int>[];
  final played = <int>[];
  final disposed = <int>[];
  final seeks = <Duration>[];
  bool delayInitialization = false;
  final pendingEvents = StreamController<VideoEvent>();
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = created.length + 1;
    created.add(id);
    return id;
  }

  VideoEvent get initialized => VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 60),
      size: const Size(1920, 1080));
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    if (delayInitialization) return pendingEvents.stream;
    final events = StreamController<VideoEvent>.broadcast();
    scheduleMicrotask(() => events.add(initialized));
    return events.stream;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> play(int playerId) async {
    played.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add(position);
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => ColoredBox(
      key: ValueKey('fake-video-${options.playerId}'), color: Colors.blue);
}

Future<void> _flushPlayerDisposal(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
}

void main() {
  late _FakeVideoPlatform backend;
  setUp(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
    final originalClient = debugNetworkImageHttpClientProvider;
    debugNetworkImageHttpClientProvider = () => _ImageClient(bytes);
    addTearDown(() {
      debugNetworkImageHttpClientProvider = originalClient;
    });
    final original = VideoPlayerPlatform.instance;
    backend = _FakeVideoPlatform();
    VideoPlayerPlatform.instance = backend;
    addTearDown(() {
      VideoPlayerPlatform.instance = original;
      unawaited(backend.pendingEvents.close());
    });
  });

  testWidgets(
      'mixed gallery plays only selected video and horizontal swipe changes media, not seek',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
            home: ImageGalleryPage(
      pics: [_photo, _video, _photo, _video],
      initialIndex: 0,
      statusId: 'mixed',
    ))));
    await tester.pump();
    expect(backend.created, isEmpty);
    final pager = tester.widget<ExtendedImageGesturePageView>(
        find.byType(ExtendedImageGesturePageView));
    pager.controller.jumpToPage(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(WeiboVideoPlayerPage), findsOneWidget);
    expect(
        tester
            .widget<WeiboVideoPlayerPage>(find.byType(WeiboVideoPlayerPage))
            .embedded,
        isTrue);
    expect(backend.played, [1]);
    final playerState = tester.state(find.byType(WeiboVideoPlayerPage));
    expect(find.byKey(const ValueKey('fake-video-1')), findsOneWidget);
    await tester.fling(
        find.byType(WeiboVideoPlayerPage), const Offset(-500, 0), 1800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('3 / 4'), findsOneWidget);
    expect(find.byType(WeiboVideoPlayerPage), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(playerState.mounted, isFalse,
        reason: 'Offscreen player must unmount');
    await _flushPlayerDisposal(tester);
    expect(backend.disposed, contains(1));
    expect(backend.seeks, isEmpty);
    await tester.tap(find.byKey(const ValueKey('gallery-thumbnail-3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(backend.played, [1, 2]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await _flushPlayerDisposal(tester);
    expect(backend.disposed, contains(2));
    await tester.pump(const Duration(seconds: 1));
    await _flushPlayerDisposal(tester);
    debugNetworkImageHttpClientProvider = null;
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'leaving video while initialization is pending never starts hidden playback',
      (tester) async {
    backend.delayInitialization = true;
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
            home: ImageGalleryPage(
                pics: [_photo, _video, _photo],
                initialIndex: 1,
                statusId: 'pending'))));
    await tester.pump();
    final pager = tester.widget<ExtendedImageGesturePageView>(
        find.byType(ExtendedImageGesturePageView));
    pager.controller.jumpToPage(2);
    await tester.pump();
    backend.pendingEvents.add(backend.initialized);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(backend.played, isEmpty);
    expect(find.byType(WeiboVideoPlayerPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await _flushPlayerDisposal(tester);
    await tester.pump(const Duration(seconds: 1));
    await _flushPlayerDisposal(tester);
    debugNetworkImageHttpClientProvider = null;
    expect(tester.takeException(), isNull);
  });
}
