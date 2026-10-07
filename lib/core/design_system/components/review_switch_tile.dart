import 'package:flutter/material.dart';

/// A switch row that follows the selected Review design language.
class ReviewSwitchTile extends StatelessWidget {
  const ReviewSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.summary,
    this.leading,
    this.contentPadding,
  });

  final String title;
  final String? summary;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? leading;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SwitchListTile(
      contentPadding: contentPadding,
      secondary: leading,
      title: Text(
        title,
        style: theme.listTileTheme.titleTextStyle?.copyWith(
          fontSize: 16,
          color: colorScheme.onSurface,
        ),
      ),
      subtitle: summary == null
          ? null
          : Text(
              summary!,
              style: theme.listTileTheme.subtitleTextStyle?.copyWith(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}
