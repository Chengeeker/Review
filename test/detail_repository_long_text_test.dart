import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/detail/data/detail_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('DetailRepository coalesces and caches long-text requests', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = WeiboDioClient(StorageService(prefs));
    client.dio.interceptors.clear();

    var requestCount = 0;
    String? requestedId;
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestCount++;
          requestedId = options.queryParameters['id']?.toString();
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              data: {
                'data': {'longTextContent_raw': '微博完整正文'},
              },
            ),
          );
        },
      ),
    );

    final repository = DetailRepository(client);
    final results = await Future.wait([
      repository.getLongText(' 12345 '),
      repository.getLongText('12345'),
    ]);

    expect(results, ['微博完整正文', '微博完整正文']);
    expect(requestCount, 1);
    expect(requestedId, '12345');
    expect(await repository.getLongText('12345'), '微博完整正文');
    expect(requestCount, 1);
  });

  test('DetailRepository limits concurrent long-text requests to two',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = WeiboDioClient(StorageService(prefs));
    client.dio.interceptors.clear();

    var activeRequests = 0;
    var peakActiveRequests = 0;
    var completedRequests = 0;
    final pendingResponses = <void Function()>[];
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          activeRequests++;
          if (activeRequests > peakActiveRequests) {
            peakActiveRequests = activeRequests;
          }
          pendingResponses.add(() {
            activeRequests--;
            completedRequests++;
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: {
                  'data': {
                    'longTextContent_raw':
                        '微博完整正文${options.queryParameters['id']}',
                  },
                },
              ),
            );
          });
        },
      ),
    );

    final repository = DetailRepository(client);
    final requests = [
      for (var index = 0; index < 5; index++)
        repository.getLongText('long-$index'),
    ];

    while (completedRequests < requests.length) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(activeRequests, lessThanOrEqualTo(2));
      if (pendingResponses.isNotEmpty) {
        pendingResponses.removeAt(0)();
      }
    }

    final results = await Future.wait(requests);
    expect(results, [
      '微博完整正文long-0',
      '微博完整正文long-1',
      '微博完整正文long-2',
      '微博完整正文long-3',
      '微博完整正文long-4',
    ]);
    expect(peakActiveRequests, 2);
  });
}
