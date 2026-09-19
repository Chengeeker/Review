import 'package:flutter/material.dart';

/// Shared surface for grouped settings and utility actions.
/// The card theme remains the single source of truth for shape and colors.
class AppSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;

  const AppSectionCard({
    super.key,
    required this.child,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: child,
    );
  }
}
