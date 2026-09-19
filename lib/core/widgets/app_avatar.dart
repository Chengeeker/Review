import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import '../constants/api_constants.dart';
import '../utils/haptic_feedback_util.dart';

/// Material You Avatar Widget with Graceful Error Fallback and Verified Badges
class AppAvatar extends StatelessWidget {
  final String? url;
  final double size;
  final String name;
  final bool verified;
  final int verifiedType;
  final VoidCallback? onTap;

  const AppAvatar({
    super.key,
    required this.url,
    this.size = 42,
    this.name = '',
    this.verified = false,
    this.verifiedType = -1,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final hasValidUrl =
        url != null && url!.isNotEmpty && url!.startsWith('http');

    Widget avatarImage;
    if (hasValidUrl) {
      avatarImage = ExtendedImage.network(
        url!,
        headers: ApiConstants.imageHeaders,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cache: true,
        loadStateChanged: (state) {
          if (state.extendedImageLoadState == LoadState.failed ||
              state.extendedImageLoadState == LoadState.loading) {
            return _buildFallback(colorScheme);
          }
          return null;
        },
      );
    } else {
      avatarImage = _buildFallback(colorScheme);
    }

    Widget content = Stack(
      clipBehavior: Clip.none,
      children: [
        ClipOval(child: avatarImage),
        if (verified)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.35,
              height: size * 0.35,
              decoration: BoxDecoration(
                color: verifiedType == 0 ? Colors.amber : Colors.blueAccent,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.surface, width: 1.5),
              ),
              child: Center(
                child: Text(
                  'v',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.22,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (onTap != null) {
      final label = name.trim().isEmpty ? '头像' : '$name的头像';
      return Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Center(
              child: InkWell(
                onTap: () {
                  // InkWell's global splash already records the pointer-down
                  // feedback; the utility consumes that event so this remains
                  // a single vibration instead of a second business callback.
                  HapticFeedbackUtil.light();
                  onTap!();
                },
                customBorder: const CircleBorder(),
                child: content,
              ),
            ),
          ),
        ),
      );
    }

    return content;
  }

  Widget _buildFallback(ColorScheme colorScheme) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: name.trim().isNotEmpty
            ? Text(
                String.fromCharCodes(name.trim().runes.take(1)).toUpperCase(),
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  fontSize: size * 0.45,
                ),
              )
            : Icon(
                Icons.person_rounded,
                size: size * 0.55,
                color: colorScheme.onPrimaryContainer,
              ),
      ),
    );
  }
}
