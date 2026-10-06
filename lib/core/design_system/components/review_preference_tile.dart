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
    return ListTile(
      leading: leading,
      title: Text(title, style: titleStyle),
      subtitle: subtitle == null ? null : Text(subtitle!, style: subtitleStyle),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
