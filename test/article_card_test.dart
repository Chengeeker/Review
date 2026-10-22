import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/services/link_routing_service.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/core/utils/weibo_article_link.dart';
import 'package:review/features/detail/presentation/weibo_article_page.dart';
import 'package:review/features/detail/presentation/widgets/image_gallery_page.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/nine_grid_view.dart';
import 'package:review/features/feed/presentation/widgets/tweet_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _articleId = '2309405350630165316501';
const _articleUrl = 'https://weibo.com/ttarticle/p/show?id=$_articleId';
const _cover = 'https://wx1.sinaimg.cn/large/article-cover.jpg';
const _shortUrl = 'https://t.cn/article-test';

Map<String, dynamic> _status(Map<String, dynamic> payload) => {
      'id': '5350630165316501',
      'mid': '5350630165316501',
      'text_raw': '发布了文章 $_shortUrl',
      'created_at': '刚刚',
      'user': {'id': '6593199887', 'screen_name': '测试作者'},
      ...payload,
    };

Map<String, dynamic> _link() => {
      'short_url': _shortUrl,
      'url_type': 39,
      'long_url': _articleUrl,
      'url_title': '文章标题',
      'card_image_url': _cover,
    };

class _ArticleClient extends Fake implements WeiboDioClient {
  final requestedIds = <String>[];

  @override
  Future<List<String>> getArticleHtmlCandidates(String articleId) async {
    requestedIds.add(articleId);
    return [
      '<div node-type="articleTitle">文章标题</div>'
          '<div node-type="contentBody"><p>文章正文已正常渲染</p></div>',
    ];
  }
}

void main() {
  test('official desktop/mobile article links share the native route', () {
    expect(LinkRoutingService.articleIdFromUrl(_articleUrl), _articleId);
    expect(
        LinkRoutingService.articleIdFromUrl(
            'https://card.weibo.com/article/m/show/id/$_articleId'),
        _articleId);
    expect(
        weiboArticleUrlFromMetadata({
          'type': 'article',
          'object_id': '1022:$_articleId',
        }),
        _articleUrl);
    expect(
        weiboArticleUrlFromMetadata({
          'type': 'webpage',
          'object_id': '1022:$_articleId',
        }),
        isNull);
    expect(
        LinkRoutingService.articleIdFromUrl(
            'https://example.com/ttarticle/p/show?id=$_articleId'),
        isNull);
  });

  for (final shape in ['url_struct', 'pic_infos', 'url_objects', 'page_info']) {
    test('article $shape cover retains native target and history metadata', () {
      late final Map<String, dynamic> payload;
      switch (shape) {
        case 'pic_infos':
          final link = _link()..remove('card_image_url');
          link['pic_infos'] = {
            'cover': {
              'large': {'url': _cover}
            },
          };
          payload = {
            'url_struct': [link]
          };
          break;
        case 'url_objects':
          payload = {
            'url_objects': [
              {
                'url_ori': _shortUrl,
                'info': {'title': '文章标题', 'url_long': _articleUrl},
                'object': {
                  'object': {
                    'object_type': 'article',
                    'image': {'url': _cover, 'width': 1600, 'height': 900},
                  },
                },
              },
            ],
          };
          break;
        case 'page_info':
          payload = {
            'url_struct': [_link()..remove('card_image_url')],
            'page_info': {
              'type': 'article',
              'page_url': _articleUrl,
              'page_title': '文章标题',
              'page_pic': _cover,
            },
          };
          break;
        default:
          payload = {
            'url_struct': [_link()]
          };
      }
      final status = WeiboStatusModel.fromJson(_status(payload));
      expect(status.pics, hasLength(1));
      expect(status.pics.single.articleUrl, _articleUrl);
      expect(status.pics.single.articleTitle, '文章标题');
      expect(status.urlStruct!.any(isAutomaticWebpageCardEntry), isFalse);
      expect(status.textRaw, isNot(contains(_shortUrl)));
      final restored = WeiboStatusModel.fromJson(status.toJson());
      expect(restored.pics, hasLength(1));
      expect(restored.pics.single.articleUrl, _articleUrl);
      expect(restored.pics.single.articleTitle, '文章标题');
    });
  }

  test('old history cover recovers the article target from url_struct', () {
    final status = WeiboStatusModel.fromJson(_status({
      'pics': [
        {
          'pid': _shortUrl,
          'is_webpage_card': true,
          'large': {'url': _cover},
          'original': {'url': _cover},
        },
      ],
      'url_struct': [_link()],
    }));
    expect(status.pics, hasLength(1));
    expect(status.pics.single.articleUrl, _articleUrl);
  });

  test('mobile article metadata repairs an old cover without duplication', () {
    final status = WeiboStatusModel.fromJson(_status({
      'pics': [
        {
          'pid': _shortUrl,
          'large': {'url': _cover},
          'original': {'url': _cover},
        },
      ],
      'url_struct': [_link()..remove('card_image_url')],
      'page_info': {
        'type': 'article',
        'page_url': _articleUrl,
        'page_title': '文章标题',
        'page_pic': _cover,
      },
    }));
    expect(status.pics, hasLength(1));
    expect(status.pics.single.articleUrl, _articleUrl);
    expect(status.textRaw, isNot(contains(_shortUrl)));
  });

  for (final isDetail in [false, true]) {
    testWidgets('article cover opens the existing reader, detail=$isDetail',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService(await SharedPreferences.getInstance());
      final client = _ArticleClient();
      final status = WeiboStatusModel.fromJson(_status({
        'url_struct': [_link()],
      }));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          weiboDioClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TweetCard(status: status, isDetail: isDetail),
            ),
          ),
        ),
      ));
      expect(client.requestedIds, isEmpty);
      await tester.tap(find
          .descendant(
            of: find.byType(NineGridView),
            matching: find.byWidgetPredicate(
                (widget) => widget is GestureDetector && widget.onTap != null),
          )
          .first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(WeiboArticlePage), findsOneWidget);
      expect(find.byType(ImageGalleryPage), findsNothing);
      expect(client.requestedIds, [_articleId]);
      expect(find.text('文章正文已正常渲染'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
