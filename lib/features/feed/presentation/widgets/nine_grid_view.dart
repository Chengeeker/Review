import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/theme/weibo_style_provider.dart';
import '../../../../core/utils/haptic_feedback_util.dart';
import '../../../../core/utils/spring_page_route.dart';
import '../../../detail/presentation/widgets/image_gallery_page.dart';
import '../../data/models/weibo_status_model.dart';
import 'weibo_video_player_page.dart';

/// Material You Adaptive Nine-Grid Image View
/// Supports 1, 2, 4, 3, 6, 9 image layouts, GIF/Long-photo badges, and full-screen hero viewer ("一镜到底").
class NineGridView extends ConsumerWidget {
  final List<WeiboPicModel> pics;
  final String statusId;
  final bool isDetail;
  final String? authorName;

  const NineGridView({
    super.key,
    required this.pics,
    required this.statusId,
    this.isDetail = false,
    this.authorName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (pics.isEmpty) return const SizedBox.shrink();

    final style = ref.watch(weiboStyleProvider);
    final count = pics.length;

    if (count == 1) {
      return _buildSingleImage(context, pics[0], style);
    }

    if (count == 2 || count == 4) {
      return _buildGrid(context, crossAxisCount: 2, style: style);
    }

    return _buildGrid(context, crossAxisCount: 3, style: style);
  }

  Widget _buildSingleImage(BuildContext context, WeiboPicModel pic, WeiboStyleSettings style) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    double maxWidth = style.largeImageMode ? 260.0 : 190.0;
    double maxHeight = style.largeImageMode ? 260.0 : 190.0;

    double aspectRatio = 1.0;
    if (pic.width > 0 && pic.height > 0) {
      aspectRatio = pic.width / pic.height;
      if (aspectRatio > 2.0) aspectRatio = 2.0;
      if (aspectRatio < 0.5) aspectRatio = 0.5;
    }

    final radius = BorderRadius.circular(style.roundedImageCorners ? 16 : 0);

    return GestureDetector(
      onTap: () => _openMedia(context, 0),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: radius,
                child: ExtendedImage.network(
                  pic.previewUrl,
                  headers: ApiConstants.imageHeaders,
                  fit: BoxFit.cover,
                  cache: true,
                  loadStateChanged: (state) {
                    if (state.extendedImageLoadState == LoadState.loading) {
                      return Container(color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4));
                    }
                    return null;
                  },
                ),
              ),
              if (pic.isVideo) ...[
                Center(
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: _buildBadge(pic.videoDuration?.isNotEmpty == true ? pic.videoDuration! : '视频'),
                ),
              ] else if (pic.isLivePhoto)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: _buildLiveBadge(),
                )
              else if (pic.isGif || pic.isLong)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: _buildBadge(pic.isGif ? 'GIF' : '长图'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, {required int crossAxisCount, required WeiboStyleSettings style}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = style.largeImageMode ? 7.0 : 5.0;
    final radius = BorderRadius.circular(style.roundedImageCorners ? 12 : 0);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: 1.0,
      ),
      itemCount: pics.length,
      itemBuilder: (context, index) {
        final pic = pics[index];
        return GestureDetector(
          onTap: () => _openMedia(context, index),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: radius,
                child: ExtendedImage.network(
                  pic.previewUrl,
                  headers: ApiConstants.imageHeaders,
                  fit: BoxFit.cover,
                  cache: true,
                  loadStateChanged: (state) {
                    if (state.extendedImageLoadState == LoadState.loading) {
                      return Container(color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4));
                    }
                    return null;
                  },
                ),
              ),
              if (pic.isVideo) ...[
                Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: _buildBadge(pic.videoDuration?.isNotEmpty == true ? pic.videoDuration! : '视频'),
                ),
              ] else if (pic.isLivePhoto)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: _buildLiveBadge(),
                )
              else if (pic.isGif || pic.isLong)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: _buildBadge(pic.isGif ? 'GIF' : '长图'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.motion_photos_on_rounded, size: 11, color: Colors.white),
          SizedBox(width: 2.5),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _openMedia(BuildContext context, int index) {
    final pic = pics[index];
    if (pic.isVideo && pic.videoUrl != null && pic.videoUrl!.isNotEmpty) {
      HapticFeedbackUtil.light();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WeiboVideoPlayerPage(
            videoUrl: pic.videoUrl!,
            statusId: statusId,
            coverUrl: pic.previewUrl,
            title: pic.videoTitle,
            authorName: authorName,
          ),
        ),
      );
    } else {
      _openGallery(context, index);
    }
  }

  void _openGallery(BuildContext context, int initialIndex) {
    HapticFeedbackUtil.light();
    Navigator.of(context).push(
      PhysicsSpringGalleryRoute(
        child: ImageGalleryPage(
          pics: pics,
          initialIndex: initialIndex,
          statusId: statusId,
          isDetail: isDetail,
          authorName: authorName,
        ),
      ),
    );
  }
}
