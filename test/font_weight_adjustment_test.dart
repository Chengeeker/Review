import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/theme/app_theme.dart';
import 'package:review/core/theme/theme_provider.dart';

void main() {
  group('FontWeight Adjustment Tests', () {
    test('Standard adjustment (0) preserves original weight', () {
      expect(AppTheme.adjustFontWeight(FontWeight.normal, 0), FontWeight.w400);
      expect(AppTheme.adjustFontWeight(FontWeight.bold, 0), FontWeight.w700);
      expect(AppTheme.adjustFontWeight(FontWeight.w600, 0), FontWeight.w600);
    });

    test('Positive adjustment increases font weight', () {
      // +100 delta (e.g. 1 step thicker in Android settings)
      expect(AppTheme.adjustFontWeight(FontWeight.w400, 100), FontWeight.w500);
      expect(AppTheme.adjustFontWeight(FontWeight.w600, 100), FontWeight.w700);
      expect(AppTheme.adjustFontWeight(FontWeight.bold, 100), FontWeight.w800);

      // +200 delta (e.g. 2 steps thicker)
      expect(AppTheme.adjustFontWeight(FontWeight.w400, 200), FontWeight.w600);
      expect(AppTheme.adjustFontWeight(FontWeight.w600, 200), FontWeight.w800);
      expect(AppTheme.adjustFontWeight(FontWeight.bold, 200), FontWeight.w900);

      // +300 delta (Bold text mode)
      expect(AppTheme.adjustFontWeight(FontWeight.w400, 300), FontWeight.w700);
      expect(AppTheme.adjustFontWeight(FontWeight.w600, 300), FontWeight.w900);
      expect(AppTheme.adjustFontWeight(FontWeight.bold, 300), FontWeight.w900); // Clamped at w900
    });

    test('Negative adjustment decreases font weight', () {
      // -100 delta (1 step thinner)
      expect(AppTheme.adjustFontWeight(FontWeight.w400, -100), FontWeight.w300);
      expect(AppTheme.adjustFontWeight(FontWeight.w600, -100), FontWeight.w500);
      expect(AppTheme.adjustFontWeight(FontWeight.bold, -100), FontWeight.w600);

      // -200 delta (2 steps thinner)
      expect(AppTheme.adjustFontWeight(FontWeight.w400, -200), FontWeight.w200);
      expect(AppTheme.adjustFontWeight(FontWeight.w600, -200), FontWeight.w400);
      expect(AppTheme.adjustFontWeight(FontWeight.bold, -200), FontWeight.w500);
    });

    test('ThemeData adjusts all textTheme styles with fontWeightAdjustment', () {
      final lightTheme0 = AppTheme.lightTheme(fontWeightAdjustment: 0);
      expect(lightTheme0.textTheme.bodyMedium?.fontWeight, FontWeight.w400);
      expect(lightTheme0.appBarTheme.titleTextStyle?.fontWeight, FontWeight.w700);

      final darkTheme300 = AppTheme.darkTheme(fontWeightAdjustment: 300);
      expect(darkTheme300.textTheme.bodyMedium?.fontWeight, FontWeight.w700);
      expect(darkTheme300.appBarTheme.titleTextStyle?.fontWeight, FontWeight.w900);
    });

    test('ThemeState calculates effectiveFontWeightAdjustment correctly', () {
      // 1. Follow system (useCustomFontWeight = false)
      const stateSystem = ThemeState(
        useCustomFontWeight: false,
        customFontWeightDelta: 200,
        systemFontWeightAdjustment: 100,
      );
      expect(stateSystem.effectiveFontWeightAdjustment, 100);

      // 2. Custom override enabled (useCustomFontWeight = true)
      const stateCustom = ThemeState(
        useCustomFontWeight: true,
        customFontWeightDelta: 200,
        systemFontWeightAdjustment: 100,
      );
      expect(stateCustom.effectiveFontWeightAdjustment, 200);
    });
  });
}
