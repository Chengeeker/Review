import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/utils/card_detail_route.dart';

void main() {
  testWidgets('card detail expands and closes back to its source', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => SizedBox(
                width: 200,
                height: 120,
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    cardDetailRoute(
                      context,
                      const Scaffold(body: Text('detail')),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final during = tester.getRect(find.byType(ClipRRect));
    expect(during.width, greaterThan(200));
    expect(during.width, lessThan(800));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(ClipRRect)).size, const Size(800, 600));
    Navigator.of(tester.element(find.text('detail'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.text('detail'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
