import 'package:flutter/material.dart';

import '../../utils/haptic_feedback_util.dart';

/// One choice row rendered in the active Review design language.
class ReviewChoiceTile<T> extends StatelessWidget {
  const ReviewChoiceTile({
    super.key,
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onSelected,
    this.summary,
  });

  final String title;
  final String? summary;
  final T value;
  final T groupValue;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return RadioGroup<T>(
      groupValue: groupValue,
      onChanged: (selectedValue) {
        if (selectedValue == null || selectedValue == groupValue) return;
        HapticFeedbackUtil.light();
        onSelected();
      },
      child: RadioListTile<T>(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
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
      ),
    );
  }
}
