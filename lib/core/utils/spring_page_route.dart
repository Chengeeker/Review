import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Physics-based Damped Spring Curve
class SpringCurve extends Curve {
  final double damping;
  final double stiffness;

  const SpringCurve({this.damping = 12.0, this.stiffness = 160.0});

  @override
  double transformInternal(double t) {
    if (t == 0.0 || t == 1.0) return t;
    final omega = math.sqrt(stiffness);
    final decay = math.exp(-damping * t);
    return 1.0 - decay * math.cos(omega * t);
  }
}

/// Two-stage Return Motion Curve:
/// Designed specifically for image gallery dismiss transition:
/// 1. First stage (t from 1.0 down to ~0.35): Rapidly & linearly shrinks dimensions and aspect ratio towards the preview thumbnail.
/// 2. Second stage (t from ~0.35 down to 0.0): Smooth cubic deceleration (ease-out) into the thumbnail card position without exaggerated spring bounce.
class TwoStageReturnCurve extends Curve {
  const TwoStageReturnCurve();

  @override
  double transformInternal(double t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;

    if (t >= 0.35) {
      final progress = (t - 0.35) / 0.65;
      return 0.20 + 0.80 * progress;
    } else {
      final progress = t / 0.35;
      return 0.20 * math.pow(progress, 1.6);
    }
  }
}

/// Material 3 Physics-based Spring Page Route Transition
class PhysicsSpringPageRoute<T> extends PageRouteBuilder<T> {
  final Widget child;

  PhysicsSpringPageRoute({
    required this.child,
    super.settings,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Spring scale curve
            final springCurvedAnimation = CurvedAnimation(
              parent: animation,
              curve: const SpringCurve(damping: 14.0, stiffness: 180.0),
              reverseCurve: Curves.easeInCubic,
            );

            // Smooth fade curve
            final fadeAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeIn,
            );

            // Scale from 0.92 to 1.0
            final scaleTween = Tween<double>(begin: 0.92, end: 1.0).animate(springCurvedAnimation);

            // Subtle vertical slide from 4% down to 0
            final slideTween = Tween<Offset>(
              begin: const Offset(0.0, 0.04),
              end: Offset.zero,
            ).animate(springCurvedAnimation);

            return FadeTransition(
              opacity: fadeAnimation,
              child: SlideTransition(
                position: slideTween,
                child: ScaleTransition(
                  scale: scaleTween,
                  child: child,
                ),
              ),
            );
          },
        );
}

/// Standard clean fade route for Image Gallery
class PhysicsSpringGalleryRoute<T> extends PageRouteBuilder<T> {
  final Widget child;

  PhysicsSpringGalleryRoute({
    required this.child,
    super.settings,
  }) : super(
          opaque: false,
          barrierColor: Colors.black,
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
        );
}
