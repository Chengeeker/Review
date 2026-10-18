import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/utils/weibo_emojis.dart';
import 'package:review/core/utils/weibo_text_parser.dart';
import 'package:review/features/drawer_features/data/chat_message_media.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';

void main() {
  test('WebIM video metadata resolves playable fid and scoped poster', () {
    final message = <String, dynamic>{
      'media_type': 10,
      'att_ids': 'a,a,b',
      'ext_text_video_pic_fid': 'poster',
    };
    expect(chatMessageVideoIds(message), ['a', 'b']);
    final metadata = chatAttachmentMetadata(
      '__review_video_meta({"extension":"mp4","fid":"playable","videosize":"1080*1920"});',
    );
    final pic = chatMessageVideo(message, 'a', metadata)!;
    expect(pic.isVideo, isTrue);
    expect(Uri.parse(pic.videoUrl!).queryParameters['fid'], 'playable');
    expect(Uri.parse(pic.previewUrl).queryParameters['fid'], 'poster');
    expect(pic.width / pic.height, 1080 / 1920);
    expect(chatMessageCaption('分享视频', hasImages: false, hasVideo: true), '');
    expect(chatMessageCaption('附言', hasImages: false, hasVideo: true), '附言');
    expect(chatMessageCaption('分享视频', hasImages: false), '分享视频');
    expect(
      chatMessageVideo({'media_type': 5}, 'a', {'extension': 'pdf'}),
      isNull,
    );
    expect(chatMessageVideo({'media_type': 5}, 'a', metadata), isNotNull);
    expect(chatMessageVideo(message, 'a', {'is_delete': 1}), isNull);
    expect(chatMessageVideoIds({'media_type': 1, 'att_ids': 'a'}), isEmpty);
    expect(chatAttachmentMetadata('evil({"fid":"bad"});'), isEmpty);
    expect(chatAttachmentMetadata('__review_video_meta({});alert(1)'), isEmpty);
    expect(chatAttachmentMetadata('{"fid":"json"}')['fid'], 'json');
  });

  test(
    'cards prefer native identities and valid long URLs over short links',
    () {
      Map<String, dynamic> message(Map<String, dynamic> entry) => {
        'url_objects': [entry],
        'cardtitle': 'fallback',
        'linkurl': 'http://t.cn/fallback',
      };
      final status = ChatLinkPreview.fromMessage(
        message({
          'info': {
            'url_short': 'http://t.cn/short',
            'url_long': 'https://example.com/long',
          },
          'status': {
            'idstr': '5345552066939360',
            'user': {'screen_name': '作者'},
          },
        }),
      )!;
      expect(status.url, 'https://weibo.com/detail/5345552066939360');
      expect(
        ChatLinkPreview.fromMessage(
          message({
            'info': {'url_short': 'http://t.cn/short'},
            'user': {'id': 123, 'screen_name': '用户'},
          }),
        )!.url,
        'https://weibo.com/u/123',
      );
      expect(
        ChatLinkPreview.fromMessage(
          message({
            'info': {
              'url_short': 'http://t.cn/short',
              'url_long': 'https://example.com/long',
            },
            'object': {'title': '文章'},
          }),
        )!.url,
        'https://example.com/long',
      );
      expect(
        ChatLinkPreview.fromMessage(
          message({
            'info': {
              'url_long': 'javascript:bad',
              'url_short': 'https://t.cn/good',
            },
            'object': {'title': '文章'},
          }),
        )!.url,
        'https://t.cn/good',
      );
    },
  );
  test('gallery originals upgrade only known Sina preview paths', () {
    for (final variant in [
      'orj960',
      'mw2000',
      'cmw960',
      'thumbnail',
      'bmiddle',
    ]) {
      final pic = WeiboPicModel.fromJson({
        'pid': 'photo',
        'large': {'url': 'https://wx3.sinaimg.cn/$variant/photo.jpg?x=1'},
      });
      expect(pic.originalUrl, 'https://wx3.sinaimg.cn/large/photo.jpg?x=1');
      expect(pic.previewUrl, contains('/$variant/'));
    }
    for (final url in [
      'https://upload.api.weibo.com/2/mss/msget?fid=123',
      'https://wx3.sinaimg.cn.evil.test/orj960/photo.jpg',
    ]) {
      expect(
        WeiboPicModel(
          pid: '',
          thumbnail: url,
          large: url,
          original: url,
        ).originalUrl,
        url,
      );
    }
  });

  test('media captions, GIFs, and status/user cards follow WebIM fields', () {
    expect(chatMessageCaption('分享图片', hasImages: true), isEmpty);
    expect(chatMessageCaption('分享图片', hasImages: false), '分享图片');
    expect(chatMessageCaption('我的说明', hasImages: true), '我的说明');
    expect(
      chatMessageImageUrls({
        'pic_gifs': {'original_pic': '//example.com/a.gif'},
      }),
      ['https://example.com/a.gif'],
    );
    final card = ChatLinkPreview.fromMessage({
      'url_objects': [
        {
          'info': {'url_short': 'https://t.cn/example'},
          'status': {
            'user': {'screen_name': '数码小凡'},
            'text': '还原 Siri 唤醒动画',
          },
        },
      ],
    });
    expect(card?.title, '数码小凡');
    expect(card?.description, '还原 Siri 唤醒动画');
    expect(card?.url, 'https://t.cn/example');
    expect(
      ChatLinkPreview.fromMessage({
        'url_objects': [
          {
            'info': {'url_short': 'javascript:alert(1)'},
            'user': {'screen_name': '用户'},
          },
        ],
      }),
      isNull,
    );
  });

  test('legacy filename emoji decode SoftBank and modern UTF8 filenames', () {
    expect(WeiboEmojis.getEmoji('[/ee90a0.png]'), '👌');
    expect(WeiboEmojis.getEmoji('[/ee808e.png]'), '👍');
    expect(WeiboEmojis.getEmoji('[/f09f918c.png]'), '👌');
    expect(WeiboEmojis.getEmoji('[/ffff00.png]'), isNull);
    expect(WeiboEmojis.getEmoji('[/unknown.png]'), isNull);
  });

  testWidgets(
    'filename labels are recognized both as inline HTML and plain text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final inline = WeiboTextParser.parse(
                rawText: '<img src="https://example.com/ee90a0.png" alt="[/ee90a0.png]">',
                context: context,
              );
              expect(inline.whereType<WidgetSpan>(), hasLength(1));
              final plain = WeiboTextParser.parse(
                rawText: '[/ee90a0.png]',
                context: context,
              );
              expect(plain.map((s) => s.toPlainText()).join(), contains('👌'));
              return const SizedBox();
            },
          ),
        ),
      );
    },
  );
}
