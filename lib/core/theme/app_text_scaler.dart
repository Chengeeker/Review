import 'package:flutter/painting.dart';

/// Applies the app's size adjustment while retaining the platform scaling curve.
class AppTextScaler extends TextScaler {
  const AppTextScaler(this.platformScaler, this.factor)
    : assert(factor > 0 && factor < double.infinity);

  final TextScaler platformScaler;
  final double factor;

  @override
  double scale(double fontSize) => platformScaler.scale(fontSize * factor);

  @override
  double get textScaleFactor => platformScaler.scale(16 * factor) / 16;

  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.platformScaler == platformScaler &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(platformScaler, factor);
}
