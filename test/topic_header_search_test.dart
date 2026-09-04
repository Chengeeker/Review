import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/features/search/data/models/weibo_topic_header_model.dart';
import 'package:review/features/search/presentation/widgets/weibo_topic_header_card.dart';

void main() {
  group('WeiboTopicHeaderModel Tests', () {
    test('Parses topicHeads JSON correctly', () {
      final json = {
        'topic_ori': 'TTG对战AG',
        'object': {
          'display_name': 'ttg对战ag',
          'summary': '18:30 广州TTG vs 成都AG超玩会',
          'image': {
            'url': 'https://wx2.sinaimg.cn/large/006D5nCUly8igqdjhk5hrj30cg0cgq4a.jpg',
          },
          'url': 'https://s.weibo.com/weibo?q=%23ttg%E5%AF%B9%E6%88%98ag%23',
        },
        'count': {
          'read': 391785293,
          'mention': 168275,
        },
        'claim_info': {
          'screen_name': 'KPL王者荣耀职业联赛',
          'verified_reason': 'KPL王者荣耀职业联赛官方微博',
          'id': 6074356560,
          'avatar_hd': 'https://tvax3.sinaimg.cn/crop.0.0.600.600.1024/6f0b57d3ly8hpxak2a0r3j20go0got9r.jpg',
        },
        'object_attr': {
          'intention': {
            'topping_docs_topic': '5339002279301155_6074356560',
          },
        },
      };

      final model = WeiboTopicHeaderModel.fromTopicHeads(json);

      expect(model.topicOri, 'TTG对战AG');
      expect(model.summary, '18:30 广州TTG vs 成都AG超玩会');
      expect(model.imageUrl, 'https://wx2.sinaimg.cn/large/006D5nCUly8igqdjhk5hrj30cg0cgq4a.jpg');
      expect(model.readCount, 391785293);
      expect(model.mentionCount, 168275);
      expect(model.formattedReadCount, '3.9亿');
      expect(model.formattedMentionCount, '16.8万');
      expect(model.hostName, 'KPL王者荣耀职业联赛');
      expect(model.hostUid, '6074356560');
      expect(model.toppingMid, '5339002279301155');
    });

    test('Formats smaller read and mention counts accurately', () {
      const model = WeiboTopicHeaderModel(
        topicOri: '测试话题',
        displayName: '测试话题',
        readCount: 5200,
        mentionCount: 88,
      );

      expect(model.formattedReadCount, '5200');
      expect(model.formattedMentionCount, '88');
    });
  });

  group('WeiboTopicHeaderCard Widget Tests', () {
    testWidgets('Renders topic title, metrics, summary, and host properly', (tester) async {
      const model = WeiboTopicHeaderModel(
        topicOri: 'TTG对战AG',
        displayName: 'ttg对战ag',
        summary: '18:30 广州TTG vs 成都AG超玩会',
        imageUrl: '',
        readCount: 390000000,
        mentionCount: 168000,
        hostName: 'KPL王者荣耀职业联赛',
        hostUid: '6074356560',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WeiboTopicHeaderCard(topic: model),
          ),
        ),
      );

      expect(find.text('#TTG对战AG#'), findsOneWidget);
      expect(find.text('阅读量 3.9亿'), findsOneWidget);
      expect(find.text('讨论量 16.8万'), findsOneWidget);
      expect(find.textContaining('18:30 广州TTG vs 成都AG超玩会'), findsOneWidget);
      expect(find.text('主持人: KPL王者荣耀职业联赛'), findsOneWidget);
      expect(find.text('分享'), findsOneWidget);
    });
  });
}
