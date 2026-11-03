import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:review/core/constants/api_constants.dart';
import 'package:review/core/design_system/components/review_preference_tile.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/core/theme/app_theme.dart';
import 'package:review/features/settings/presentation/settings_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'settings omit separators and retain app typography',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1250);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final loggedIn in [false, true]) {
        SharedPreferences.setMockInitialValues({
          StorageService.keyIsLoggedIn: loggedIn,
          StorageService.keyUserUid: '123',
          StorageService.keyUserNickname: '测试用户',
          StorageService.keyUserAvatar: 'avatar',
        });
        final storage = await StorageService.init();
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(loggedIn),
            overrides: [storageServiceProvider.overrideWithValue(storage)],
            child: MaterialApp(
              theme: loggedIn ? AppTheme.darkTheme() : AppTheme.lightTheme(),
              home: const SettingsView(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final title in ['缓存管理', 'WebDAV备份']) {
          final tile = tester.widget<ReviewPreferenceTile>(
            find.widgetWithText(ReviewPreferenceTile, title),
          );
          expect(tile.subtitle, isNull);
          expect(tester.widget<Text>(find.text(title)).style?.fontSize, 15);
        }
        expect(
          tester
              .widget<Text>(find.text('版本 ${ApiConstants.appVersion}'))
              .style
              ?.fontSize,
          12.5,
        );
        expect(find.byType(Divider), findsNothing);
        await tester.tap(find.text('关于 Review'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(Divider), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('uses M3 typography and omits absent helper text', (
    tester,
  ) async {
    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: ReviewPreferenceTile(title: '存储设置', onTap: null),
        ),
      ),
    );

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    final title = tester.widget<Text>(find.text('存储设置'));
    expect(tile.subtitle, isNull);
    final textTheme = Theme.of(
      tester.element(find.byType(ReviewPreferenceTile)),
    ).textTheme;
    expect(title.style?.fontSize, textTheme.titleMedium?.fontSize);
  });

  testWidgets('keeps useful helper text at the M3 body size', (tester) async {
    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: ReviewPreferenceTile(
            title: 'WebDAV备份',
            subtitle: '仅备份应用设置',
            onTap: null,
          ),
        ),
      ),
    );

    final subtitle = tester.widget<Text>(find.text('仅备份应用设置'));
    final textTheme = Theme.of(
      tester.element(find.byType(ReviewPreferenceTile)),
    ).textTheme;
    expect(subtitle.style?.fontSize, textTheme.bodyMedium?.fontSize);
  });
}
