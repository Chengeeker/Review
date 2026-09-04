import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/profile/presentation/user_timeline_search_page.dart';
import 'package:review/features/search/data/search_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('User Timeline Search Tests', () {
    test('SearchRepository.searchUserStatuses returns empty on empty query or empty uid', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final storage = StorageService(sp);
      final client = WeiboDioClient(storage);
      final repo = SearchRepository(client);

      final res1 = await repo.searchUserStatuses(uid: '', keyword: 'test');
      expect(res1, isEmpty);

      final res2 = await repo.searchUserStatuses(uid: '12345', keyword: '   ');
      expect(res2, isEmpty);
    });

    testWidgets('UserTimelineSearchPage displays placeholder and initial guidance', (tester) async {
      const user = WeiboUserModel(
        id: '12345678',
        screenName: '测试科技博主',
        avatar: '',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: UserTimelineSearchPage(user: user, autofocus: false),
          ),
        ),
      );

      // Verify TextField and hint text
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('搜索 @测试科技博主 的微博'), findsOneWidget);
      expect(find.text('搜索'), findsOneWidget);

      // Verify initial guidance
      expect(find.text('输入关键词，检索 @测试科技博主 的微博'), findsOneWidget);
      expect(find.byIcon(Icons.manage_search_rounded), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
