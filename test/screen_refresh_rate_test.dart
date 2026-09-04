import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/theme/theme_provider.dart';

void main() {
  group('Screen Refresh Rate Mode Tests', () {
    test('Default ThemeState has screenRefreshRateMode = 0 (Auto)', () {
      const state = ThemeState();
      expect(state.screenRefreshRateMode, 0);
    });

    test('ThemeState copyWith correctly updates screenRefreshRateMode', () {
      const state = ThemeState();
      final updated = state.copyWith(screenRefreshRateMode: 5);
      expect(updated.screenRefreshRateMode, 5);
    });

    test('All 9 refresh rate modes (0~8) are distinct and valid', () {
      final modes = [0, 1, 2, 3, 4, 5, 6, 7, 8];
      for (final m in modes) {
        final state = const ThemeState().copyWith(screenRefreshRateMode: m);
        expect(state.screenRefreshRateMode, m);
      }
    });
  });
}
