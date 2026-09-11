import 'package:flutter_test/flutter_test.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/search/data/models/weibo_topic_header_model.dart';
import 'package:review/features/search/data/search_repository.dart';

void main() {
  group('SearchStatusesResult and Native Badges Tests', () {
    test('SearchStatusesResult initializes with statuses and optional details', () {
      final user = WeiboUserModel(id: '1', screenName: '成都AG超玩会', avatar: '', verified: true);
      final status = WeiboStatusModel(
        id: '1001',
        mid: '1001',
        textRaw: '比赛精彩',
        source: '微博网页版',
        repostsCount: 10,
        commentsCount: 20,
        attitudesCount: 30,
        user: user,
        createdAt: '2026-09-04 12:00:00',
        titleText: '热门',
      );

      final result = SearchStatusesResult(
        statuses: [status],
        toppingStatus: status.copyWith(isTop: true, titleText: '置顶'),
        hotOfficialUsers: [user],
      );

      expect(result.statuses.length, 1);
      expect(result.statuses.first.titleText, '热门');
      expect(result.toppingStatus?.isTop, isTrue);
      expect(result.toppingStatus?.titleText, '置顶');
      expect(result.hotOfficialUsers.length, 1);
      expect(result.hotOfficialUsers.first.screenName, '成都AG超玩会');
    });

    test('TopicHeader parsing from topicHeads map', () {
      final topicHeads = {
        'topic_ori': 'TTG对战AG',
        'count': {'read': 393055257, 'mention': 168932},
        'object': {'summary': '导语：18:30 广州TTG vs 成都AG超玩会', 'image': {'url': 'https://wx1.sinaimg.cn/pic.jpg'}},
        'claim_info': {'name': 'KPL王者荣耀职业联赛', 'id': '6074356560'},
      };

      final header = WeiboTopicHeaderModel.fromTopicHeads(topicHeads);
      expect(header.topicOri, 'TTG对战AG');
      expect(header.readCount, 393055257);
      expect(header.mentionCount, 168932);
      expect(header.formattedReadCount, '3.9亿');
      expect(header.formattedMentionCount, '16.9万');
      expect(header.summary, '导语：18:30 广州TTG vs 成都AG超玩会');
      expect(header.hostName, 'KPL王者荣耀职业联赛');
      expect(header.hostUid, '6074356560');
    });
  });
}
