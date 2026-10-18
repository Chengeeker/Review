import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/core/utils/haptic_feedback_util.dart';
import 'package:review/core/widgets/cached_network_image.dart';
import 'package:review/features/detail/presentation/widgets/image_gallery_page.dart';
import 'package:review/features/drawer_features/data/chat_message_media.dart';
import 'package:review/features/drawer_features/presentation/chat_conversation_page.dart';
import 'package:review/features/drawer_features/presentation/my_messages_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review/features/feed/presentation/widgets/weibo_video_player_page.dart';
import 'package:review/features/detail/presentation/status_detail_page.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

Map<String, dynamic> _message(int id) => {
  'idstr': '$id',
  'id': id,
  'from_uid': '1',
  'sender_id': '1',
  'time': 1700000000 + id,
  'text': '记录$id',
  'content': '记录$id',
};

Future<(StorageService, WeiboDioClient)> _client(
  FutureOr<Object> Function(RequestOptions) respond,
) async {
  SharedPreferences.setMockInitialValues({
    StorageService.keyIsLoggedIn: true,
    StorageService.keyFullCookie: 'SUB=test-session',
    StorageService.keySubCookie: 'test-session',
    StorageService.keyUserUid: '42',
    StorageService.keyUserNickname: '我',
  });
  final storage = StorageService(await SharedPreferences.getInstance());
  final client = WeiboDioClient(storage);
  client.dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        handler.resolve(
          Response(requestOptions: options, data: await respond(options)),
        );
      },
    ),
  );
  addTearDown(() => client.dio.close(force: true));
  ChatConversationPage.globalUserCache['1'] = {'nick': '发言人', 'avatar': ''};
  addTearDown(ChatConversationPage.globalUserCache.clear);
  return (storage, client);
}

Future<void> _mount(
  WidgetTester tester,
  StorageService storage,
  WeiboDioClient client,
  Widget page,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        weiboDioClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

class _DecodedImage extends ImageStreamCompleter {
  _DecodedImage(ui.Image image) {
    setImage(ImageInfo(image: image));
  }
}

class _ChatVideoBackend extends VideoPlayerPlatform {
  final sources = <DataSource>[];
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    sources.add(options.dataSource);
    return sources.length;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 5),
      size: const Size(1920, 1080),
    ),
  );
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

