import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/core/theme/app_theme.dart';
import 'package:review/core/widgets/app_section_card.dart';
import 'package:review/features/profile/presentation/custom_app_icon_page.dart';
import 'package:review/features/profile/presentation/theme_settings_page.dart';
import 'package:review/features/profile/presentation/weibo_style_settings_page.dart';
import 'package:review/features/settings/presentation/cache_management_page.dart';
import 'package:review/features/settings/presentation/settings_view.dart';
import 'package:review/features/settings/presentation/webdav_backup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('section headings align with card content in $direction', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 1250);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.init();
      final pages = <(Widget, Map<String, Finder>)>[
        (
          const SettingsView(),
          {
            '偏好与功能': find.byIcon(Icons.palette_outlined),
            '存储与备份': find.byIcon(Icons.folder_open_outlined),
            '账号设置': find.byIcon(Icons.login_rounded),
            '关于与支持': find.byIcon(Icons.info_outline_rounded),
          },
        ),
        (
          const ThemeSettingsPage(),
          {
            '明暗模式': find.byIcon(Icons.contrast_rounded),
            '色彩方案': find.byIcon(Icons.auto_awesome_outlined),
            '字体粗细': find.byIcon(Icons.format_bold_rounded),
            '字体大小': find.byIcon(Icons.format_size_rounded),
            '底部导航': find.byIcon(Icons.dock_rounded),
            '显示效果': find.byIcon(Icons.blur_on_rounded),
            '应用图标': find.byIcon(Icons.app_shortcut_rounded),
            '屏幕显示': find.byIcon(Icons.speed_rounded),
            '触感与震动': find.byIcon(Icons.vibration_rounded),
          },
        ),
        (
          const WeiboStyleSettingsPage(),
          {
            '卡片与时间显示': find.byIcon(Icons.schedule_rounded),
            '排版与视觉布局': find.byIcon(Icons.dashboard_customize_outlined),
            '功能开关与视觉控制': find.text('链接颜色跟随主题'),
          },
        ),
        (const CustomAppIconPage(), {'可选预设图标': find.byType(ListTile).first}),
        (
          const CacheManagementPage(),
          {'自动清理规则': find.byIcon(Icons.auto_delete_outlined)},
        ),
        (
          const WebDavBackupPage(),
          {
            'WebDAV 服务器配置': find.byType(TextFormField).first,
            '云端备份与还原操作': find
                .byWidgetPredicate((widget) => widget is FilledButton)
                .first,
          },
        ),
      ];
      for (final (page, headings) in pages) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [storageServiceProvider.overrideWithValue(storage)],
            child: MaterialApp(
              theme: direction == TextDirection.ltr
                  ? AppTheme.lightTheme()
                  : AppTheme.darkTheme(),
              home: Directionality(textDirection: direction, child: page),
            ),
          ),
        );
        await tester.pump();
        for (final entry in headings.entries) {
          await tester.scrollUntilVisible(
            find.text(entry.key),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          if (page is! CacheManagementPage) await tester.pumpAndSettle();
          final headingRect = tester.getRect(find.text(entry.key));
          expect(
            find.ancestor(
              of: find.text(entry.key),
              matching: find.byType(Card),
            ),
            findsNothing,
            reason: '${entry.key} belongs above its card',
          );
          var contentRect = tester.getRect(entry.value);
          if (page is CustomAppIconPage) {
            final tile = tester.widget<ListTile>(entry.value);
            contentRect = tester.getRect(find.byWidget(tile.leading!));
          }
          expect(
            direction == TextDirection.ltr
                ? headingRect.left
                : headingRect.right,
            closeTo(
              direction == TextDirection.ltr
                  ? contentRect.left
                  : contentRect.right,
              0.01,
            ),
            reason: '${page.runtimeType}: ${entry.key}',
          );
          if (page is ThemeSettingsPage || page is WebDavBackupPage) {
            final card = find
                .ancestor(
                  of: entry.value,
                  matching: find.byType(AppSectionCard),
                )
                .first;
            expect(
              tester.getRect(card).top - headingRect.bottom,
              closeTo(12, 0.01),
              reason: '${entry.key} has a 12dp gap above its card',
            );
            expect(
              tester.widget<Text>(find.text(entry.key)).style?.fontSize,
              14,
            );
          }
        }
        expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }
}
