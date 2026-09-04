import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/detail/data/models/weibo_edit_history_model.dart';
import 'package:review/features/detail/data/detail_repository.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';
import 'package:review/features/detail/presentation/widgets/edit_history_bottom_sheet.dart';

class FakeDetailRepository extends Fake implements DetailRepository {
  @override
  Future<WeiboEditHistoryModel?> getEditHistory(String mid, {int page = 1}) async {
    return WeiboEditHistoryModel(
      ok: 1,
      total: 2,
      statuses: [
        WeiboStatusModel.fromJson({
          'id': '5339420032499899',
          'mid': '5339420032499899',
          'created_at': 'Fri Sep 04 14:35:04 +0800 2026',
          'text_raw': '最新版本内容',
          'region_name': '发布于 北京',
        }),
        WeiboStatusModel.fromJson({
          'id': '5339420032499899',
          'mid': '5339420032499899',
          'created_at': 'Fri Sep 04 13:40:00 +0800 2026',
          'text_raw': '最初版本内容',
          'region_name': '发布于 北京',
        }),
      ],
    );
  }
}

void main() {
  group('Weibo Edit History Model & Parsing Tests', () {
    test('WeiboStatusModel parses edit_count and isEdited correctly', () {
      final sampleJsonWithEdit = {
        'id': '5339420032499899',
        'mid': '5339420032499899',
        'created_at': 'Fri Sep 04 14:35:04 +0800 2026',
        'text_raw': '早 ​​​',
        'source': 'iPhone 15 Pro',
        'edit_count': 1,
        'user': {
          'id': '6048569942',
          'screen_name': '数码闲聊站',
          'avatar_hd': 'https://example.com/avatar.jpg',
        },
      };

      final status = WeiboStatusModel.fromJson(sampleJsonWithEdit);
      expect(status.id, '5339420032499899');
      expect(status.editCount, 1);
      expect(status.isEdited, true);

      final jsonMap = status.toJson();
      expect(jsonMap['edit_count'], 1);
    });

    test('WeiboStatusModel defaults editCount to 0 when not present', () {
      final sampleJsonNoEdit = {
        'id': '12345',
        'mid': '12345',
        'created_at': 'Fri Sep 04 14:00:00 +0800 2026',
        'text_raw': 'Normal tweet',
        'source': 'Web',
        'user': {
          'id': '100',
          'screen_name': 'Tester',
        },
      };

      final status = WeiboStatusModel.fromJson(sampleJsonNoEdit);
      expect(status.editCount, 0);
      expect(status.isEdited, false);
    });

    test('WeiboEditHistoryModel parses response with revisions correctly', () {
      final mockApiResponse = {
        'ok': 1,
        'total': 2,
        'statuses': [
          {
            'id': '-1',
            'mid': '5339420032499899',
            'created_at': 'Fri Sep 04 14:35:04 +0800 2026',
            'text_raw': '早 ​​​',
            'edit_count': 1,
            'region_name': '发布于 北京',
            'user': {
              'id': '6048569942',
              'screen_name': '数码闲聊站',
            },
          },
          {
            'id': '-1',
            'mid': '5339420032499899',
            'created_at': 'Fri Sep 04 13:40:00 +0800 2026',
            'text_raw': '独家信息：子系中端性能机确定有Pro...',
            'region_name': '发布于 北京',
            'user': {
              'id': '6048569942',
              'screen_name': '数码闲聊站',
            },
          },
        ],
      };

      final model = WeiboEditHistoryModel.fromJson(mockApiResponse);
      expect(model.ok, 1);
      expect(model.total, 2);
      expect(model.statuses.length, 2);
      expect(model.statuses[0].textRaw, '早 ​​​');
      expect(model.statuses[1].textRaw.contains('独家信息'), true);
      expect(model.statuses[0].regionName, '发布于 北京');
    });
  });

  group('EditHistoryBottomSheet Widget Tests', () {
    testWidgets('Renders EditHistoryBottomSheet frame, title and history items', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final fakeRepo = FakeDetailRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            detailRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: EditHistoryBottomSheet(
                statusId: '5339420032499899',
                authorName: '数码闲聊站',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify header components
      expect(find.text('微博编辑记录'), findsOneWidget);
      expect(find.text('共 2 个修订版本'), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsOneWidget);

      // Verify history items loaded from FakeDetailRepository
      expect(find.text('最新版本内容'), findsOneWidget);
      expect(find.text('最初版本内容'), findsOneWidget);
      expect(find.text('🔥 最新版本 (当前)'), findsOneWidget);
      expect(find.text('🌱 首次发布'), findsOneWidget);
    });
  });
}
