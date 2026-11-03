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
import 'package:review/features/detail/presentation/status_detail_page.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/tweet_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AvatarStream extends ImageStreamCompleter {
  void frame(ui.Image image) => setImage(ImageInfo(image: image));
}

void main() {
  testWidgets(
    'detail reuses decoded card avatar before and after author enrichment',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.init();
      final client = WeiboDioClient(storage);
      client.dio.interceptors.clear();
      const sourceUrl = 'https://example.com/source-avatar.jpg';
      final post = <String, dynamic>{
        'id': '123',
        'text_raw': '帖子正文',
        'created_at': '刚刚',
        'user': {'id': 'owner', 'screen_name': '楼主', 'avatar_large': sourceUrl},
      };
      final detail = Completer<Map<String, dynamic>>();
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) async {
            handler.resolve(
              Response(
                requestOptions: request,
                data: request.path.contains('/show')
                    ? await detail.future
                    : {'data': [], 'max_id': 0},
              ),
            );
          },
        ),
      );
      final image = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final result = await picture.toImage(48, 48);
        picture.dispose();
        return result;
      }))!;
      final provider = ExtendedNetworkImageProvider(
        sourceUrl,
        cache: true,
        headers: ApiConstants.imageHeaders,
      );
      imageCache.putIfAbsent(provider, () => _AvatarStream()..frame(image));
      addTearDown(() => imageCache.evict(provider));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            weiboDioClientProvider.overrideWithValue(client),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TweetCard(status: WeiboStatusModel.fromJson(post)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('帖子正文', findRichText: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      void expectCachedAvatar() {
        final avatar = find
            .descendant(
              of: find.byType(StatusDetailPage),
              matching: find.byType(AppAvatar),
            )
            .first;
        expect(tester.widget<AppAvatar>(avatar).url, sourceUrl);
        final rendered = find.descendant(
          of: avatar,
          matching: find.byType(ExtendedImage),
        );
        final state = tester.state(rendered) as ExtendedImageState;
        expect(state.extendedImageLoadState, LoadState.completed);
        expect(state.wasSynchronouslyLoaded, isTrue);
      }

      expectCachedAvatar();
      detail.complete({
        ...post,
        'user': {
          'id': 'owner',
          'screen_name': '更新后的楼主',
          'avatar_hd': 'https://example.com/detail-avatar.jpg',
          'verified': true,
          'verified_type': 0,
        },
      });
      await tester.pumpAndSettle();
      expectCachedAvatar();
      expect(find.text('更新后的楼主'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
