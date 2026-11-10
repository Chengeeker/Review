import 'package:flutter/material.dart';

/// Flush surface for grouped settings and utility actions.
class AppSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;

  const AppSectionCard({super.key, required this.child, this.margin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pageColor = theme.scaffoldBackgroundColor;
    final page = pageColor.computeLuminance() + .05;
    final card = scheme.surfaceContainerHigh.computeLuminance() + .05;
    final separated = card >= page * 1.12 || page >= card * 1.12;
    final color = separated
        ? scheme.surfaceContainerHigh
        : Color.alphaBlend(scheme.onSurface.withValues(alpha: .10), pageColor);
    return Card(
      margin: margin ?? EdgeInsets.zero,
      color: color,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide.none,
      ),
      child: child,
    );
  }
}
