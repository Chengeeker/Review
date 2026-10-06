import 'package:flutter/material.dart';

/// A shared card surface that follows the selected Review design language.
class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.child,
    this.margin,
    this.color,
    this.shape,
    this.elevation = 1,
    this.clipBehavior = Clip.none,
    this.onTap,
    this.onLongPress,
    this.enableFeedback = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final ShapeBorder? shape;
  final double elevation;
  final Clip clipBehavior;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enableFeedback;

  @override
  Widget build(BuildContext context) {
    final roundedShape = shape is RoundedRectangleBorder
        ? shape as RoundedRectangleBorder
        : null;
    return Card(
      margin: margin,
      color: color,
      shape: shape,
      elevation: elevation,
      clipBehavior: clipBehavior,
      child: onTap != null || onLongPress != null
          ? InkWell(
              borderRadius: roundedShape?.borderRadius.resolve(
                Directionality.of(context),
              ),
              enableFeedback: enableFeedback,
              onTap: onTap,
              onLongPress: onLongPress,
              child: child,
            )
          : child,
    );
  }
}
