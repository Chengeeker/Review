import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/theme/app_theme.dart';

void main() {
  test(
    'navigation stays transparent and readable in light and dark scenes',
    () {
      for (final brightness in Brightness.values) {
        final style = AppTheme.systemBars(brightness);
        expect(style.systemNavigationBarColor, Colors.transparent);
        expect(style.systemNavigationBarDividerColor, Colors.transparent);
        expect(style.systemNavigationBarContrastEnforced, isFalse);
        expect(
          style.systemNavigationBarIconBrightness,
          brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        );
      }
    },
  );
}
