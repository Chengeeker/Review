import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/constants/api_constants.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/feed/data/feed_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _longStatus(
  String id, {
  Map<String, dynamic>? retweetedStatus,
}) =>
    {
      'id': id,
      'idstr': id,
      'mid': id,
      'mblogid': id,
      'created_at': '刚刚',
      'text_raw': '微博预览正文 $id',
      'isLongText': true,
      'source': '来自微博网页版',
      'user': {'id': 'user-$id', 'idstr': 'user-$id', 'screen_name': '用户$id'},
      if (retweetedStatus != null) 'retweeted_status': retweetedStatus,
    };

void main() {
  test('timeline resolves main and repost long text before returning rows',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = WeiboDioClient(StorageService(prefs));
    client.dio.interceptors.clear();
    final requestedIds = <String>{};
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/ajax/feed/friendstimeline') {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: {
                  'statuses': [
                    _longStatus(
                      'main-id',
                      retweetedStatus: _longStatus('repost-id'),
                    ),
                  ],
                  'max_id': '0',
                },
              ),
            );
            return;
          }
          if (options.path == ApiConstants.longText) {
            final id = options.queryParameters['id'].toString();
            requestedIds.add(id);
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: {
                  'data': {'longTextContent_raw': '全文-$id'},
                },
              ),
            );
            return;
          }
          handler.next(options);
        },
      ),
    );

    final result = await FeedRepository(client, StorageService(prefs))
        .getTimeline(category: 'friends');

    expect(result.statuses, hasLength(1));
    final status = result.statuses.single;
    expect(status.fullTextRaw, '全文-main-id');
    expect(status.needsLongText, isFalse);
    expect(status.retweetedStatus?.fullTextRaw, '全文-repost-id');
    expect(status.retweetedStatus?.needsLongText, isFalse);
    expect(requestedIds, {'main-id', 'repost-id'});
  });

  test('background parsing opts out; foreground can resolve before publish',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = WeiboDioClient(StorageService(prefs));
    client.dio.interceptors.clear();
    var longTextRequestCount = 0;
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == ApiConstants.longText) {
            longTextRequestCount++;
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: {
                  'data': {'longTextContent_raw': '完整正文'},
                },
              ),
            );
          } else {
            handler.next(options);
          }
        },
      ),
    );
    final repository = FeedRepository(client, StorageService(prefs));
    final rawStatuses = [_longStatus('long-id')];

    final backgroundStatuses = await repository.parseStatuses(rawStatuses);
    expect(backgroundStatuses.single.needsLongText, isTrue);
    expect(longTextRequestCount, 0);

    final foregroundStatuses = await repository.parseStatuses(
      rawStatuses,
      resolveLongText: true,
    );
    expect(foregroundStatuses.single.fullTextRaw, '完整正文');
    expect(foregroundStatuses.single.needsLongText, isFalse);
    expect(longTextRequestCount, 1);
  });

  test('failed source hydration keeps the original row and preview', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = WeiboDioClient(StorageService(prefs));
    client.dio.interceptors.clear();
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/ajax/feed/friendstimeline') {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: {
                  'statuses': [_longStatus('unavailable-long-id')],
                  'max_id': '0',
                },
              ),
            );
          } else if (options.path == ApiConstants.longText) {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: {'data': <String, dynamic>{}},
              ),
            );
          } else {
            handler.next(options);
          }
        },
      ),
    );

    final result = await FeedRepository(client, StorageService(prefs))
        .getTimeline(category: 'friends');

    expect(result.statuses, hasLength(1));
    expect(result.statuses.single.textRaw, '微博预览正文 unavailable-long-id');
    expect(result.statuses.single.needsLongText, isTrue);
  });
}
