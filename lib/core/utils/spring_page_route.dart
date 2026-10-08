import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Two-stage return curve used by image gallery hero dismissal.
class TwoStageReturnCurve extends Curve {
  const TwoStageReturnCurve();

  @override
  double transformInternal(double t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    if (t >= 0.35) {
      return 0.20 + 0.80 * ((t - 0.35) / 0.65);
    }
    return 0.20 * math.pow(t / 0.35, 1.6);
  }
}

/// Standard clean fade route for Image Gallery
class PhysicsSpringGalleryRoute<T> extends PageRouteBuilder<T> {
  final Widget child;

  PhysicsSpringGalleryRoute({required this.child, super.settings})
    : super(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) => child,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      );
}
