import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/utils/card_detail_route.dart';

class _PushObserver extends NavigatorObserver {
  final pushed = Completer<void>();
  int count = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return;
    count++;
    if (!pushed.isCompleted) pushed.complete();
  }
}

void main() {
  testWidgets('source persists while fixed detail fills the expanding card', (
    tester,
  ) async {
    final observer = _PushObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => RepaintBoundary(
                child: SizedBox(
                  width: 200,
                  height: 120,
                  child: ColoredBox(
                    color: Colors.red,
                    child: TextButton(
                      onPressed: () => openCardDetail(
                        context,
                        const Scaffold(
                          body: Padding(
                            padding: EdgeInsets.only(top: 30),
                            child: Text('header'),
                          ),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final source = tester.getRect(find.byType(RepaintBoundary).last);
    await tester.tap(find.text('open'));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.runAsync(() => observer.pushed.future);
    await tester.pump();
    await tester.pump();
    expect(observer.count, 1);
    final preview = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(tester.getRect(find.byType(ClipRRect)), source);
    expect(tester.getTopLeft(find.text('header')).dy, 30);
    final detailOpacity = find
        .ancestor(of: find.text('header'), matching: find.byType(Opacity))
        .first;
    expect(tester.widget<Opacity>(detailOpacity).opacity, 0);
    await tester.pump(const Duration(milliseconds: 160));
    final during = tester.getRect(find.byType(ClipRRect));
    expect(during.width, greaterThan(200));
    expect(during.width, lessThan(800));
    expect(tester.getTopLeft(find.text('header')).dy, 30);
    expect(tester.widget<Opacity>(detailOpacity).opacity, greaterThan(0));
    expect(preview.debugDisposed, isFalse);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(ClipRRect)).size, const Size(800, 600));
    Navigator.of(tester.element(find.text('header'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(preview.debugDisposed, isFalse);
    await tester.pumpAndSettle();
    expect(preview.debugDisposed, isTrue);
    expect(find.text('open'), findsOneWidget);
    expect(find.text('header'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion uses the standard route without a capture', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  openCardDetail(context, const Scaffold(body: Text('detail'))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
    Navigator.of(tester.element(find.text('detail'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
