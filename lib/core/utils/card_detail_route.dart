import 'package:flutter/material.dart';

/// Expands a detail surface from the tapped card without rasterizing the feed.
PageRoute<T> cardDetailRoute<T>(BuildContext source, Widget page) {
  final navigatorBox = Navigator.of(source).context.findRenderObject();
  final box = source.findRenderObject();
  if (box is! RenderBox ||
      !box.hasSize ||
      navigatorBox is! RenderBox ||
      box.size.isEmpty ||
      MediaQuery.disableAnimationsOf(source) ||
      Theme.of(source).platform == TargetPlatform.iOS) {
    return MaterialPageRoute<T>(builder: (_) => page);
  }
  final origin = box.localToGlobal(Offset.zero, ancestor: navigatorBox);
  final start = origin & box.size;
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return AnimatedBuilder(
            animation: animation,
            child: child,
            builder: (context, child) {
              final t = Curves.easeInOutCubic.transform(animation.value);
              final rect = Rect.lerp(start, Offset.zero & size, t)!;
              return Stack(
                children: [
                  Positioned.fromRect(
                    rect: rect,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22 * (1 - t)),
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: size.width,
                        maxWidth: size.width,
                        minHeight: size.height,
                        maxHeight: size.height,
                        child: Transform.scale(
                          alignment: Alignment.topLeft,
                          scale: rect.width / size.width,
                          child: child,
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
}
