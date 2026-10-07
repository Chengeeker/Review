import 'package:flutter/material.dart';

/// Low-emphasis, flush surface for grouped settings and utility actions.
class AppSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;

  const AppSectionCard({super.key, required this.child, this.margin});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.surface == Colors.black
        ? scheme.surfaceContainer
        : scheme.surfaceContainerLow;
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
