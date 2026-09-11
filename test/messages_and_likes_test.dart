import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/drawer_features/presentation/likes_comments_page.dart';
import 'package:review/features/drawer_features/presentation/likes_favorites_page.dart';
import 'package:review/features/drawer_features/presentation/my_messages_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
}
