import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/core/theme/app_text_scaler.dart';
import 'package:review/core/theme/theme_provider.dart';
import 'package:review/features/profile/presentation/theme_settings_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('app scale is applied through the platform scaling curve', () {
    const scaler = AppTextScaler(_QuadraticTextScaler(), 1.2);

    expect(scaler.scale(20), 24 + 24 * 24 / 100);
    expect(
      scaler.textScaleFactor,
      const _QuadraticTextScaler().scale(19.2) / 16,
    );
  });

  test(
    'font size preview is immediate, clamped, and saved on commit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final notifier = ThemeNotifier(storage);

      notifier.previewAppTextScale(1.25);
      expect(notifier.state.appTextScale, 1.25);
      expect(prefs.containsKey(StorageService.keyAppTextScale), isFalse);

      await notifier.setAppTextScale(2.0);
      expect(notifier.state.appTextScale, 1.4);
      expect(storage.getAppTextScale(), 1.4);
      notifier.dispose();
    },
  );

  testWidgets('personalization uses the Review X font-size slider layout', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const MaterialApp(home: ThemeSettingsPage()),
      ),
    );

    final sectionTitle = find.text('字体大小');
    await tester.scrollUntilVisible(sectionTitle, 300);
    expect(sectionTitle, findsOneWidget);

    final slider = find.byKey(const ValueKey('app-text-scale-slider'));
    await tester.scrollUntilVisible(slider, 160);
    await tester.pumpAndSettle();

    expect(find.text('应用字体大小'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(tester.widget<Slider>(slider).divisions, 12);
  });
}

class _QuadraticTextScaler extends TextScaler {
  const _QuadraticTextScaler();

  @override
  double scale(double fontSize) => fontSize + fontSize * fontSize / 100;

  @override
  double get textScaleFactor => 1;

  @override
  bool operator ==(Object other) => other is _QuadraticTextScaler;

  @override
  int get hashCode => runtimeType.hashCode;
}
