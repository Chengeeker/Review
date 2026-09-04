import 'package:flutter_test/flutter_test.dart';
import 'package:review/features/detail/data/models/weibo_comment_model.dart';
import 'package:review/features/detail/data/models/weibo_attitude_model.dart';

void main() {
  group('Weibo Detail Interaction Tests', () {
    test('WeiboCommentModel correctly formats real user IP location', () {
      final comment1 = WeiboCommentModel.fromJson({
        'id': '101',
        'text_raw': '去新加坡吃正宗的',
        'source': '来自 湖北',
        'user': {
          'id': 'u1',
          'screen_name': '科技雷灵',
        },
      });
      expect(comment1.formattedIpOrSource, equals('来自 湖北'));

      final comment2 = WeiboCommentModel.fromJson({
        'id': '102',
        'text_raw': '直接来海南海口我请你吃',
        'source': '海南',
        'user': {
          'id': 'u2',
          'screen_name': 'lingg056',
        },
      });
      expect(comment2.formattedIpOrSource, equals('来自 海南'));
    });

    test('WeiboCommentModel correctly identifies AI generation (千问, AI bots, etc.)', () {
      // Case 1: User name is 千问
      final qianwenComment = WeiboCommentModel.fromJson({
        'id': '103',
        'text_raw': '深圳好吃得海南鸡饭不少！',
        'source': '千问AI生成',
        'user': {
          'id': 'u3',
          'screen_name': '千问',
        },
      });
      expect(qianwenComment.formattedIpOrSource, equals('来自 AI生成'));

      // Case 2: Source contains AI生成
      final aiComment2 = WeiboCommentModel.fromJson({
        'id': '104',
        'text_raw': '这是AI生成的内容',
        'source': '来自 文心AI生成',
        'user': {
          'id': 'u4',
          'screen_name': '美食助手',
        },
      });
      expect(aiComment2.formattedIpOrSource, equals('来自 AI生成'));

      // Case 3: User screenName contains AI
      final aiComment3 = WeiboCommentModel.fromJson({
        'id': '105',
        'text_raw': 'Kimi智能助手的推荐',
        'source': '广东',
        'user': {
          'id': 'u5',
          'screen_name': 'Kimi_AI',
        },
      });
      expect(aiComment3.formattedIpOrSource, equals('来自 AI生成'));
    });

    test('WeiboCommentModel cleans HTML from source tags', () {
      final comment = WeiboCommentModel.fromJson({
        'id': '106',
        'text_raw': '测试HTML标签清洗',
        'source': '<a href="http://weibo.com/">来自 微博Android客户端</a>',
        'user': {
          'id': 'u6',
          'screen_name': '测试用户',
        },
      });
      expect(comment.formattedIpOrSource, equals('来自 微博Android客户端'));
    });

    test('WeiboAttitudeModel parses JSON correctly', () {
      final attitude = WeiboAttitudeModel.fromJson({
        'id': 'att_123',
        'created_at': 'Thu Sep 03 18:00:00 +0800 2026',
        'attitude': 'like',
        'user': {
          'id': 'u99',
          'screen_name': '点赞达人',
          'profile_image_url': 'https://example.com/avatar.jpg',
          'verified': true,
          'verified_type': 0,
          'description': '资深数码爱好者',
        },
      });

      expect(attitude.id, equals('att_123'));
      expect(attitude.user.screenName, equals('点赞达人'));
      expect(attitude.user.verified, isTrue);
      expect(attitude.attitude, equals('like'));
      expect(attitude.user.description, equals('资深数码爱好者'));
    });
  });
}
