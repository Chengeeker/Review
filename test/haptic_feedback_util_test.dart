import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/utils/haptic_feedback_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    HapticFeedbackUtil.isEnabled = true;
    HapticFeedbackUtil.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    HapticFeedbackUtil.resetForTesting();
  });

  test('manual feedback remains a single event for an action', () async {
    HapticFeedbackUtil.light();
    HapticFeedbackUtil.light();

    await Future<void>.delayed(Duration.zero);

    expect(calls, hasLength(1));
    expect(calls.single.arguments, 'HapticFeedbackType.lightImpact');
  });

  test('rapid feedback across types is throttled', () async {
    HapticFeedbackUtil.light();
    HapticFeedbackUtil.selection();

    await Future<void>.delayed(Duration.zero);

    expect(calls, hasLength(1));
    expect(calls.single.arguments, 'HapticFeedbackType.lightImpact');
  });

  test('standalone manual feedback still works', () async {
    HapticFeedbackUtil.light();

    await Future<void>.delayed(Duration.zero);

    expect(calls, hasLength(1));
    expect(calls.single.arguments, 'HapticFeedbackType.lightImpact');
  });

  test('refresh feedback fires once before the refresh action', () async {
    var actionStarted = false;

    await HapticFeedbackUtil.refresh(() async {
      actionStarted = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(actionStarted, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.arguments, 'HapticFeedbackType.lightImpact');
  });

  test('global splash feedback is consumed by a light callback', () async {
    HapticFeedbackUtil.light(fromSplash: true);
    HapticFeedbackUtil.light();

    await Future<void>.delayed(Duration.zero);

    expect(calls, hasLength(1));
  });

  test('global splash feedback is consumed by medium and selection callbacks',
      () async {
    HapticFeedbackUtil.light(fromSplash: true);
    HapticFeedbackUtil.medium();
    HapticFeedbackUtil.selection();

    await Future<void>.delayed(Duration.zero);

    expect(calls, hasLength(1));
    expect(calls.single.arguments, 'HapticFeedbackType.lightImpact');
  });
}
