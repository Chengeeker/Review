import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/utils/weibo_text_parser.dart';

void main() {
  testWidgets('WeiboTextParser parses @, #, and URLs into spans correctly',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            const rawText =
                '你好 @人民日报 发布了新话题 #今日热点# 详情见 https://weibo.com <br/>欢迎关注！';
            final spans = WeiboTextParser.parse(
              rawText: rawText,
              context: context,
            );

            expect(spans.length, greaterThan(3));
            final combinedText = spans.map((s) => s.toPlainText()).join();
            expect(combinedText.contains('@人民日报'), isTrue);
            expect(combinedText.contains('#今日热点#'), isTrue);
            expect(combinedText.contains('网页链接'), isTrue);

            return Text.rich(TextSpan(children: spans));
          },
        ),
      ),
    );
  });

  testWidgets('WeiboTextParser parses urlStruct to display smart link title',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            const rawText = '微博智搜为你整理了结果：http://t.cn/A6smartsearch 点击查看';
            final urlStruct = [
              {
                'short_url': 'http://t.cn/A6smartsearch',
                'url_title': '微博智搜',
                'url_type': 36,
                'long_url': 'https://s.weibo.com/weibo?q=test',
              }
            ];
            final spans = WeiboTextParser.parse(
              rawText: rawText,
              context: context,
              urlStruct: urlStruct,
            );

            final combinedText = spans.map((s) => s.toPlainText()).join();
            expect(combinedText.contains('微博智搜'), isTrue);
            expect(combinedText.contains('🔗 微博智搜'), isTrue);

            return Text.rich(TextSpan(children: spans));
          },
        ),
      ),
    );
  });

  testWidgets(
      'WeiboTextParser ignores zero-width suffixes on official smart links',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            const rawText = '深度测评：http://t.cn/AXOxP3Ga\u200b\u200b\u200b';
            final urlStruct = [
              {
                'short_url': 'http://t.cn/AXOxP3Ga',
                'url_title': '努比亚NaviX Ultra深度测评报告',
                'long_url':
                    'http://weibo.com/ttarticle/p/show?id=2310475343796384104518',
              }
            ];
            final spans = WeiboTextParser.parse(
              rawText: rawText,
              context: context,
              urlStruct: urlStruct,
            );

            final combinedText = spans.map((s) => s.toPlainText()).join();
            expect(combinedText.contains('努比亚NaviX Ultra深度测评报告'), isTrue);
            expect(combinedText.contains('网页链接'), isFalse);
            return Text.rich(TextSpan(children: spans));
          },
        ),
      ),
    );
  });

  testWidgets('WeiboTextParser prefers any official video target in urlStruct',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final spans = WeiboTextParser.parse(
              rawText: '视频：http://t.cn/A6video',
              context: context,
              urlStruct: [
                {
                  'short_url': 'http://t.cn/A6video',
                  'url_title': 'ColorOS陈希的微博视频',
                  'long_url': 'https://weibo.com/tv/show/1034:video-1',
                },
              ],
            );

            final combinedText = spans.map((span) => span.toPlainText()).join();
            expect(combinedText, contains('ColorOS陈希的微博视频'));
            return Text.rich(TextSpan(children: spans));
          },
        ),
      ),
    );
  });

  testWidgets('WeiboTextParser routes a signed url_objects media URL natively',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final spans = WeiboTextParser.parse(
              rawText: '视频：http://t.cn/AXOaa3q8',
              context: context,
              urlStruct: [
                {
                  'short_url': 'http://t.cn/AXOaa3q8',
                  'url_title': 'ColorOS陈希的微博视频',
                  'h5_target_url':
                      'https://video.weibo.com/show?fid=1034:5344173386039366',
                  'video_url': 'https://f.video.weibocdn.com/video.mp4?sig=1',
                },
              ],
            );

            final combinedText = spans.map((span) => span.toPlainText()).join();
            expect(combinedText, contains('ColorOS陈希的微博视频'));
            expect(combinedText, isNot(contains('网页链接')));
            return Text.rich(TextSpan(children: spans));
          },
        ),
      ),
    );
  });

  testWidgets('WeiboTextParser keeps video targets from long-text anchors',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final spans = WeiboTextParser.parse(
              rawText:
                  '''正文 <a href="https://video.weibo.com/show?fid=1034:video-1"><span class="surl-text">ColorOS陈希的微博视频</span></a>''',
              context: context,
              urlStruct: [
                {
                  'short_url': 'http://t.cn/A6video',
                  'url_title': 'ColorOS陈希的微博视频',
                  'h5_target_url':
                      'https://video.weibo.com/show?fid=1034:video-1',
                  'video_url': 'https://f.video.weibocdn.com/video.mp4?sig=1',
                },
              ],
            );

            final combinedText = spans.map((span) => span.toPlainText()).join();
            expect(combinedText, contains('ColorOS陈希的微博视频'));
            expect(combinedText, isNot(contains('网页链接')));
            return Text.rich(TextSpan(children: spans));
          },
        ),
      ),
    );
  });

  testWidgets('WeiboTextParser parses Super Topic and Weibo Emotions correctly',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            const rawText = '今日赛果 #AG超玩会[超话]# MVP给到了救赎 [努力][心]';
            final urlStruct = [
              {
                'short_url': '#AG超玩会[超话]#',
                'url_title': 'AG超玩会超话',
                'page_id': '100808e42ac86fcd4c91f965e34411bd21f0b0',
                'ori_url':
                    'sinaweibo://pageinfo?containerid=100808e42ac86fcd4c91f965e34411bd21f0b0',
              }
            ];
            final spans = WeiboTextParser.parse(
              rawText: rawText,
              context: context,
              urlStruct: urlStruct,
            );

            expect(spans.isNotEmpty, isTrue);
            final combinedText = spans.map((s) => s.toPlainText()).join();
            expect(combinedText.contains('#AG超玩会[超话]#'), isTrue);

            return Text.rich(TextSpan(children: spans));
          },
        ),
      ),
    );
  });

  testWidgets('WeiboTextParser uses emoji assets returned in status HTML',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final spans = WeiboTextParser.parse(
              rawText: '这个表情是[勾引]',
              htmlText:
                  '这个表情是<img alt="[勾引]" src="https://face.t.sinajs.cn/emoji.png">',
              context: context,
            );

            expect(spans.whereType<WidgetSpan>(), hasLength(1));
            return Text.rich(TextSpan(children: spans));
          },
        ),
      ),
    );
  });

  testWidgets('WeiboTextParser parses complex @user mentions correctly',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            const rawText = '本局MVP给到了@成都AG救赎_ ，队友有@成都AG丶轩染 和@AG长生-';
            final parsedUsers = <String>[];
            final spans = WeiboTextParser.parse(
              rawText: rawText,
              context: context,
              onUserTap: (u) => parsedUsers.add(u),
            );

            expect(spans.isNotEmpty, isTrue);
            final combinedText = spans.map((s) => s.toPlainText()).join();
            expect(combinedText.contains('@成都AG救赎_'), isTrue);
            expect(combinedText.contains('@成都AG丶轩染'), isTrue);
            expect(combinedText.contains('@AG长生-'), isTrue);

            return Text.rich(TextSpan(children: spans));
          },
        ),
      ),
    );
  });
}
