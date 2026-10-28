import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:review/core/design_system/components/review_navigation_bar.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<LiquidGlassSettings> _resolveSettings(
  WidgetTester tester,
  Brightness brightness, [
  LiquidGlassSettings? settings,
]) async {
  late LiquidGlassSettings resolved;
  await tester.pumpWidget(
    MaterialApp(
      home: Theme(
        data: ThemeData(brightness: brightness),
        child: Builder(
          builder: (context) {
            resolved = ReviewNavigationBar.liquidGlassSettingsFor(
              context,
              settings,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return resolved;
}

void main() {
  testWidgets(
    'light liquid glass brightens the shell while dark stays intact',
    (tester) async {
      final light = await _resolveSettings(tester, Brightness.light);
      expect(light.glassColor, const Color(0xF0FFFFFF));
      expect(light.rimLight, 1);
      expect(
        light.thickness,
        ReviewNavigationBar.liquidGlassSettings.thickness,
      );
      expect(light.blur, ReviewNavigationBar.liquidGlassSettings.blur);

      final dark = await _resolveSettings(tester, Brightness.dark);
      expect(
        dark.glassColor,
        ReviewNavigationBar.liquidGlassSettings.glassColor,
      );
      expect(dark.rimLight, ReviewNavigationBar.liquidGlassSettings.rimLight);
      expect(dark.thickness, ReviewNavigationBar.liquidGlassSettings.thickness);
      expect(dark.blur, ReviewNavigationBar.liquidGlassSettings.blur);
      expect(dark.bodyMode, ReviewNavigationBar.liquidGlassSettings.bodyMode);

      const custom = LiquidGlassSettings(
        visibility: 0.5,
        glassColor: Color(0x66000000),
        thickness: 32,
      );
      final lightCustom = await _resolveSettings(
        tester,
        Brightness.light,
        custom,
      );
      expect(lightCustom.glassColor, const Color(0xF0FFFFFF));
      expect(lightCustom.rimLight, 1);
      expect(lightCustom.visibility, 0.5);
      expect(lightCustom.thickness, 32);
    },
  );

  testWidgets('light liquid glass navigation uses readable themed colors', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      StorageService.keyUseFloatingNavBar: true,
      StorageService.keyUseLiquidGlass: true,
    });
    final storage = StorageService(await SharedPreferences.getInstance());
    final container = ProviderContainer(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: Brightness.light,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, colorScheme: scheme),
          home: Scaffold(
            body: const ColoredBox(color: Colors.white),
            bottomNavigationBar: ReviewNavigationBar(
              selectedIndex: 0,
              hasBottomInset: false,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final glassBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
    expect(glassBar.settings?.glassColor, const Color(0xF0FFFFFF));
    expect(glassBar.settings?.rimLight, 1);
    expect(glassBar.settings?.shadowElevation, 0.55);
    expect(glassBar.indicatorSettings?.glassColor, const Color(0x18000000));
    expect(glassBar.indicatorSettings?.bodyMode, GlassBodyMode.clear);
    expect(glassBar.indicatorSettings?.rimShade, 0.12);
    expect(glassBar.indicatorSettings?.rimLight, 0.35);
    expect(glassBar.indicatorColor, const Color(0x26000000));
    expect(glassBar.selectedIconColor, scheme.primary);
    expect(glassBar.selectedLabelColor, scheme.primary);
    expect(glassBar.unselectedIconColor, scheme.onSurfaceVariant);
    expect(glassBar.unselectedLabelColor, scheme.onSurfaceVariant);
    expect(
      find.byKey(const ValueKey('liquid-glass-light-rim')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
