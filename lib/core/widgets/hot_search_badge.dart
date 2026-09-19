import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared badge used by both the search page and the full hot-trends page.
/// Keeping the geometry in one place prevents the same Weibo label from
/// drifting between screens.
class HotSearchBadge extends StatelessWidget {
  final String label;
  final bool compact;

  const HotSearchBadge({
    super.key,
    required this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (label) {
      '热' || '爆' => (const Color(0xFFFF2442), Colors.white),
      '新' => (const Color(0xFF00B0FF), Colors.white),
      '沸' => (const Color(0xFFFF6D00), Colors.white),
      _ => (scheme.primaryContainer, scheme.onPrimaryContainer),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 5,
        vertical: compact ? 1 : 1.5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(compact ? 3 : 4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: compact ? 9 : 10,
          fontWeight: context.adjustWeight(FontWeight.bold),
          height: 1.1,
        ),
      ),
    );
  }
}
