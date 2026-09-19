import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Global Haptic Feedback Controller with Anti-Double-Trigger Cooldown (防连击与防重复震动机制)
class HapticFeedbackUtil {
  HapticFeedbackUtil._();

  static bool isEnabled = true;
  static int _lastTriggerTime = 0;
  static int _lastAutomaticTapTime = 0;
  static bool _automaticTapPending = false;
  static const int _cooldownMs = 40;
  static const int _automaticTapWindowMs = 300;

  static bool _canTrigger() {
    if (!isEnabled) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTriggerTime < _cooldownMs) {
      return false;
    }
    _lastTriggerTime = now;
    return true;
  }

  /// Emits the shared feedback for a confirmed action. When called by the
  /// Material splash bridge, it records the pointer-down feedback so the
  /// matching callback does not emit a second vibration.
  static void light({bool fromSplash = false}) {
    if (!isEnabled) return;

    if (!fromSplash && _consumeAutomaticTapFeedback()) return;

    if (_canTrigger()) {
      if (fromSplash) {
        _lastAutomaticTapTime = DateTime.now().millisecondsSinceEpoch;
        _automaticTapPending = true;
      }
      HapticFeedback.lightImpact();
    }
  }

  static void selection() {
    if (_consumeAutomaticTapFeedback()) return;
    if (_canTrigger()) {
      HapticFeedback.selectionClick();
    }
  }

  static void medium() {
    if (_consumeAutomaticTapFeedback()) return;
    if (_canTrigger()) {
      HapticFeedback.mediumImpact();
    }
  }

  static void heavy() {
    if (_consumeAutomaticTapFeedback()) return;
    if (_canTrigger()) {
      HapticFeedback.heavyImpact();
    }
  }

  /// Adds one light feedback when a pull-to-refresh action starts.
  /// The callback uses the same global enablement and cooldown rules as taps.
  static Future<void> refresh(FutureOr<void> Function() action) async {
    light();
    await action();
  }

  /// Reset only the in-memory deduplication state in tests.
  @visibleForTesting
  static void resetForTesting() {
    _lastTriggerTime = 0;
    _lastAutomaticTapTime = 0;
    _automaticTapPending = false;
  }

  static bool _consumeAutomaticTapFeedback() {
    if (!isEnabled || !_automaticTapPending) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sameTap = now - _lastAutomaticTapTime <= _automaticTapWindowMs;
    _automaticTapPending = false;
    return sameTap;
  }
}

/// Adds one global light feedback at Material pointer-down time. Business
/// callbacks consume that event through [HapticFeedbackUtil], so a normal
/// InkWell/ListTile/IconButton tap still feels global without double vibration.
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
