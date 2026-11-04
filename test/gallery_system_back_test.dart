import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/utils/spring_page_route.dart';

Future<Object?> backGesture(WidgetTester tester, String method) async {
  Object? result;
  const channel = SystemChannels.backGesture;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    channel.name,
    channel.codec.encodeMethodCall(
      MethodCall(
        method,
        method == 'startBackGesture'
            ? {
                'touchOffset': [0.0, 300.0],
                'progress': 0.0,
                'swipeEdge': 0,
              }
            : null,
      ),
    ),
    (data) => result = channel.codec.decodeEnvelope(data!),
  );
  return result;
}

void main() {
  for (final nestedSource in [false, true]) {
    for (final openingMs in [0, 80, 400]) {
      testWidgets(
        'system back stays with exiting gallery: nested=$nestedSource open=$openingMs',
        (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          var exits = 0;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          final frameworkBack = <bool>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'SystemNavigator.pop') exits++;
              if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
                frameworkBack.add(call.arguments as bool);
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          final navigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              home: const Scaffold(body: Text('root feed')),
            ),
          );
          if (nestedSource) {
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('source detail')),
              ),
            );
            await tester.pumpAndSettle();
          }
          navigator.currentState!.push(
            PhysicsSpringGalleryRoute<void>(
              child: const Scaffold(body: Text('gallery')),
            ),
          );
          await tester.pump();
          await tester.pump(Duration(milliseconds: openingMs));
          await tester.binding.handlePopRoute();
          await tester.binding.handlePopRoute();
          expect(
            exits,
            0,
            reason: 'a repeated gallery back must not finish the Activity',
          );
          if (openingMs > 0) {
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 10));
            await tester.binding.handlePopRoute();
            expect(exits, 0);
            expect(
              frameworkBack.last,
              isTrue,
              reason: 'Android back must stay in Flutter during gallery exit',
            );
          }
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump();
          expect(
            find.text(nestedSource ? 'source detail' : 'root feed'),
            findsOneWidget,
          );
          expect(PhysicsSpringGalleryRoute.hasActiveRoutes, isFalse);
          await tester.binding.handlePopRoute();
          if (nestedSource) {
            expect(exits, 0);
            await tester.pumpAndSettle();
            expect(find.text('root feed'), findsOneWidget);
            await tester.binding.handlePopRoute();
          }
          expect(
            exits,
            1,
            reason: 'normal root back must work after the gallery is gone',
          );
          expect(tester.takeException(), isNull);
          expect(frameworkBack.last, isFalse);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }

  for (final end in [
    'commitBackGesture',
    'cancelBackGesture',
    'reopen',
    'background',
  ]) {
    testWidgets(
      'predictive back retains gallery ownership through disposal: $end',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        var exits = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemNavigator.pop') exits++;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('root feed')),
          ),
        );
        final old = PhysicsSpringGalleryRoute<void>(
          child: const Scaffold(body: Text('gallery')),
        );
        navigator.currentState!.push(old);
        await tester.pumpAndSettle();
        await backGesture(tester, 'startBackGesture');
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(old.navigator, isNull);
        final fresh = end == 'reopen'
            ? PhysicsSpringGalleryRoute<void>(
                child: const Scaffold(body: Text('new gallery')),
              )
            : null;
        if (fresh != null) {
          navigator.currentState!.push(fresh);
          await tester.pumpAndSettle();
        }
        if (end == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
        } else {
          await backGesture(
            tester,
            end == 'cancelBackGesture' ? end : 'commitBackGesture',
          );
        }
        expect(
          exits,
          0,
          reason: 'an old gallery gesture cannot exit the Activity',
        );
        if (fresh != null) {
          expect(fresh.isCurrent, isTrue);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        }
        await tester.binding.handlePopRoute();
        expect(exits, 1);
        expect(find.text('root feed'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets(
    'predictive cancel keeps gallery open and commit closes it once',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var exits = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') exits++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('root feed')),
        ),
      );
      final gallery = PhysicsSpringGalleryRoute<void>(
        child: const Scaffold(body: Text('gallery')),
      );
      navigator.currentState!.push(gallery);
      await tester.pumpAndSettle();
      expect(await backGesture(tester, 'startBackGesture'), isTrue);
      await backGesture(tester, 'cancelBackGesture');
      expect(gallery.isCurrent, isTrue);
      expect(exits, 0);
      expect(await backGesture(tester, 'startBackGesture'), isTrue);
      await backGesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('root feed'), findsOneWidget);
      expect(PhysicsSpringGalleryRoute.hasActiveRoutes, isFalse);
      expect(exits, 0);
      await tester.binding.handlePopRoute();
      expect(exits, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('old gallery cleanup cannot unlock the new gallery source', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var exits = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exits++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('root feed')),
      ),
    );
    final old = PhysicsSpringGalleryRoute<void>(
      child: const Scaffold(body: Text('old gallery')),
    );
    navigator.currentState!.push(old);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final fresh = PhysicsSpringGalleryRoute<void>(
      child: const Scaffold(body: Text('new gallery')),
    );
    navigator.currentState!.push(fresh);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(old.navigator, isNull);
    await tester.binding.handlePopRoute();
    await tester.binding.handlePopRoute();
    expect(exits, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('root feed'), findsOneWidget);
    expect(fresh.navigator, isNull);
    expect(PhysicsSpringGalleryRoute.hasActiveRoutes, isFalse);
    await tester.binding.handlePopRoute();
    expect(exits, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
