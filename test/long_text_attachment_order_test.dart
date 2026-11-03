import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/nine_grid_view.dart';
import 'package:review/features/feed/presentation/widgets/tweet_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('main and repost long-text controls appear before image grids', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    const image = WeiboPicModel(
      pid: 'long-text-order-image',
      thumbnail: 'https://example.com/photo.jpg',
      large: 'https://example.com/photo.jpg',
      original: 'https://example.com/photo.jpg',
    );
    final fullText = List.filled(80, '这是用于验证正文展开按钮与图片顺序的内容').join();
    final repost = WeiboStatusModel(
      id: 'long-text-order-repost',
      mid: 'long-text-order-repost',
      isLongText: true,
      textRaw: '转发正文预览',
      fullTextRaw: fullText,
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: const WeiboUserModel(id: '200', screenName: '原作者', avatar: ''),
      pics: const [image],
    );
    final status = WeiboStatusModel(
      id: 'long-text-order-main',
      mid: 'long-text-order-main',
      isLongText: true,
      textRaw: '主微博正文预览',
      fullTextRaw: fullText,
      createdAt: '刚刚',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: const WeiboUserModel(id: '100', screenName: '转发者', avatar: ''),
      pics: const [image],
      retweetedStatus: repost,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: TweetCard(status: status)),
          ),
        ),
      ),
    );

    final toggles = find.text('展开全文');
    final imageGrids = find.byType(NineGridView);
    expect(toggles, findsNWidgets(2));
    expect(imageGrids, findsNWidgets(2));
    for (var index = 0; index < 2; index++) {
      expect(
        tester.getTopLeft(toggles.at(index)).dy,
        lessThan(tester.getTopLeft(imageGrids.at(index)).dy),
      );
    }
  });
}
