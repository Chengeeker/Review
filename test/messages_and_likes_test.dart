import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:review/core/constants/api_constants.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/detail/data/detail_repository.dart';
import 'package:review/features/detail/data/models/weibo_attitude_model.dart';
import 'package:review/features/detail/data/models/weibo_comment_model.dart';
import 'package:review/features/detail/presentation/status_detail_page.dart';
import 'package:review/features/drawer_features/presentation/likes_comments_page.dart';
import 'package:review/features/drawer_features/presentation/likes_favorites_page.dart';
import 'package:review/features/drawer_features/presentation/my_messages_page.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingDetailRepository extends Fake implements DetailRepository {
  String? deletedCommentId;
  List<WeiboCommentModel> rootComments = const [];
  String rootCommentsMaxId = '0';
  bool rootCommentsHasMore = false;
  final List<String> rootCommentRequests = [];
  final Map<String, CommentResult> rootCommentResults = {};
  final List<String> secondCommentRequests = [];
  final Map<String, CommentResult> secondCommentResults = {};

  @override
  Future<CommentActionResult> destroyComment({required String cid}) async {
    deletedCommentId = cid;
    return const CommentActionResult(success: true);
  }

  @override
  Future<CommentResult> getComments({
    required String id,
    required String uid,
    String maxId = '0',
    int count = 15,
    int flow = 0,
  }) async {
    rootCommentRequests.add(maxId);
    final pagedResult = rootCommentResults[maxId];
    if (pagedResult != null) return pagedResult;
    return CommentResult(
      comments: rootComments,
      maxId: rootCommentsMaxId,
      hasMore: rootCommentsHasMore,
    );
  }

  @override
  Future<CommentResult> getSecondComments({
    required String commentId,
    String maxId = '0',
    int count = 20,
  }) async {
    final requestKey = '$commentId|$maxId';
    secondCommentRequests.add(requestKey);
    return secondCommentResults[requestKey] ??
        const CommentResult(comments: [], hasMore: false);
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

void main() {
  test('destroyComment uses the official delete endpoint and comment id',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.setFullCookie('SUB=test; XSRF-TOKEN=test');

    final client = WeiboDioClient(storage);
    String? requestPath;
    Map<String, dynamic>? requestData;
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestPath = options.path;
          requestData = Map<String, dynamic>.from(options.data as Map);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'ok': 1},
            ),
          );
        },
      ),
    );

    final result = await DetailRepository(client).destroyComment(
      cid: 'comment-1',
    );

    expect(result.success, isTrue);
    expect(requestPath, ApiConstants.destroyComment);
    expect(requestData, {'cid': 'comment-1'});
  });

  test('getSecondComments parses official nested pagination envelopes',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.setFullCookie('SUB=test; XSRF-TOKEN=test');

    final client = WeiboDioClient(storage);
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final isNextPage = options.queryParameters['max_id'] == 'next';
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: isNextPage
                  ? {
                      'data': {
                        'data': [
                          {
                            'cid': 'reply-2',
                            'text_raw': '第二页回复',
                            'user': {'screen_name': '回复用户'},
                          },
                        ],
                        'max_id': '0',
                      },
                    }
                  : {
                      'data': {
                        'comments': [
                          {
                            'idstr': 'reply-1',
                            'text_raw': '第一页回复',
                            'user': {'screen_name': '回复用户'},
                          },
                        ],
                        'max_id': 'next',
                      },
                    },
            ),
          );
        },
      ),
    );

    final repository = DetailRepository(client);
    final firstPage = await repository.getSecondComments(commentId: 'root-1');
    final secondPage = await repository.getSecondComments(
      commentId: 'root-1',
      maxId: firstPage.maxId,
    );

    expect(firstPage.comments.single.id, 'reply-1');
    expect(firstPage.maxId, 'next');
    expect(firstPage.hasMore, isTrue);
    expect(secondPage.comments.single.id, 'reply-2');
    expect(secondPage.hasMore, isFalse);
  });

  test('getComments uses web continuation parameters and nested pagination',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.setFullCookie('SUB=test; XSRF-TOKEN=test');

    final client = WeiboDioClient(storage);
    final requests = <Map<String, dynamic>>[];
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(Map<String, dynamic>.from(options.queryParameters));
          final isNextPage = options.queryParameters['max_id'] == 'next';
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: isNextPage
                  ? {
                      'data': [
                        {
                          'idstr': 'comment-2',
                          'text_raw': '第二页评论',
                          'user': {'screen_name': '评论用户'},
                        },
                      ],
                      'max_id': 0,
                    }
                  : {
                      'data': {
                        'data': [
                          {
                            'idstr': 'comment-1',
                            'text_raw': '第一页评论',
                            'user': {'screen_name': '评论用户'},
                          },
                        ],
                        'max_id': 'next',
                      },
                    },
            ),
          );
        },
      ),
    );

    final repository = DetailRepository(client);
    final firstPage = await repository.getComments(
      id: 'status-1',
      uid: 'user-1',
    );
    final secondPage = await repository.getComments(
      id: 'status-1',
      uid: 'user-1',
      maxId: firstPage.maxId,
    );

    expect(firstPage.comments.single.id, 'comment-1');
    expect(firstPage.maxId, 'next');
    expect(firstPage.hasMore, isTrue);
    expect(secondPage.comments.single.id, 'comment-2');
    expect(secondPage.hasMore, isFalse);
    expect(requests[0]['is_mix'], 0);
    expect(requests[1]['is_mix'], 1);
    expect(requests[1]['max_id'], 'next');
    expect(requests[1]['max_id_type'], 0);
    expect(requests[1]['fetch_level'], 0);
  });

  testWidgets('LikesFavoritesPage has 2 tabs: 我的赞 and 我的收藏', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
        child: const MaterialApp(
          home: LikesFavoritesPage(),
        ),
      ),
    );

    expect(find.text('我的赞'), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('赞和收藏'), findsOneWidget);
  });

  testWidgets('ReceivedLikesPage, SentCommentsPage, ReceivedCommentsPage render clean titles', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
        child: const MaterialApp(
          home: ReceivedLikesPage(),
        ),
      ),
    );
    expect(find.text('收到的赞'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
        child: const MaterialApp(
          home: SentCommentsPage(),
        ),
      ),
    );
    expect(find.text('发出的评论'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
        child: const MaterialApp(
          home: ReceivedCommentsPage(),
        ),
      ),
    );
    expect(find.text('收到的评论'), findsOneWidget);
  });

  testWidgets('MyMessagesPage renders message center structure', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
        child: const MaterialApp(
          home: MyMessagesPage(),
        ),
      ),
    );

    expect(find.text('我的消息'), findsOneWidget);
  });

  testWidgets(
      'SentCommentsPage exposes deletion and preserves the status/comment target',
      (tester) async {
    const status = <String, dynamic>{
      'id': '5340912604415830',
      'mid': '5340912604415830',
      'mblogid': 'RtestStatus',
      'created_at': '2026-09-12 12:00:00',
      'text_raw': '原微博',
      'user': {
        'id': '2',
        'screen_name': '博主',
        'profile_image_url': '',
      },
    };
    const comment = <String, dynamic>{
      'id': 'comment-1',
      'created_at': '2026-09-12 12:01:00',
      'text_raw': '测试评论',
      'user': {
        'id': '3',
        'screen_name': '评论用户',
        'profile_image_url': '',
      },
      'status': status,
    };

    SharedPreferences.setMockInitialValues({
      StorageService.keyIsLoggedIn: true,
      StorageService.keyFullCookie: 'SUB=test; XSRF-TOKEN=test',
      StorageService.keySubCookie: 'test',
      StorageService.keyUserUid: '3',
      StorageService.keyUserNickname: '评论用户',
      StorageService.keyUserAvatar: '',
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final client = WeiboDioClient(storage);
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'data': {
                  'comments': [comment],
                },
              },
            ),
          );
        },
      ),
    );
    final detailRepository = _RecordingDetailRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          weiboDioClientProvider.overrideWithValue(client),
          detailRepositoryProvider.overrideWithValue(detailRepository),
        ],
        child: const MaterialApp(
          home: SentCommentsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试评论'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('测试评论'));
    await tester.pumpAndSettle();
    final detailPage = tester.widget<StatusDetailPage>(
      find.byType(StatusDetailPage),
    );
    expect(detailPage.statusId, '5340912604415830');
    expect(detailPage.initialComment?.id, 'comment-1');
    expect(detailPage.initialCommentId, 'comment-1');
    expect(find.text('测试评论'), findsOneWidget);

    Navigator.of(tester.element(find.byType(StatusDetailPage))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('确定要删除这条评论吗？删除后不可恢复。'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(detailRepository.deletedCommentId, 'comment-1');
    expect(find.text('测试评论'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'SentCommentsPage resolves nested reply targets across second-comment pages',
      (tester) async {
    const status = <String, dynamic>{
      'id': '5340912604415830',
      'mid': '5340912604415830',
      'mblogid': 'RtestStatus',
      'created_at': '2026-09-12 12:00:00',
      'text_raw': '原微博',
      'user': {
        'id': '2',
        'screen_name': '博主',
        'profile_image_url': '',
      },
    };
    const comment = <String, dynamic>{
      'id': 'reply-2',
      'created_at': '2026-09-12 12:01:00',
      'text_raw': '目标回复',
      'user': {
        'id': '3',
        'screen_name': '评论用户',
        'profile_image_url': '',
      },
      'status': status,
      'rootid': '0',
      'reply_comment': {
        'id': 'reply-1',
        'text_raw': '直接父回复',
        'reply_comment': {
          'id': 'root-1',
          'text_raw': '根评论',
        },
      },
    };

    SharedPreferences.setMockInitialValues({
      StorageService.keyIsLoggedIn: true,
      StorageService.keyFullCookie: 'SUB=test; XSRF-TOKEN=test',
      StorageService.keySubCookie: 'test',
      StorageService.keyUserUid: '3',
      StorageService.keyUserNickname: '评论用户',
      StorageService.keyUserAvatar: '',
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final client = WeiboDioClient(storage);
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'data': {
                  'comments': [comment],
                },
              },
            ),
          );
        },
      ),
    );
    final detailRepository = _RecordingDetailRepository()
      ..rootComments = [
        WeiboCommentModel.fromJson({
          'id': 'root-1',
          'text_raw': '根评论',
          'user': {'screen_name': '根评论用户'},
        }),
      ]
      ..secondCommentResults['root-1|0'] = CommentResult(
        comments: [
          WeiboCommentModel.fromJson({
            'id': 'reply-before-target',
            'text_raw': '第一页回复',
            'user': {'screen_name': '回复用户'},
          }),
        ],
        maxId: 'page-2',
        hasMore: true,
      )
      ..secondCommentResults['root-1|page-2'] = CommentResult(
        comments: [
          WeiboCommentModel.fromJson({
            'idstr': 'reply-2',
            'text_raw': '目标回复',
            'user': {'screen_name': '评论用户'},
          }),
        ],
        hasMore: false,
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          weiboDioClientProvider.overrideWithValue(client),
          detailRepositoryProvider.overrideWithValue(detailRepository),
        ],
        child: const MaterialApp(
          home: SentCommentsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('目标回复'));
    await tester.pumpAndSettle();

    final detailPage = tester.widget<StatusDetailPage>(
      find.byType(StatusDetailPage),
    );
    expect(detailPage.initialCommentId, 'reply-2');
    expect(detailPage.initialCommentParentId, 'root-1');
    expect(detailRepository.secondCommentRequests, [
      'root-1|0',
      'root-1|page-2',
    ]);
    expect(find.text('目标回复'), findsOneWidget);
  });

  testWidgets(
      'SentCommentsPage keeps seeking past the former 30-page root-comment limit',
      (tester) async {
    const status = <String, dynamic>{
      'id': '5340912604415830',
      'mid': '5340912604415830',
      'mblogid': 'RtestStatus',
      'created_at': '2026-09-12 12:00:00',
      'text_raw': '原微博',
      'user': {
        'id': '2',
        'screen_name': '博主',
        'profile_image_url': '',
      },
    };
    const comment = <String, dynamic>{
      'id': 'target-root',
      'created_at': '2026-09-12 12:01:00',
      'text_raw': '超过三十页的目标评论',
      'user': {
        'id': '3',
        'screen_name': '评论用户',
        'profile_image_url': '',
      },
      'status': status,
      'rootid': 'target-root',
    };

    SharedPreferences.setMockInitialValues({
      StorageService.keyIsLoggedIn: true,
      StorageService.keyFullCookie: 'SUB=test; XSRF-TOKEN=test',
      StorageService.keySubCookie: 'test',
      StorageService.keyUserUid: '3',
      StorageService.keyUserNickname: '评论用户',
      StorageService.keyUserAvatar: '',
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final client = WeiboDioClient(storage);
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'data': {
                  'comments': [comment],
                },
              },
            ),
          );
        },
      ),
    );
    final detailRepository = _RecordingDetailRepository();
    detailRepository.rootCommentResults['0'] = CommentResult(
      comments: [
        WeiboCommentModel.fromJson({
          'id': 'root-page-0',
          'text_raw': '第一页评论',
          'user': {'screen_name': '评论用户'},
        }),
      ],
      maxId: 'page-1',
      hasMore: true,
    );
    for (var page = 1; page <= 31; page++) {
      final isTargetPage = page == 31;
      detailRepository.rootCommentResults['page-$page'] = CommentResult(
        comments: [
          WeiboCommentModel.fromJson({
            'id': isTargetPage ? 'target-root' : 'root-page-$page',
            'text_raw': isTargetPage ? '超过三十页的目标评论' : '普通评论 $page',
            'user': {'screen_name': '评论用户'},
          }),
        ],
        maxId: isTargetPage ? '0' : 'page-${page + 1}',
        hasMore: !isTargetPage,
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          weiboDioClientProvider.overrideWithValue(client),
          detailRepositoryProvider.overrideWithValue(detailRepository),
        ],
        child: const MaterialApp(
          home: SentCommentsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('超过三十页的目标评论'));
    await tester.pumpAndSettle();

    expect(find.text('超过三十页的目标评论'), findsOneWidget);
    expect(detailRepository.rootCommentRequests.length, 32);
    expect(detailRepository.rootCommentRequests.last, 'page-31');
  });
}
