import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/design_system/components/review_preference_tile.dart';

void main() {
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