void main() {
  for (final (isGroup, mediaType) in [
    (false, 10),
    (true, 10),
    (false, 5),
    (true, 5),
  ]) {
    testWidgets(
      '${isGroup ? 'group' : 'direct'} type $mediaType video resolves once, plays on tap with auth and gallery Hero',
      (tester) async {
        final oldBackend = VideoPlayerPlatform.instance;
        final backend = _ChatVideoBackend();
        VideoPlayerPlatform.instance = backend;
        addTearDown(() => VideoPlayerPlatform.instance = oldBackend);
        final calls = <RequestOptions>[];
        final message = {
          ..._message(10),
          'media_type': mediaType,
          'att_ids': 'original',
          'text': '分享视频',
          'content': '分享视频',
        };
        final (storage, client) = await _client((options) {
          if (options.path.endsWith('meta_query.json')) {
            calls.add(options);
            return '__review_video_meta({"extension":"mp4","fid":"${options.queryParameters['replace'] == 'true' ? 'playable' : 'original'}","videosize":"1920*1080"});';
          }
          return {
            isGroup ? 'messages' : 'direct_messages': [message],
          };
        });
        await _mount(
          tester,
          storage,
          client,
          ChatConversationPage(
            targetId: '1',
            targetName: '会话',
            targetAvatar: '',
            isGroup: isGroup,
          ),
        );
        expect(find.text('分享视频'), findsNothing);
        expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
        expect(calls.map((c) => c.queryParameters['replace']), [
          'false',
          'true',
        ]);
        expect(
          calls.every(
            (c) => c.headers['Cookie'].toString().contains('SUB=test-session'),
          ),
          isTrue,
        );
        expect(backend.sources, isEmpty);
        await tester.pump();
        expect(calls, hasLength(2));
        await tester.tap(find.byIcon(Icons.play_circle_fill_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(ImageGalleryPage), findsOneWidget);
        expect(find.byType(WeiboVideoPlayerPage), findsOneWidget);
        expect(backend.sources, hasLength(1));
        expect(
          Uri.parse(backend.sources.single.uri!).queryParameters['fid'],
          'playable',
        );
        expect(
          backend.sources.single.httpHeaders['Cookie'],
          contains('SUB=test-session'),
        );
        final gallery = tester.widget<ImageGalleryPage>(
          find.byType(ImageGalleryPage),
        );
        expect(gallery.statusId, isEmpty);
        final tag = ImageGalleryHeroTag.forPic(
          scope: gallery.heroScope!,
          index: 0,
          pic: gallery.pics.single,
        );
        expect(
          find.byWidgetPredicate((w) => w is Hero && w.tag == tag),
          findsNWidgets(2),
        );
        Navigator.of(tester.element(find.byType(ImageGalleryPage))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(ImageGalleryPage), findsNothing);
        expect(backend.sources, hasLength(1));
        expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
        expect(calls, hasLength(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  for (final isGroup in [false, true]) {
    testWidgets(
      '${isGroup ? 'group' : 'direct'} visible URL loads the official card once',
      (tester) async {
        var cardRequests = 0;
        final message = {
          ..._message(10),
          'text': 'https://t.cn/card',
          'content': 'https://t.cn/card',
        };
        final complete = {
          'url_objects': [
            {
              'info': {'url_short': 'https://t.cn/card'},
              'status': {
                'idstr': '5345552066939360',
                'user': {'screen_name': '数码小凡'},
                'text': '还原 Siri 唤醒动画',
              },
            },
          ],
        };
        final (storage, client) = await _client((options) {
          if (options.path.endsWith('show_batch.json') ||
              options.path.endsWith('query_message.json')) {
            cardRequests++;
            return isGroup ? {'message': complete} : [complete];
          }
          return {
            isGroup ? 'messages' : 'direct_messages': [message],
          };
        });
        await _mount(
          tester,
          storage,
          client,
          ChatConversationPage(
            targetId: '1',
            targetName: '会话',
            targetAvatar: '',
            isGroup: isGroup,
          ),
        );
        expect(find.text('数码小凡'), findsOneWidget);
        expect(find.text('还原 Siri 唤醒动画'), findsOneWidget);
        expect(cardRequests, 1);
        final card = tester.widget<InkWell>(
          find
              .ancestor(of: find.text('数码小凡'), matching: find.byType(InkWell))
              .first,
        );
        card.onTap!();
        await tester.pumpAndSettle();
        expect(find.byType(StatusDetailPage), findsOneWidget);
        await tester.pump();
        expect(cardRequests, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('WebIM images parse attachment lists and GIF metadata without treating files as photos', () {
    final urls = chatMessageImageUrls({
      'media_type': 1,
      'att_ids': '123,456,123',
    });
    expect(urls, hasLength(2));
    expect(Uri.parse(urls.first).queryParameters, {
      'source': '209678993',
      'fid': '123',
      'imageType': 'origin',
    });
    expect(
      chatMessageImageUrls({
        'media_type': '1',
        'fids': ['789'],
      }),
      hasLength(1),
    );
    expect(
      chatMessageImageUrls({
        'media_type': 5,
        'att_ids': ['document'],
      }),
      isEmpty,
    );
    expect(
      chatMessageImageUrls({
        'pic_infos': [
          {'original_pic': '//wx1.sinaimg.cn/large/photo.gif'},
          {'original_pic': 'javascript:bad'},
        ],
      }),
      ['https://wx1.sinaimg.cn/large/photo.gif'],
    );
  });

  test(
    'private media credentials are restricted to HTTPS WebIM media endpoint',
    () async {
      final (_, client) = await _client((_) => {});
      expect(
        client.imageHeadersForUrl(
          'https://upload.api.weibo.com/2/mss/msget?fid=123',
        )['Cookie'],
        'SUB=test-session',
      );
      for (final url in [
        'https://wx1.sinaimg.cn/large/p.jpg',
        'https://upload.api.weibo.com.evil.test/2/mss/msget',
        'http://upload.api.weibo.com/2/mss/msget',
        'https://upload.api.weibo.com/other',
      ]) {
        expect(client.imageHeadersForUrl(url).containsKey('Cookie'), isFalse);
      }
    },
  );

  testWidgets('message list does not inherit a second status bar gap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (storage, client) = await _client(
      (_) => {
        'contacts': [
          {
            'user': {'id': '1', 'name': '示例会话'},
            'message': {'text': '最近消息'},
          },
        ],
      },
    );
    await _mount(
      tester,
      storage,
      client,
      const MediaQuery(
        data: MediaQueryData(
          size: Size(430, 1000),
          padding: EdgeInsets.only(top: 100),
        ),
        child: MyMessagesPage(),
      ),
    );
    final title = tester.getRect(find.text('私信与群聊'));
    final contact = tester.getRect(find.text('示例会话'));
    expect(contact.top - title.bottom, lessThan(65));
    expect(tester.takeException(), isNull);
  });

  for (final isGroup in [false, true]) {
    testWidgets(
      '${isGroup ? 'group' : 'direct'} history prefetches, deduplicates, preserves position and stops',
      (tester) async {
        final requests = <RequestOptions>[];
        final olderResponse = Completer<Map<String, dynamic>>();
        final field = isGroup ? 'messages' : 'direct_messages';
        final cursor = isGroup ? 'max_mid' : 'max_id';
        final (storage, client) = await _client((options) {
          requests.add(options);
          if (requests.length == 1) {
            return {
              field: [for (var id = 161; id <= 200; id++) _message(id)],
            };
          }
          if (requests.length == 2) return olderResponse.future;
          if (requests.length > 3) return {field: <dynamic>[]};
          return {
            field: [for (var id = 110; id <= 121; id++) _message(id)],
          };
        });
        await _mount(
          tester,
          storage,
          client,
          ChatConversationPage(
            targetId: '1',
            targetName: '会话',
            targetAvatar: '',
            isGroup: isGroup,
          ),
        );
        expect(requests, hasLength(1));
        expect(
          tester.getTopLeft(find.text('记录199')).dy,
          lessThan(tester.getTopLeft(find.text('记录200')).dy),
        );
        final controller = tester
            .widget<ListView>(find.byType(ListView))
            .controller!;
        controller.jumpTo(controller.position.maxScrollExtent - 300);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(requests, hasLength(2));
        expect(requests.last.queryParameters[cursor], '160');
        controller.jumpTo(controller.offset + 1);
        await tester.pump();
        expect(
          requests,
          hasLength(2),
          reason: 'only one older request may be in flight',
        );
        final offset = controller.offset;
        olderResponse.complete({
          field: [for (var id = 122; id <= 161; id++) _message(id)],
        });
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(offset, .1));
        final list = tester.widget<ListView>(find.byType(ListView));
        final delegate = list.childrenDelegate as SliverChildBuilderDelegate;
        expect(
          delegate.childCount,
          80,
          reason: '40 original + 39 older + status; duplicate 161 removed',
        );
        controller.jumpTo(controller.position.maxScrollExtent - 300);
        await tester.pumpAndSettle();
        expect(requests, hasLength(3));
        expect(requests.last.queryParameters[cursor], '121');
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(requests, hasLength(4));
        expect(requests.last.queryParameters[cursor], '109');
        expect(find.text('已到最早消息'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed history keeps messages and retries the same cursor without looping',
    (tester) async {
      final cursors = <String>[];
      var fail = true;
      final (storage, client) = await _client((options) {
        final cursor = options.queryParameters['max_mid']?.toString() ?? '0';
        if (cursor == '0') {
          return {
            'messages': [for (var i = 61; i <= 100; i++) _message(i)],
          };
        }
        cursors.add(cursor);
        if (cursor == '59') return {'messages': <dynamic>[]};
        return fail
            ? {'error': 'expired', 'error_code': 21301}
            : {
                'messages': [_message(60)],
              };
      });
      await _mount(
        tester,
        storage,
        client,
        const ChatConversationPage(
          targetId: '1',
          targetName: '会话',
          targetAvatar: '',
          isGroup: true,
        ),
      );
      final controller = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(cursors, ['60']);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(cursors, ['60']);
      expect(find.text('记录61'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('历史消息加载失败，点击重试'));
      await tester.pumpAndSettle();
      expect(cursors.take(2), ['60', '60']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short server pages still prefetch until the server returns no older messages',
    (tester) async {
      final cursors = <String>[];
      final (storage, client) = await _client((options) {
        final cursor = options.queryParameters['max_id']?.toString() ?? '0';
        cursors.add(cursor);
        return {
          'direct_messages': cursor == '0'
              ? [for (var id = 61; id <= 80; id++) _message(id)]
              : cursor == '60'
              ? [for (var id = 51; id <= 60; id++) _message(id)]
              : <dynamic>[],
        };
      });
      await _mount(
        tester,
        storage,
        client,
        const ChatConversationPage(
          targetId: '1',
          targetName: '会话',
          targetAvatar: '',
        ),
      );
      final controller = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      controller.jumpTo(controller.position.maxScrollExtent - 200);
      await tester.pumpAndSettle();
      expect(cursors.take(2), ['0', '60']);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(cursors, ['0', '60', '50']);
      expect(find.text('已到最早消息'), findsOneWidget);
    },
  );

  testWidgets(
    'private image paints decoded pixels and opens the shared gallery',
    (tester) async {
      final hapticCalls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final wasHapticsEnabled = HapticFeedbackUtil.isEnabled;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        hapticCalls.add(call);
        return null;
      });
      HapticFeedbackUtil.isEnabled = true;
      HapticFeedbackUtil.resetForTesting();
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        HapticFeedbackUtil.isEnabled = wasHapticsEnabled;
        HapticFeedbackUtil.resetForTesting();
      });
      final message = {
        ..._message(1),
        'media_type': 1,
        'att_ids': ['photo-1'],
        'text': '分享图片',
      };
      final url = chatMessageImageUrls(message).single;
      final (storage, client) = await _client(
        (_) => {
          'direct_messages': [message],
        },
      );
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = (await tester.runAsync(() => picture.toImage(120, 240)))!;
      picture.dispose();
      final provider = ExtendedImage.network(
        url,
        cache: true,
        cacheWidth: (220 * tester.view.devicePixelRatio).round().clamp(1, 1024),
        headers: client.imageHeadersForUrl(url),
      ).image;
      final fullProvider = ExtendedNetworkImageProvider(url, cache: true);
      imageCache.putIfAbsent(fullProvider, () => _DecodedImage(image.clone()));
      addTearDown(() => imageCache.evict(fullProvider));
      final providerKey = await provider.obtainKey(ImageConfiguration.empty);
      imageCache.putIfAbsent(providerKey, () => _DecodedImage(image));
      addTearDown(() => imageCache.evict(providerKey));
      await _mount(
        tester,
        storage,
        client,
        const ChatConversationPage(
          targetId: '1',
          targetName: '会话',
          targetAvatar: '',
        ),
      );
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(
        tester
            .widgetList<ExtendedRawImage>(find.byType(ExtendedRawImage))
            .any((w) => w.image != null),
        isTrue,
      );
      expect(find.text('[图片]'), findsNothing);
      expect(find.text('分享图片'), findsNothing);
      final imageSize = tester.getSize(find.byType(CachedNetworkImage));
      expect(imageSize.width / imageSize.height, closeTo(.5, .01));
      final bubble = tester.widget<Container>(
        find.byKey(const ValueKey('chat-message-content-1')),
      );
      expect(bubble.padding, const EdgeInsets.all(4));
      await tester.tap(find.byType(CachedNetworkImage));
      await tester.pumpAndSettle();
      final feedback = hapticCalls
          .where((call) => call.method == 'HapticFeedback.vibrate')
          .toList();
      expect(feedback, hasLength(1));
      expect(feedback.single.arguments, 'HapticFeedbackType.lightImpact');
      expect(find.byType(ImageGalleryPage), findsOneWidget);
      final gallery = tester.widget<ImageGalleryPage>(
        find.byType(ImageGalleryPage),
      );
      expect(gallery.heroScope, isNotNull);
      final heroTag = ImageGalleryHeroTag.forPic(
        scope: gallery.heroScope!,
        index: 0,
        pic: gallery.pics.single,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == heroTag,
        ),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
