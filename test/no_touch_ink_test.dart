import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/theme/app_theme.dart';
import 'package:review/core/utils/haptic_feedback_util.dart';

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('ink-pixels')),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  final themes = {
    'light': AppTheme.lightTheme(),
    'dark': AppTheme.darkTheme(),
    'black': AppTheme.darkTheme(isPureBlack: true),
  };
  for (final entry in themes.entries) {
    test(
      '${entry.key} keeps focus and hover while suppressing pressed ink',
      () {
        final theme = entry.value;
        expect(theme.splashFactory, isA<HapticSplashFactory>());
        expect(theme.splashColor, Colors.transparent);
        expect(theme.highlightColor, Colors.transparent);
        for (final overlay in [
          theme.iconButtonTheme.style!.overlayColor!,
          theme.textButtonTheme.style!.overlayColor!,
          theme.filledButtonTheme.style!.overlayColor!,
          theme.outlinedButtonTheme.style!.overlayColor!,
          theme.elevatedButtonTheme.style!.overlayColor!,
          theme.segmentedButtonTheme.style!.overlayColor!,
          theme.radioTheme.overlayColor!,
          theme.checkboxTheme.overlayColor!,
          theme.switchTheme.overlayColor!,
          theme.tabBarTheme.overlayColor!,
          theme.navigationBarTheme.overlayColor!,
        ]) {
          expect(overlay.resolve({WidgetState.pressed}), Colors.transparent);
          expect(overlay.resolve({WidgetState.focused}), isNull);
          expect(overlay.resolve({WidgetState.hovered}), isNull);
        }
        expect(theme.focusColor.a, greaterThan(0));
        expect(theme.hoverColor.a, greaterThan(0));
        final sliderOverlay = theme.sliderTheme.overlayColor!;
        for (final state in [WidgetState.pressed, WidgetState.dragged]) {
          expect(
            WidgetStateProperty.resolveAs<Color>(sliderOverlay, {state}),
            Colors.transparent,
          );
        }
        expect(
          WidgetStateProperty.resolveAs<Color>(sliderOverlay, {
            WidgetState.focused,
          }).a,
          greaterThan(0),
        );
      },
    );

    testWidgets(
      '${entry.key} tap and long press paint no ink and keep actions',
      (tester) async {
        final calls = <MethodCall>[];
        HapticFeedbackUtil.isEnabled = true;
        HapticFeedbackUtil.resetForTesting();
        final focusNode = FocusNode();
        final originalFocusStrategy = FocusManager.instance.highlightStrategy;
        addTearDown(() {
          focusNode.dispose();
          FocusManager.instance.highlightStrategy = originalFocusStrategy;
          HapticFeedbackUtil.isEnabled = true;
          HapticFeedbackUtil.resetForTesting();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'HapticFeedback.vibrate') calls.add(call);
              return null;
            });
        var taps = 0;
        var longPresses = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.value,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 180,
                  height: 100,
                  child: RepaintBoundary(
                    key: const ValueKey('ink-pixels'),
                    child: Material(
                      color: entry.value.colorScheme.surface,
                      child: InkWell(
                        key: const ValueKey('ink-target'),
                        focusNode: focusNode,
                        onTap: () {
                          taps++;
                          HapticFeedbackUtil.light();
                        },
                        onLongPress: () {
                          longPresses++;
                          HapticFeedbackUtil.medium();
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final baseline = await _pixels(tester);
        final target = find.byKey(const ValueKey('ink-target'));
        final gesture = await tester.startGesture(tester.getCenter(target));
        await tester.pump(const Duration(milliseconds: 100));
        expect(await _pixels(tester), orderedEquals(baseline));
        await tester.pump(const Duration(milliseconds: 600));
        expect(longPresses, 1);
        expect(await _pixels(tester), orderedEquals(baseline));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(taps, 0);
        calls.clear();
        HapticFeedbackUtil.resetForTesting();
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(taps, 1);
        expect(calls, hasLength(1));
        calls.clear();
        HapticFeedbackUtil.isEnabled = false;
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(taps, 2);
        expect(calls, isEmpty);
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        focusNode.requestFocus();
        await tester.pumpAndSettle();
        expect(await _pixels(tester), isNot(orderedEquals(baseline)));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
