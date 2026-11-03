import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/detail/presentation/status_detail_page.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'three filters refresh on every selection and author roots use time order',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService(await SharedPreferences.getInstance());
      final client = WeiboDioClient(storage);
      client.dio.interceptors.clear();
      final post = <String, dynamic>{
        'id': '123',
        'text_raw': '帖子正文',
        'created_at': '刚刚',
        'user': {'id': 'owner', 'screen_name': '楼主'},
      };
      Map<String, dynamic> comment(
        String id,
        String uid,
        String text,
        int count,
      ) => {
        'id': id,
        'text_raw': text,
        'total_number': count,
        'user': {'id': uid, 'screen_name': uid},
      };
      final rootRequests = <int>[];
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            if (request.path.contains('buildComments') &&
                request.queryParameters['fetch_level'] != 1) {
              rootRequests.add(request.queryParameters['flow'] as int? ?? 0);
            }
            final data = request.path.contains('buildComments')
                ? {
                    'ok': 1,
                    'max_id': 0,
                    'data': request.queryParameters['fetch_level'] == 1
                        ? [comment('reply', 'owner', '楼主后续回复', 0)]
                        : [
                            comment('own', 'owner', '楼主独立评论', 0),
                            comment('thread', 'other', '别人发起的讨论', 10),
                          ],
                  }
                : request.path.contains('/show')
                ? post
                : <String, dynamic>{'data': []};
            handler.resolve(Response(requestOptions: request, data: data));
          },
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            weiboDioClientProvider.overrideWithValue(client),
          ],
          child: MaterialApp(
            home: StatusDetailPage(status: WeiboStatusModel.fromJson(post)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('排序方式'));
      await tester.pumpAndSettle();
      expect(find.text('仅楼主'), findsNothing);
      var before = rootRequests.length;
      await tester.tap(find.text('按热度').last);
      await tester.pumpAndSettle();
      expect(rootRequests.length, before + 1);
      expect(rootRequests.last, 0);
      await tester.tap(find.byTooltip('排序方式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('含楼主').last);
      await tester.pumpAndSettle();
      expect(rootRequests.last, 1);
      await tester.ensureVisible(find.text('继续筛选'));
      await tester.tap(find.text('继续筛选'));
      await tester.pumpAndSettle();
      expect(find.text('别人发起的讨论', findRichText: true), findsOneWidget);
      for (final label in ['含楼主', '按时间', '按时间', '按热度']) {
        before = rootRequests.length;
        await tester.ensureVisible(find.byTooltip('排序方式'));
        await tester.tap(find.byTooltip('排序方式'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(rootRequests.length, before + 1);
        expect(rootRequests.last, label == '按热度' ? 0 : 1);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
