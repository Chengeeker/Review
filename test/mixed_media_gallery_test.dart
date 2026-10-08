import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
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
  final paused = <int>[];
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
  Future<void> pause(int playerId) async {
    paused.add(playerId);
  }
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

  testWidgets('video reel clears the progress bar and stays fixed during drag',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final scale in [1.0, 1.4]) {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(bottom: 28),
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: const ImageGalleryPage(
            pics: [_photo, _video, _photo],
            initialIndex: 1,
            statusId: 'layout',
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      final reel = tester.getRect(
          find.byKey(const ValueKey('gallery-thumbnail-strip')));
      final progress = tester.getRect(find.byType(VideoProgressIndicator));
      expect(reel.bottom, lessThan(progress.top));
      expect(tester.takeException(), isNull);
    }
    final progress = tester.getRect(find.byType(VideoProgressIndicator));
    await tester.tapAt(progress.center);
    await tester.pump();
    expect(backend.seeks, isNotEmpty);
    final reelFinder = find.byKey(const ValueKey('gallery-thumbnail-strip'));
    final reel = tester.getRect(reelFinder);
    final gesture = await tester.startGesture(reel.center);
    await gesture.moveBy(const Offset(-45, 0));
    await tester.pump();
    expect(tester.getRect(reelFinder).top, reel.top);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await _flushPlayerDisposal(tester);
    await tester.pump(const Duration(seconds: 1));
    debugNetworkImageHttpClientProvider = null;
    expect(tester.takeException(), isNull);
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

  testWidgets('mixed gallery keeps Live Photo paused until its control is used',
      (tester) async {
    final normalVideo = WeiboPicModel.fromJson({
      'pid': 'normal-video',
      'type': 'video',
      'video_url': 'https://video.weibo.com/media/normal.mp4',
    });
    expect(normalVideo.isVideo, isTrue);
    expect(normalVideo.isLivePhoto, isFalse);

    final videoFieldMp4 = WeiboPicModel.fromJson({
      'pid': 'video-field-mp4',
      'fid': 'must-not-become-livephoto',
      'video': 'https://video.weibo.com/media/clip.mp4',
      'thumbnail': {'url': 'https://example.com/clip-cover.jpg'},
    });
    expect(videoFieldMp4.isVideo, isTrue);
    expect(videoFieldMp4.isLivePhoto, isFalse);
    expect(videoFieldMp4.videoUrl,
        equals('https://video.weibo.com/media/clip.mp4'));
    expect(videoFieldMp4.livePhotoVideoUrl, isNull);

    final gif = WeiboPicModel.fromJson({
      'pid': 'gif-with-fid',
      'fid': 'must-not-become-livephoto',
      'thumbnail': {
        'url':
            'https://wx1.sinaimg.cn/orj360/62762bd0gy1ihtmluvbm6g20b406c7wr.gif?from=weibo',
      },
    });
    expect(gif.isGif, isTrue);
    expect(gif.isVideo, isFalse);
    expect(gif.isLivePhoto, isFalse);
    expect(gif.livePhotoVideoUrl, isNull);

    final gifWithConflictingMetadata = WeiboPicModel.fromJson({
      'pid': 'gif-with-stale-player-metadata',
      'type': 'video',
      'isVideo': true,
      'fid': 'must-not-become-livephoto',
      'livePhotoVideoUrl':
          'https://video.weibo.com/media/livephoto/stale.mp4',
      'thumbnail': {
        'url':
            'https://wx1.sinaimg.cn/orj360/62762bd0gy1ihtmluvbm6g20b406c7wr.gif?from=weibo',
      },
    });
    expect(gifWithConflictingMetadata.isGif, isTrue);
    expect(gifWithConflictingMetadata.isVideo, isFalse);
    expect(gifWithConflictingMetadata.isLivePhoto, isFalse);
    expect(gifWithConflictingMetadata.videoUrl, isNull);
    expect(gifWithConflictingMetadata.livePhotoVideoUrl, isNull);

    final mp4WithGifPoster = WeiboPicModel.fromJson({
      'pid': 'video-with-gif-preview',
      'type': 'video',
      'video_url': 'https://video.weibo.com/media/clip.mp4',
      'thumbnail': {
        'url': 'https://example.com/animated-poster.gif',
      },
    });
    expect(mp4WithGifPoster.isVideo, isTrue);
    expect(mp4WithGifPoster.isGif, isFalse);
    expect(mp4WithGifPoster.isLivePhoto, isFalse);

    final livePhoto = WeiboPicModel.fromJson({
      'pid': 'live-photo',
      'type': 'livephoto',
      'video_url': 'https://video.weibo.com/media/livephoto/live-photo.mp4',
      'thumbnail': {'url': 'https://example.com/live-photo.jpg'},
    });
    expect(livePhoto.isLivePhoto, isTrue);
    expect(livePhoto.isVideo, isFalse);

    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: ImageGalleryPage(
      pics: [_photo, livePhoto, _photo],
      initialIndex: 0,
      statusId: 'live-photo-test',
    ))));
    await tester.pump();
    final pager = tester.widget<ExtendedImageGesturePageView>(
        find.byType(ExtendedImageGesturePageView));
    pager.controller.jumpToPage(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('播放 Live 图'), findsOneWidget);
    expect(backend.played, isEmpty,
        reason: 'opening the Live Photo must not autoplay');
    final pauseCountBeforeTap = backend.paused.length;

    await tester.tap(find.text('播放 Live 图'));
    await tester.pump();
    expect(backend.played, hasLength(1));
    expect(find.text('暂停 Live 图'), findsOneWidget);

    await tester.tap(find.text('暂停 Live 图'));
    await tester.pump();
    expect(backend.paused, hasLength(pauseCountBeforeTap + 1));
    expect(find.text('播放 Live 图'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await _flushPlayerDisposal(tester);
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
