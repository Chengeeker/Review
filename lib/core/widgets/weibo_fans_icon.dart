import 'package:flutter/material.dart';

import '../constants/api_constants.dart';
import 'cached_network_image.dart';

/// Displays the iron-fan tier artwork returned by Weibo for a comment user.
///
/// The server-provided image contains the current tier-specific color/artwork;
/// this widget intentionally does not recreate or recolor the badge locally.
class WeiboFansIcon extends StatelessWidget {
  const WeiboFansIcon({
    super.key,
    required this.url,
    this.height = 14,
  });

  final String url;
  final double height;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = url.trim();
    final normalizedUrl =
        trimmedUrl.startsWith('//') ? 'https:$trimmedUrl' : trimmedUrl;
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return const SizedBox.shrink();
    }

    return Semantics(
      image: true,
      label: '微博铁粉等级标识',
      child: Tooltip(
        message: '微博铁粉等级标识',
        child: CachedNetworkImage(
          normalizedUrl,
          headers: ApiConstants.imageHeaders,
          height: height,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
