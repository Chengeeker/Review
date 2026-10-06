import 'package:flutter/material.dart';

typedef ReviewPageBodyBuilder = Widget Function(
  BuildContext context,
  EdgeInsets contentInsets,
);

/// Shared page shell for settings and other simple secondary pages.
class ReviewPageScaffold extends StatelessWidget {
  const ReviewPageScaffold({
    super.key,
    required this.title,
    required this.bodyBuilder,
    this.showNavigationIcon = true,
  });

  final String title;
  final ReviewPageBodyBuilder bodyBuilder;
  final bool showNavigationIcon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: showNavigationIcon,
        title: Text(title),
      ),
      body: bodyBuilder(context, EdgeInsets.zero),
    );
  }
}
