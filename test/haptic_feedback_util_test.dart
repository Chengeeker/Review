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

  test('manual tap feedback is consumed after a Material splash', () async {
    HapticFeedbackUtil.light(fromSplash: true);
    HapticFeedbackUtil.light();

    await Future<void>.delayed(Duration.zero);

    expect(calls, hasLength(1));
    expect(calls.single.arguments, 'HapticFeedbackType.lightImpact');
  });

  test('selection feedback is also consumed after a Material splash', () async {
    HapticFeedbackUtil.light(fromSplash: true);
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
}
