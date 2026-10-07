import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/widgets/review_refresh_header.dart';

void main() {
  test('overlay header keeps the normal pull threshold', () {
    expect(reviewFrostedAppBarRefreshHeader.triggerOffset, 70);
    expect(reviewFrostedAppBarRefreshHeader.safeArea, isFalse);
    expect(reviewFrostedAppBarRefreshHeader.position, IndicatorPosition.above);
  });

  testWidgets('refreshes without counting the overlay app-bar inset twice', (
    tester,
  ) async {
    var refreshCount = 0;
    final refreshCompleter = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final media = MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 80),
              viewPadding: const EdgeInsets.only(top: 24),
            );
            return Scaffold(
              extendBodyBehindAppBar: true,
              appBar: const PreferredSize(
                preferredSize: Size.fromHeight(56),
                child: SizedBox.expand(),
              ),
              body: MediaQuery(
                data: media,
                child: EasyRefresh(
                  header: reviewFrostedAppBarRefreshHeader,
                  onRefresh: () {
                    refreshCount++;
                    return refreshCompleter.future;
                  },
                  child: ListView.builder(
                    itemCount: 30,
                    itemBuilder: (_, __) => const SizedBox(height: 80),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    final indicatorPadding = tester.widget<Padding>(
      find.byKey(const ValueKey('review-frosted-refresh-indicator-inset')),
    );
    expect(indicatorPadding.padding, const EdgeInsets.only(top: 80));
    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pump();
    for (var attempt = 0; attempt < 20 && refreshCount == 0; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(refreshCount, 1);

    refreshCompleter.complete();
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
