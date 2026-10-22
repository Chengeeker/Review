import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

final _openingCards = Expando<bool>();

/// Keeps the tapped card visible until the stationary detail page takes over.
Future<void> openCardDetail(BuildContext source, Widget page) async {
  if (_openingCards[source] == true) return;
  _openingCards[source] = true;
  ui.Image? preview;
  try {
    final navigator = Navigator.of(source);
    final reduceMotion = MediaQuery.disableAnimationsOf(source);
    final standardRoute = Theme.of(source).platform == TargetPlatform.iOS;
    Rect? start;
    if (!reduceMotion && !standardRoute) {
      // Ink feedback may dirty the source during the tap callback.
      await WidgetsBinding.instance.endOfFrame;
      if (!source.mounted || !navigator.mounted) return;
      final box = source.findRenderObject();
      final navigatorBox = navigator.context.findRenderObject();
      if (box is RenderRepaintBoundary &&
          box.hasSize &&
          !box.size.isEmpty &&
          navigatorBox is RenderBox) {
        start =
            box.localToGlobal(Offset.zero, ancestor: navigatorBox) & box.size;
        final ratio = math.min(
          1.5,
          math.min(
            math.sqrt(2000000 / (box.size.width * box.size.height)),
            4096 / math.max(box.size.width, box.size.height),
          ),
        );
        try {
          preview = await box.toImage(pixelRatio: ratio);
        } catch (_) {
          // A source removed before rasterization uses the normal route.
        }
      }
    }
    if (!source.mounted || !navigator.mounted) return;
    if (preview == null || start == null) {
      await navigator.push(MaterialPageRoute<void>(builder: (_) => page));
      return;
    }
    final image = preview;
    final origin = start;
    final surface = Theme.of(source).colorScheme.surface;
    final bodyInset = MediaQuery.paddingOf(source).top + kToolbarHeight;
    final route = PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (context, child) {
                final t = Curves.easeInOutCubic.transform(animation.value);
                final rect = Rect.lerp(
                  origin,
                  Offset.zero & constraints.biggest,
                  t,
                )!;
                final radius = 22 * (1 - t);
                final mix = ((t - 0.2) / 0.65).clamp(0.0, 1.0);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fromRect(
                      rect: rect,
                      child: Opacity(
                        opacity: t,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(radius),
                          ),
                        ),
                      ),
                    ),
                    ClipPath(
                      clipper: _CardClipper(rect, radius),
                      child: Opacity(opacity: mix, child: child),
                    ),
                    Positioned.fromRect(
                      rect: rect,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 1 - mix,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(radius),
                            child: Stack(
                              children: [
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: bodyInset * t,
                                  child: AspectRatio(
                                    aspectRatio: image.width / image.height,
                                    child: RawImage(
                                      image: image,
                                      fit: BoxFit.fill,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
    navigator.push(route);
    // Navigator.push resolves before the reverse animation has finished.
    await route.completed;
  } finally {
    preview?.dispose();
    _openingCards[source] = false;
  }
}

class _CardClipper extends CustomClipper<Path> {
  const _CardClipper(this.rect, this.radius);
  final Rect rect;
  final double radius;
  @override
  Path getClip(Size size) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
  @override
  bool shouldReclip(_CardClipper oldClipper) =>
      rect != oldClipper.rect || radius != oldClipper.radius;
}
