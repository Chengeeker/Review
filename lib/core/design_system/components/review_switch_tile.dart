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
    return SwitchListTile(
      contentPadding: contentPadding,
      secondary: leading,
      title: Text(title),
      subtitle: summary == null ? null : Text(summary!),
      value: value,
      onChanged: onChanged,
    );
  }
}
