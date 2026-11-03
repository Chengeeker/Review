import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/detail/presentation/widgets/image_gallery_page.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/nine_grid_view.dart';
import 'package:review/features/feed/presentation/widgets/tweet_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _shortUrl = 'http://t.cn/AXYhzyFV';
const _outerPid = '62762bd0gy1iip88sql5aj235s2pk7wh';
const _innerPid = '005IO4S6ly1iip2dlinj9j31yb22vqen';

// Reduced attachment structure from the reported response; no account session.
Map<String, dynamic> _repost() => {
  'id': '5361250647148996',
  'text_raw': '作者附言 $_shortUrl',
  'text':
      '作者附言 <a data-pid=$_outerPid href="https://wx2.sinaimg.cn/large/$_outerPid.jpg">'
      '<img title="$_shortUrl" src="https://h5.sinaimg.cn/photo-icon.png"/>查看图片</a>',
  'user': {'id': 'outer', 'screen_name': '附图作者'},
  'pic_ids': [],
  'url_struct': [
    {
      'url_title': '查看图片',
      'url_type': 39,
      'short_url': _shortUrl,
      'ori_url':
          'https://photo.weibo.com/h5/repost/reppic_id/1022:attached-photo',
      'result': false,
      'pic_ids': [_outerPid],
      'pic_infos': {
        _outerPid: {
          'thumbnail': {
            'url': 'http://wx2.sinaimg.cn/thumbnail/$_outerPid.jpg',
            'width': 120,
            'height': 102,
          },
          'large': {
            'url': 'http://wx2.sinaimg.cn/large/$_outerPid.jpg',
            'width': 2048,
            'height': 1756,
          },
          'woriginal': {
            'url': 'http://wx2.sinaimg.cn/woriginal/$_outerPid.jpg',
            'width': 2048,
            'height': 1756,
          },
        },
      },
    },
  ],
  'retweeted_status': {
    'id': '5361199610333809',
    'text_raw': '原帖正文',
    'user': {'id': 'inner', 'screen_name': '原作者'},
    'pic_ids': [_innerPid],
    'pic_infos': {
      _innerPid: {
        'large': {'url': 'https://wx1.sinaimg.cn/large/$_innerPid.jpg'},
      },
    },
  },
};

void main() {
  test(
    'a repost photo link becomes the outer photo without moving quoted media',
    () {
      final status = WeiboStatusModel.fromJson(_repost());
      expect(status.pics.single.pid, _outerPid);
      expect(
        status.pics.single.originalUrl,
        'https://wx2.sinaimg.cn/large/$_outerPid.jpg',
      );
      expect(status.pics.single.isWebpageCard, isFalse);
      expect(status.textRaw, '作者附言');
      expect(status.retweetedStatus!.pics.single.pid, _innerPid);
      final restored = WeiboStatusModel.fromJson(status.toJson());
      expect(restored.pics.single.pid, _outerPid);
      expect(restored.retweetedStatus!.pics.single.pid, _innerPid);
    },
  );

  test('unreferenced inherited cards and short URL prefixes stay out of the wrapper', () {
    for (final text in ['普通转发附言', '${_shortUrl}Suffix']) {
      final raw = _repost()..remove('text');
      raw['text_raw'] = text;
      final status = WeiboStatusModel.fromJson(raw);
      expect(status.pics, isEmpty);
      expect(status.textRaw, text);
      expect(status.retweetedStatus!.pics.single.pid, _innerPid);
    }
  });

  test(
    'link ownership handles HTTPS, zero-width text and HTML-only responses',
    () {
      for (final htmlOnly in [false, true]) {
        final raw = _repost();
        if (htmlOnly) {
          raw.remove('text_raw');
        } else {
          raw.remove('text');
          raw['text_raw'] =
              '作者附言 ${_shortUrl.replaceFirst('http:', 'https:')}\u200b';
        }
        expect(WeiboStatusModel.fromJson(raw).pics.single.pid, _outerPid);
      }
    },
  );

  test('a photo link without real photo data stays readable', () {
    final raw = _repost();
    (raw['url_struct'] as List).single.remove('pic_infos');
    final status = WeiboStatusModel.fromJson(raw);
    expect(status.pics, isEmpty);
    expect(status.textRaw, contains(_shortUrl));
  });

  for (final isDetail in [false, true]) {
    testWidgets(
      'own and quoted photos render separately and open the right gallery, detail=$isDetail',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final storage = await StorageService.init();
        final status = WeiboStatusModel.fromJson(_repost());
        tester.view.physicalSize = const Size(430, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [storageServiceProvider.overrideWithValue(storage)],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: TweetCard(status: status, isDetail: isDetail),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final grids = find.byType(NineGridView);
        expect(grids, findsNWidgets(2));
        expect(
          tester.widget<NineGridView>(grids.at(0)).pics.single.pid,
          _outerPid,
        );
        expect(
          tester.widget<NineGridView>(grids.at(1)).pics.single.pid,
          _innerPid,
        );
        expect(find.text('查看图片', findRichText: true), findsNothing);
        final source = find
            .descendant(
              of: grids.first,
              matching: find.byWidgetPredicate(
                (widget) => widget is GestureDetector && widget.onTap != null,
              ),
            )
            .first;
        await tester.tap(source);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          tester
              .widget<ImageGalleryPage>(find.byType(ImageGalleryPage))
              .pics
              .single
              .pid,
          _outerPid,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
