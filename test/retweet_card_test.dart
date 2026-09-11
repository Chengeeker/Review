import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/detail/data/detail_repository.dart';
import 'package:review/features/detail/data/models/weibo_attitude_model.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/feed/presentation/widgets/tweet_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopDetailRepository extends Fake implements DetailRepository {
  @override
  Future<CommentResult> getComments({
    required String id,
    required String uid,
    String maxId = '0',
    int count = 15,
    int flow = 0,
  }) async {
    return const CommentResult(comments: [], hasMore: false);
  }

  @override
  Future<RepostResult> getReposts({
    required String id,
    int page = 1,
    int count = 20,
  }) async {
    return const RepostResult();
  }

  @override
  Future<AttitudeResult> getAttitudes({
    required String id,
    int page = 1,
    int count = 20,
  }) async {
    return const AttitudeResult();
  }

  @override
  Future<WeiboStatusModel?> getStatusDetail(String id) async => null;
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}

void main() {
  testWidgets(
      'retweeted text remains clickable in detail and a retweeted video is rendered',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final navigatorObserver = _RecordingNavigatorObserver();

    const original = WeiboStatusModel(
      id: 'original-status',
      mid: 'original-status',
      createdAt: '刚刚',
      textRaw: '原微博文字和视频',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(
        id: 'original-user',
        screenName: '原作者',
        avatar: '',
      ),
      videoCoverUrl: 'https://example.com/original-cover.jpg',
      videoStreamUrl: 'https://example.com/original.mp4',
    );

    const status = WeiboStatusModel(
      id: 'outer-status',
      mid: 'outer-status',
      createdAt: '刚刚',
      textRaw: '转发原微博',
      source: '来自微博网页版',
      repostsCount: 0,
      commentsCount: 0,
      attitudesCount: 0,
      user: WeiboUserModel(
        id: 'outer-user',
        screenName: '转发用户',
        avatar: '',
      ),
      retweetedStatus: original,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          detailRepositoryProvider.overrideWithValue(_NoopDetailRepository()),
        ],
        child: MaterialApp(
          navigatorObservers: [navigatorObserver],
          home: Scaffold(
            body: SingleChildScrollView(
              child: TweetCard(status: status, isDetail: true),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('retweet-text-original-status')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(navigatorObserver.pushCount, equals(2));
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump(const Duration(milliseconds: 400));
  });
}
