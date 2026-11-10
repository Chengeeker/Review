import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/widgets/app_section_card.dart';

void main() {
  testWidgets('settings card remains distinct from the actual page', (tester) async {
    for (final page in [const Color(0xFFFFF8FF), const Color(0xFF111215), Colors.black]) {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: page.computeLuminance() > .5 ? Brightness.light : Brightness.dark,
      ).copyWith(surfaceContainerHigh: page);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: scheme, scaffoldBackgroundColor: page),
        home: const Scaffold(body: AppSectionCard(child: Text('设置'))),
      ));
      final card = tester.widget<Card>(find.byType(Card)).color!;
      final baseline = page.computeLuminance() + .05;
      final fill = card.computeLuminance() + .05;
      expect(fill >= baseline * 1.12 || baseline >= fill * 1.12, isTrue);
    }
  });
}
