import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/utils/weibo_text_parser.dart';

void main() {
  testWidgets('WeiboTextParser parses @, #, and URLs into spans correctly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            const rawText = '你好 @人民日报 发布了新话题 #今日热点# 详情见 https://weibo.com <br/>欢迎关注！';
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

  testWidgets('WeiboTextParser parses urlStruct to display smart link title', (tester) async {
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

  testWidgets('WeiboTextParser parses Super Topic and Weibo Emotions correctly', (tester) async {
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
                'ori_url': 'sinaweibo://pageinfo?containerid=100808e42ac86fcd4c91f965e34411bd21f0b0',
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

  testWidgets('WeiboTextParser parses complex @user mentions correctly', (tester) async {
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
