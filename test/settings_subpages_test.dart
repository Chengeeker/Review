import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/profile/presentation/screen_refresh_rate_page.dart';
import 'package:review/features/profile/presentation/theme_settings_page.dart';
import 'package:review/features/profile/presentation/weibo_style_settings_page.dart';
import 'package:review/features/settings/presentation/message_notification_settings_page.dart';
import 'package:review/features/settings/presentation/storage_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'settings subpages have no row separators, including expanded options',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1250);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.init();
      for (final page in const <Widget>[
        ThemeSettingsPage(),
        WeiboStyleSettingsPage(),
        StorageSettingsPage(),
        MessageNotificationSettingsPage(),
        ScreenRefreshRatePage(),
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [storageServiceProvider.overrideWithValue(storage)],
            child: MaterialApp(home: page),
          ),
        );
        await tester.pumpAndSettle();
        if (page is WeiboStyleSettingsPage) {
          await tester.tap(find.text('时间显示模式'));
          await tester.pumpAndSettle();
        }
        if (page is ScreenRefreshRatePage) {
          expect(find.text('自动'), findsOneWidget);
          expect(
            find.byIcon(Icons.radio_button_checked_rounded),
            findsOneWidget,
          );
          expect(
            find.byIcon(Icons.radio_button_unchecked_rounded),
            findsNWidgets(8),
          );
        }
        for (var step = 0; step < 12; step++) {
          expect(
            find.byType(Divider),
            findsNothing,
            reason: '${page.runtimeType}',
          );
          final scrollable = tester.state<ScrollableState>(
            find.byType(Scrollable).first,
          );
          if (scrollable.position.extentAfter <= 0) break;
          await tester.drag(find.byType(ListView).first, const Offset(0, -600));
          await tester.pumpAndSettle();
        }
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(
          scrollable.position.extentAfter,
          0,
          reason: 'checked all rows in ${page.runtimeType}',
        );
        expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
