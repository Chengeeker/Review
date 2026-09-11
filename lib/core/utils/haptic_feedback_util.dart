import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Global Haptic Feedback Controller with Anti-Double-Trigger Cooldown (防连击与防重复震动机制)
class HapticFeedbackUtil {
  HapticFeedbackUtil._();

  static bool _isEnabled = true;
  static int _lastTriggerTime = 0;
  static int _lastAutomaticTapTime = 0;
  static bool _automaticTapPending = false;
  static const int _cooldownMs = 40;
  // Material 的 InkWell 在按下时触发自动触感，而 onTap 通常在抬起时才执行。
  // 这个窗口需要覆盖一次正常点击的按住时间，但不能变成全局的长时间节流。
  static const int _automaticTapWindowMs = 500;

  static bool get isEnabled => _isEnabled;

  static set isEnabled(bool value) {
    _isEnabled = value;
    if (!value) {
      _automaticTapPending = false;
    }
  }

  static bool _canTrigger() {
    if (!isEnabled) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTriggerTime < _cooldownMs) {
      return false;
    }
    _lastTriggerTime = now;
    return true;
  }

  /// Consume the automatic Material tap feedback before emitting a manual
  /// tap feedback from the same gesture.
  ///
  /// The custom splash is created on pointer-down, while many callbacks call
  /// this utility on pointer-up. Treating the next light/selection feedback
  /// in this short window as the same tap prevents a single click from
  /// vibrating twice without removing feedback from GestureDetector-only
  /// interactions.
  static bool _consumeAutomaticTapFeedback() {
    if (!isEnabled || !_automaticTapPending) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    final isSameTap = now - _lastAutomaticTapTime <= _automaticTapWindowMs;
    _automaticTapPending = false;
    return isSameTap;
  }

  static void light({bool fromSplash = false}) {
    if (!isEnabled) return;

    if (!fromSplash && _consumeAutomaticTapFeedback()) {
      return;
    }

    if (_canTrigger()) {
      if (fromSplash) {
        _lastAutomaticTapTime = DateTime.now().millisecondsSinceEpoch;
        _automaticTapPending = true;
      }
      HapticFeedback.lightImpact();
    }
  }

  static void selection() {
    if (_consumeAutomaticTapFeedback()) {
      return;
    }

    if (_canTrigger()) {
      HapticFeedback.selectionClick();
    }
  }

  static void medium() {
    if (_canTrigger()) {
      HapticFeedback.mediumImpact();
    }
  }

  static void heavy() {
    if (_canTrigger()) {
      HapticFeedback.heavyImpact();
    }
  }

  /// Reset only the in-memory deduplication state in tests.
  @visibleForTesting
  static void resetForTesting() {
    _lastTriggerTime = 0;
    _lastAutomaticTapTime = 0;
    _automaticTapPending = false;
  }
}

/// Custom Material Splash Factory that automatically triggers haptic feedback on every InkWell/Button/Card/ListTile tap
class HapticSplashFactory extends InteractiveInkFeatureFactory {
  final InteractiveInkFeatureFactory _delegate;

  const HapticSplashFactory({
    InteractiveInkFeatureFactory delegate = InkSplash.splashFactory,
  }) : _delegate = delegate;

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    HapticFeedbackUtil.light(fromSplash: true);

    return _delegate.create(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: onRemoved,
    );
  }
}
