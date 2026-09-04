import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Global Haptic Feedback Controller with Anti-Double-Trigger Cooldown (防连击与防重复震动机制)
class HapticFeedbackUtil {
  HapticFeedbackUtil._();

  static bool isEnabled = true;
  static int _lastTriggerTime = 0;
  static const int _cooldownMs = 40;

  static bool _canTrigger() {
    if (!isEnabled) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTriggerTime < _cooldownMs) {
      return false;
    }
    _lastTriggerTime = now;
    return true;
  }

  static void light() {
    if (_canTrigger()) {
      HapticFeedback.lightImpact();
    }
  }

  static void selection() {
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
    HapticFeedbackUtil.light();

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
