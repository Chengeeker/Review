import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/widgets/app_section_card.dart';

void main() {
  testWidgets('uses a low-emphasis, zero-margin settings surface', (
    tester,
  ) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, colorScheme: scheme),
        home: const Scaffold(body: AppSectionCard(child: SizedBox(height: 48))),
      ),
    );

    final card = tester.widget<Card>(find.byType(Card));
    expect(card.margin, EdgeInsets.zero);
    expect(card.color, scheme.surfaceContainerLow);
    expect(card.elevation, 0);
    expect(card.surfaceTintColor, Colors.transparent);
    expect((card.shape as RoundedRectangleBorder).side.style, BorderStyle.none);
  });

  testWidgets('uses the intended container level in pure-black themes', (
    tester,
  ) async {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ).copyWith(
          surface: Colors.black,
          surfaceContainer: const Color(0xFF121212),
        );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, colorScheme: scheme),
        home: const Scaffold(body: AppSectionCard(child: SizedBox(height: 48))),
      ),
    );

    final card = tester.widget<Card>(find.byType(Card));
    expect(card.color, scheme.surfaceContainer);
  });
}
