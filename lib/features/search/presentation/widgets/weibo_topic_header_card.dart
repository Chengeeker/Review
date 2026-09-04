import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/app_toast.dart';
import '../../../../core/utils/haptic_feedback_util.dart';
import '../../../detail/presentation/widgets/image_gallery_page.dart';
import '../../../feed/data/models/weibo_status_model.dart';
import '../../../profile/presentation/user_profile_page.dart';
import '../../data/models/weibo_topic_header_model.dart';

/// 微博话题词条介绍卡片 (展示于搜索栏与分类顶栏之间)
class WeiboTopicHeaderCard extends StatelessWidget {
  final WeiboTopicHeaderModel topic;

  const WeiboTopicHeaderCard({
    super.key,
    required this.topic,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final topicTitle = topic.topicOri.startsWith('#') && topic.topicOri.endsWith('#')
        ? topic.topicOri
        : '#${topic.topicOri}#';

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E1F24)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.2 : 0.4),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. 顶部主体行：词条封面 + 词条标题 + 数据指标 + 分享操作
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面图
              if (topic.imageUrl.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        opaque: false,
                        pageBuilder: (_, __, ___) => ImageGalleryPage(
                          pics: [
                            WeiboPicModel(
                              pid: 'topic_cover',
                              thumbnail: topic.imageUrl,
                              large: topic.imageUrl,
                              original: topic.imageUrl,
                            ),
                          ],
                          initialIndex: 0,
                          statusId: 'topic_${topic.topicOri}',
                          authorName: topic.topicOri,
                        ),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 68,
                      height: 68,
                      color: colorScheme.surfaceContainerHighest,
                      child: ExtendedImage.network(
                        topic.imageUrl,
                        headers: ApiConstants.imageHeaders,
                        fit: BoxFit.cover,
                        loadStateChanged: (state) {
                          if (state.extendedImageLoadState == LoadState.failed) {
                            if (topic.hostAvatar != null && topic.hostAvatar!.isNotEmpty) {
                              return ExtendedImage.network(
                                topic.hostAvatar!,
                                headers: ApiConstants.imageHeaders,
                                fit: BoxFit.cover,
                              );
                            }
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    colorScheme.primaryContainer,
                                    colorScheme.secondaryContainer,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  topic.topicOri.isNotEmpty ? topic.topicOri.substring(0, 1) : '#',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            );
                          }
                          return null;
                        },
                      ),
                    ),
                  ),
                )
              else if (topic.hostAvatar != null && topic.hostAvatar!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 68,
                    height: 68,
                    color: colorScheme.surfaceContainerHighest,
                    child: ExtendedImage.network(
                      topic.hostAvatar!,
                      headers: ApiConstants.imageHeaders,
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              else
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primaryContainer,
                        colorScheme.secondaryContainer,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      topic.topicOri.isNotEmpty ? topic.topicOri.substring(0, 1) : '#',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 12),

              // 标题、指标与快捷操作
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            topicTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 分享按钮
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            HapticFeedbackUtil.light();
                            final url = topic.shareUrl ??
                                'https://s.weibo.com/weibo?q=${Uri.encodeComponent(topicTitle)}';
                            Clipboard.setData(ClipboardData(text: url));
                            AppToast.show(context, '已复制话题链接到剪贴板');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.share_rounded, size: 12.5, color: colorScheme.primary),
                                const SizedBox(width: 3),
                                Text(
                                  '分享',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),

                    // 阅读量与讨论量
                    Row(
                      children: [
                        Text(
                          '阅读量 ${topic.formattedReadCount}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '讨论量 ${topic.formattedMentionCount}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),

                    // 话题主持人
                    if (topic.hostName != null && topic.hostName!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (topic.hostUid != null && topic.hostUid!.isNotEmpty) {
                            HapticFeedbackUtil.light();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => UserProfilePage(
                                  uid: topic.hostUid!,
                                  screenName: topic.hostName!,
                                ),
                              ),
                            );
                          }
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_user_rounded,
                              size: 13,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '主持人: ${topic.hostName!}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 13,
                              color: colorScheme.primary.withValues(alpha: 0.7),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // 2. 导语简介行
          if (topic.summary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest.withValues(alpha: isDark ? 0.4 : 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '导语：',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    TextSpan(
                      text: topic.summary,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
