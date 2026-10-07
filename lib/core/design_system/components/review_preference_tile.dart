import 'package:flutter/material.dart';

/// A shared navigation row rendered in the active design language.
class ReviewPreferenceTile extends StatelessWidget {
  const ReviewPreferenceTile({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.trailing,
    this.titleStyle,
    this.subtitleStyle,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final titleTextStyle = theme.textTheme.titleMedium?.merge(titleStyle);
    final subtitleTextStyle = theme.textTheme.bodyMedium
        ?.copyWith(color: colorScheme.onSurfaceVariant)
        .merge(subtitleStyle);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minLeadingWidth: 24,
      horizontalTitleGap: 16,
      minVerticalPadding: 8,
      leading: leading,
      title: Text(title, style: titleTextStyle),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: subtitleTextStyle),
      trailing:
          trailing ??
          Icon(
            Icons.chevron_right_rounded,
            size: 24,
            color: colorScheme.onSurfaceVariant,
          ),
      onTap: onTap,
    );
  }
}
