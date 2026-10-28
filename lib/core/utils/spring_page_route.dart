import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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

/// Shared image-gallery route, including the Hero flight's animation timing.
class PhysicsSpringGalleryRoute<T> extends PageRouteBuilder<T> {
  static final Set<Object> _activeRoutes = <Object>{};
  static final Set<int> _transitionPointers = <int>{};
  static final Set<int> _recentTransitionPointers = <int>{};
  static final List<VoidCallback> _idleCallbacks = <VoidCallback>[];
  static bool _listeningForTransitionPointers = false;
  static bool get hasActiveRoutes => _activeRoutes.isNotEmpty;

  static Future<R?> openFromSource<R>(
    BuildContext context,
    PhysicsSpringGalleryRoute<R> route,
  ) {
    final navigator = Navigator.of(context);
    if (_activeRoutes.whereType<PhysicsSpringGalleryRoute>().any(
      (active) => active.navigator == navigator,
    )) {
      return Future<R?>.value(null);
    }
    return navigator.push<R>(route);
  }

  static void whenAllRoutesIdle(VoidCallback callback) {
    if (_activeRoutes.isEmpty) {
      callback();
    } else {
      _idleCallbacks.add(callback);
    }
  }

  static void _notifyRoutesIdle() {
    if (_activeRoutes.isNotEmpty || _idleCallbacks.isEmpty) return;
    final callbacks = List<VoidCallback>.of(_idleCallbacks);
    _idleCallbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  static void _updateTransitionPointerRoute() {
    final shouldListen =
        _activeRoutes.isNotEmpty ||
        _transitionPointers.isNotEmpty ||
        _recentTransitionPointers.isNotEmpty;
    if (shouldListen == _listeningForTransitionPointers) return;
    final pointerRouter = GestureBinding.instance.pointerRouter;
    if (shouldListen) {
      pointerRouter.addGlobalRoute(_handleTransitionPointer);
    } else {
      pointerRouter.removeGlobalRoute(_handleTransitionPointer);
    }
    _listeningForTransitionPointers = shouldListen;
  }

  static void _handleTransitionPointer(PointerEvent event) {
    if (event is PointerDownEvent && _activeRoutes.isNotEmpty) {
      _transitionPointers.add(event.pointer);
    } else if (event is PointerUpEvent &&
        _transitionPointers.remove(event.pointer)) {
      _recentTransitionPointers.add(event.pointer);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _recentTransitionPointers.remove(event.pointer);
        _updateTransitionPointerRoute();
      });
      WidgetsBinding.instance.scheduleFrame();
    } else if (event is PointerCancelEvent) {
      _transitionPointers.remove(event.pointer);
    }
    _updateTransitionPointerRoute();
  }

  final Widget child;
  PhysicsSpringGalleryRoute({required this.child, super.settings})
    : super(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 330),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) => child,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      );

  @override
  void install() {
    super.install();
    _activeRoutes.add(this);

    _updateTransitionPointerRoute();
  }

  @override
  void dispose() {
    // Keep feed taps guarded until Navigator removes the Hero overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeRoutes.remove(this);
      _updateTransitionPointerRoute();
      _notifyRoutesIdle();
    });
    WidgetsBinding.instance.scheduleFrame();
    super.dispose();
  }
}

bool isCoveredRouteTransitioning(BuildContext context) =>
    PhysicsSpringGalleryRoute._activeRoutes.isNotEmpty ||
    PhysicsSpringGalleryRoute._transitionPointers.isNotEmpty ||
    PhysicsSpringGalleryRoute._recentTransitionPointers.isNotEmpty ||
    (ModalRoute.of(context)?.secondaryAnimation?.isAnimating ?? false);
