import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/constants/api_constants.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/feed/data/feed_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('FeedRepository sends the official direct vote payload', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.setFullCookie('SUB=test; XSRF-TOKEN=test');

    final client = WeiboDioClient(storage);
    Map<String, dynamic>? sentData;
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          sentData = Map<String, dynamic>.from(options.data as Map);
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'ok': 2,
                'vote_object': {
                  'id': 'vote-1',
                  'content': '投票问题',
                  'part_info': 9,
                  'parted': 1,
                  'vote_list': [
                    {'id': 'option-1', 'content': '甲', 'part_num': 4},
                    {'id': 'option-2', 'content': '乙', 'part_num': 5},
                  ],
                },
              },
            ),
          );
        },
      ),
    );

    final result = await FeedRepository(client, storage).setPollVote(
          voteId: 'vote-1',
          optionIds: ['option-2', 'option-1'],
        );

    expect(sentData, {
      'id': 'vote-1',
      'vote_items': 'option-2,option-1',
      'ext': '4',
    });
    expect(result.success, isTrue);
    expect(result.poll?.hasVoted, isTrue);
    expect(result.poll?.participantCount, 9);
    expect(result.poll?.options.last.votes, 5);
  });

  test('FeedRepository reads non-zero poll results from the official status API',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.setFullCookie('SUB=test; XSRF-TOKEN=test');

    final client = WeiboDioClient(storage);
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'data': {
                  'vote_info': {
                    'vote_id': 'vote-result',
                    'vote_title': '投票问题',
                    'part_info': 55,
                    'vote_options': [
                      {'id': 1, 'content': '甲'},
                      {'id': 2, 'content': '乙'},
                    ],
                  },
                  'card_info': {
                    'vote_object': {
                      'id': 'vote-result',
                      'content': '投票问题',
                      'part_info': 55,
                      'vote_list': [
                        {'id': 1, 'content': '甲', 'part_num': 10},
                        {'id': 2, 'content': '乙', 'part_num': 45},
                      ],
                    },
                  },
                },
              },
            ),
          );
        },
      ),
    );

    final poll = await FeedRepository(client, storage).getPollResult(
      statusId: '5340912604415830',
      pollId: 'vote-result',
    );

    expect(poll, isNotNull);
    expect(poll!.participantCount, 55);
    expect(poll.options.first.votes, 10);
    expect(poll.options.last.votes, 45);
  });

  test('FeedRepository rejects a poll shell without option result fields',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.setFullCookie('SUB=test; XSRF-TOKEN=test');

    final client = WeiboDioClient(storage);
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'data': {
                  'card_info': {
                    'vote_object': {
                      'id': 'vote-shell',
                      'content': '投票问题',
                      'part_info': 55,
                      'vote_list': [
                        {'id': 1, 'content': '甲'},
                        {'id': 2, 'content': '乙'},
                      ],
                    },
                  },
                },
              },
            ),
          );
        },
      ),
    );

    final poll = await FeedRepository(client, storage).getPollResult(
      statusId: '5340912604415830',
      pollId: 'vote-shell',
    );

    expect(poll, isNull);
  });
}
