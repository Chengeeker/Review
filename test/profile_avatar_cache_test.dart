import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/constants/api_constants.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/core/widgets/app_avatar.dart';
import 'package:review/features/feed/data/feed_repository.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/tweet_card.dart';
import 'package:review/features/profile/presentation/user_profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AvatarStream extends ImageStreamCompleter {
  void frame(ui.Image image) => setImage(ImageInfo(image: image));
  void fail() => reportError(exception: StateError('offline'), silent: true);
}

class _EmptyFeed extends FeedRepository {
  _EmptyFeed(super.client, super.storage);
  @override
  Future<List<WeiboStatusModel>> getUserTimeline({
    required String uid,
    int page = 1,
    int feature = 0,
    bool resolveLongText = true,
  }) async => [];
}

ExtendedNetworkImageProvider _provider(String url) =>
    ExtendedNetworkImageProvider(
      url,
      cache: true,
      headers: ApiConstants.imageHeaders,
    );

Future<ui.Image> _cacheAvatar(WidgetTester tester, String url) async {
  final image = (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final result = await picture.toImage(64, 64);
    picture.dispose();
    return result;
  }))!;
  final provider = _provider(url);
  imageCache.putIfAbsent(provider, () => _AvatarStream()..frame(image.clone()));
  addTearDown(() {
    imageCache.evict(provider);
    image.dispose();
  });
  return image;
}

void main() {
  for (final ownAccount in [false, true]) {
    testWidgets(
      'profile reuses the source avatar through late profile data and reentry, ownAccount=$ownAccount',
      (tester) async {
        const sourceUrl = 'https://example.com/profile-source.jpg';
        final uid = ownAccount ? 'profile-cache-self' : 'profile-cache-user';
        SharedPreferences.setMockInitialValues({
          if (ownAccount) ...{
            StorageService.keyIsLoggedIn: true,
            StorageService.keyUserUid: uid,
            StorageService.keyUserNickname: '作者',
            StorageService.keyUserAvatar: sourceUrl,
          },
        });
        final storage = await StorageService.init();
        final client = WeiboDioClient(storage);
        client.dio.interceptors.clear();
        var response = Completer<Map<String, dynamic>>();
        client.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) async {
              handler.resolve(
                Response(requestOptions: request, data: await response.future),
              );
            },
          ),
        );
        final sourceImage = await _cacheAvatar(tester, sourceUrl);
        final post = WeiboStatusModel.fromJson({
          'id': '123',
          'text_raw': '帖子正文',
          'user': {'id': uid, 'screen_name': '作者', 'avatar_large': sourceUrl},
        });
        final profile = <String, dynamic>{
          'ok': 1,
          'data': {
            'user': {
              'id': post.user.id,
              'screen_name': '新昵称',
              'avatar_hd': 'https://example.com/profile-hd.jpg',
              'description': '最新资料',
              'verified': true,
              'verified_type': 0,
            },
          },
        };
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              storageServiceProvider.overrideWithValue(storage),
              weiboDioClientProvider.overrideWithValue(client),
              feedRepositoryProvider.overrideWithValue(
                _EmptyFeed(client, storage),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ownAccount
                    ? Builder(
                        builder: (context) => AppAvatar(
                          url: sourceUrl,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => UserProfilePage(uid: uid),
                            ),
                          ),
                        ),
                      )
                    : TweetCard(status: post),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        void expectCachedHeader() {
          final header = find
              .descendant(
                of: find.byType(UserProfilePage),
                matching: find.byType(AppAvatar),
              )
              .first;
          expect(tester.widget<AppAvatar>(header).url, sourceUrl);
          final image = find.descendant(
            of: header,
            matching: find.byType(ExtendedImage),
          );
          final state = tester.state(image) as ExtendedImageState;
          expect(state.extendedImageLoadState, LoadState.completed);
          expect(state.wasSynchronouslyLoaded, isTrue);
          expect(state.extendedImageInfo!.image.isCloneOf(sourceImage), isTrue);
        }

        for (var visit = 0; visit < 2; visit++) {
          if (visit > 0) response = Completer<Map<String, dynamic>>();
          await tester.tap(find.byType(AppAvatar).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 30));
          expectCachedHeader();
          response.complete(profile);
          await tester.pumpAndSettle();
          expectCachedHeader();
          expect(find.text('最新资料'), findsOneWidget);
          Navigator.of(tester.element(find.byType(UserProfilePage))).pop();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'profile avatar keeps its decoded frame on slow or failed replacement and resets by identity',
    (tester) async {
      const sourceUrl = 'https://example.com/avatar-before-refresh.jpg';
      const replacementUrl = 'https://example.com/avatar-pending.jpg';
      const otherUrl = 'https://example.com/avatar-other-user.jpg';
      final image = await _cacheAvatar(tester, sourceUrl);
      final pending = _AvatarStream();
      imageCache.putIfAbsent(_provider(replacementUrl), () => pending);
      imageCache.putIfAbsent(_provider(otherUrl), () => _AvatarStream());
      addTearDown(() {
        imageCache.evict(_provider(replacementUrl));
        imageCache.evict(_provider(otherUrl));
      });
      var uid = 'owner';
      var url = sourceUrl;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return AppAvatar(
                key: ValueKey(uid),
                url: url,
                gaplessPlayback: true,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      rebuild(() => url = replacementUrl);
      await tester.pump();
      var state =
          tester.state(find.byType(ExtendedImage)) as ExtendedImageState;
      expect(state.extendedImageInfo!.image.isCloneOf(image), isTrue);
      pending.fail();
      await tester.pump();
      final raw = tester.widget<RawImage>(find.byType(RawImage));
      expect(raw.image!.isCloneOf(image), isTrue);
      rebuild(() {
        uid = 'another-user';
        url = otherUrl;
      });
      await tester.pump();
      state = tester.state(find.byType(ExtendedImage)) as ExtendedImageState;
      expect(state.extendedImageInfo, isNull);
      expect(state.extendedImageLoadState, LoadState.loading);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
