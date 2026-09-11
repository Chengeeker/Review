import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/card_display_provider.dart';
import '../../../../core/theme/weibo_style_provider.dart';
import '../../../../core/utils/app_dialog.dart';
import '../../../../core/utils/app_toast.dart';
import '../../../../core/utils/haptic_feedback_util.dart';
import '../../../../core/utils/weibo_text_parser.dart';
import '../../../../core/utils/weibo_time_formatter.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../compose/presentation/compose_tweet_page.dart';
import '../../../detail/presentation/status_detail_page.dart';
import '../../../profile/presentation/user_profile_page.dart';
import '../../data/feed_repository.dart';
import '../../data/models/weibo_engagement_models.dart';
import '../../data/models/weibo_status_model.dart';
import '../feed_controller.dart';
import 'nine_grid_view.dart';
import '../../../detail/data/detail_repository.dart';
import '../../../detail/presentation/widgets/edit_history_bottom_sheet.dart';
import '../../../drawer_features/presentation/chaohua_detail_page.dart';
import '../../../search/presentation/search_results_page.dart';
import 'weibo_video_player_page.dart';

String _trimTimelineTrailingWhitespace(String value) {
  return value.replaceFirst(
    RegExp(r'[\s\u200B\u200C\u200D\u2060\uFEFF]+$'),
    '',
  );
}

String _removeEmbeddedPollLink(String value, WeiboStatusModel status) {
  if (status.poll == null) return value;
  // Weibo puts the vote short URL at the end of the status text. Once the
  // native poll card is available, showing that same URL as a blue smart-link
  // duplicates the card and differs from the official web layout.
  return value
      .replaceFirst(
        RegExp(
          r'[\s\u200B\u200C\u200D\u2060\uFEFF]*(?:https?://)?t\.cn/[A-Za-z0-9]+[\s\u200B\u200C\u200D\u2060\uFEFF]*$',
        ),
        '',
      )
      .trimRight();
}

/// Material You (MD3) Weibo Status Card (支持时间智能格式化、全域微博样式个性化响应与长文本智能展开)
class TweetCard extends ConsumerStatefulWidget {
  final WeiboStatusModel status;
  final bool isDetail;

  const TweetCard({
    super.key,
    required this.status,
    this.isDetail = false,
  });

  void showMoreOptions(
    BuildContext context,
    WidgetRef ref, {
    bool? favoritedOverride,
    ValueChanged<bool>? onFavoriteChanged,
  }) {
    HapticFeedbackUtil.light();
    final colorScheme = Theme.of(context).colorScheme;
    final auth = ref.read(authProvider);

    final isMyTweet = auth.isLoggedIn &&
        ((auth.uid != null &&
                auth.uid!.isNotEmpty &&
                (auth.uid == status.user.id || auth.uid == status.id)) ||
            (auth.nickname != null &&
                auth.nickname!.isNotEmpty &&
                auth.nickname == status.user.screenName));

    final isFavorited = favoritedOverride ?? status.favorited;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // If it's user's own tweet, show Delete & Edit options prominently
            if (isMyTweet) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑微博'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ComposeTweetPage(
                        initialText: status.effectiveText,
                        editMid: status.id,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded,
                    color: colorScheme.error),
                title: Text('删除微博', style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context, ref);
                },
              ),
              const Divider(),
            ],
            // Edit History Option
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('查看编辑记录'),
              subtitle: status.editCount > 0
                  ? Text('已编辑 ${status.editCount} 次')
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                EditHistoryBottomSheet.show(
                  context,
                  statusId: status.id,
                  mid: status.mid.isNotEmpty ? status.mid : status.id,
                  authorName: status.user.screenName,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制微博正文'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: status.effectiveText));
                Navigator.pop(ctx);
                AppToast.show(context, '已复制微博文本至剪贴板');
              },
            ),
            ListTile(
              leading: Icon(
                  isFavorited ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isFavorited ? const Color(0xFFFF8200) : null),
              title: Text(isFavorited ? '取消收藏' : '收藏微博'),
              onTap: () async {
                Navigator.pop(ctx);
                final wasFavorited = isFavorited;
                final success = await ref
                    .read(feedRepositoryProvider)
                    .toggleFavorite(status.id,
                        currentlyFavorited: wasFavorited);
                if (context.mounted) {
                  if (success) {
                    onFavoriteChanged?.call(!wasFavorited);
                    ref
                        .read(feedControllerProvider.notifier)
                        .syncFavoriteLocally(status.id, !wasFavorited);
                  }
                  AppToast.show(context,
                      success ? (wasFavorited ? '已取消收藏' : '已收藏') : '操作失败，请重试');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('复制微博链接'),
              onTap: () {
                final link = 'https://weibo.com/${status.user.id}/${status.id}';
                Clipboard.setData(ClipboardData(text: link));
                Navigator.pop(ctx);
                AppToast.show(context, '已复制微博网页链接');
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: Text('查看 @${status.user.screenName} 的主页'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (c) => UserProfilePage(
                      user: status.user,
                      uid: status.user.id,
                      screenName: status.user.screenName,
                    ),
                  ),
                );
              },
            ),
            if (!isMyTweet)
              ListTile(
                leading: Icon(Icons.block_outlined, color: colorScheme.error),
                title:
                    Text('屏蔽该博主', style: TextStyle(color: colorScheme.error)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref
                      .read(feedControllerProvider.notifier)
                      .blockUser(status.user.id);
                  if (context.mounted) {
                    AppToast.show(context, '已在本地屏蔽 @${status.user.screenName}');
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确定删除微博？'),
        content: const Text('删除后该条微博将不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ref
                  .read(feedControllerProvider.notifier)
                  .deleteStatus(status.id);
              if (context.mounted) {
                if (isDetail) {
                  Navigator.of(context).pop();
                }
                AppToast.show(context, success ? '🎉 微博已成功删除' : '删除失败，微博仍保留');
              }
            },
            child: const Text('确定删除'),
          ),
        ],
      ),
    );
  }

  @override
  ConsumerState<TweetCard> createState() => _TweetCardState();
}

class _TweetCardState extends ConsumerState<TweetCard> {
  bool _isExpanded = false;
  bool _isLoadingLongText = false;
  String? _loadedLongText;

  bool _isRetweetExpanded = false;
  bool _isLoadingRetweetLongText = false;
  String? _loadedRetweetLongText;

  bool? _liked;
  int? _attitudesCount;
  bool? _favorited;
  WeiboPollModel? _poll;
  bool _showAllPollOptions = false;
  bool _showPollResults = false;
  bool _isSubmittingPoll = false;
  bool _isLoadingPollResult = false;
  final Set<String> _selectedPollOptionIds = <String>{};

  bool get _effectiveLiked => _liked ?? widget.status.liked;
  int get _effectiveAttitudesCount =>
      _attitudesCount ?? widget.status.attitudesCount;
  bool get _effectiveFavorited => _favorited ?? widget.status.favorited;

  @override
  void initState() {
    super.initState();
    if (widget.isDetail && widget.status.needsLongText) {
      _fetchMainLongText();
    }
  }

  @override
  void didUpdateWidget(covariant TweetCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status.id != widget.status.id) {
      _liked = null;
      _attitudesCount = null;
      _favorited = null;
      _poll = null;
      _showAllPollOptions = false;
      _showPollResults = false;
      _isSubmittingPoll = false;
      _isLoadingPollResult = false;
      _selectedPollOptionIds.clear();
    } else if (oldWidget.status.poll?.id != widget.status.poll?.id) {
      _poll = null;
      _showAllPollOptions = false;
      _showPollResults = false;
      _selectedPollOptionIds.clear();
    }
    if (widget.isDetail &&
        widget.status.needsLongText &&
        _loadedLongText == null &&
        !_isLoadingLongText) {
      _fetchMainLongText();
    }
  }

  Future<void> _handleToggleLike() async {
    HapticFeedbackUtil.light();
    final wasLiked = _effectiveLiked;
    final currentCount = _effectiveAttitudesCount;
    final nextLiked = !wasLiked;
    final nextCount = nextLiked
        ? currentCount + 1
        : (currentCount > 0 ? currentCount - 1 : 0);

    setState(() {
      _liked = nextLiked;
      _attitudesCount = nextCount;
    });

    ref
        .read(feedControllerProvider.notifier)
        .syncLikeLocally(widget.status.id, nextLiked, nextCount);

    final repo = ref.read(feedRepositoryProvider);
    final success =
        await repo.toggleLike(widget.status.id, currentlyLiked: wasLiked);
    if (!success && mounted) {
      setState(() {
        _liked = wasLiked;
        _attitudesCount = currentCount;
      });
      ref
          .read(feedControllerProvider.notifier)
          .syncLikeLocally(widget.status.id, wasLiked, currentCount);
      AppToast.show(context, '操作失败，请检查网络或登录状态');
    }
  }

  void _showMoreOptions(BuildContext context) {
    widget.showMoreOptions(
      context,
      ref,
      favoritedOverride: _effectiveFavorited,
      onFavoriteChanged: (value) {
        if (mounted) setState(() => _favorited = value);
      },
    );
  }

  Future<void> _fetchMainLongText() async {
    if (_isLoadingLongText) return;
    setState(() => _isLoadingLongText = true);
    final repo = ref.read(detailRepositoryProvider);
    final longText =
        await repo.getLongText(widget.status.mblogid ?? widget.status.id);
    if (mounted) {
      setState(() {
        _isLoadingLongText = false;
        if (longText != null && longText.isNotEmpty) {
          _loadedLongText = longText;
          _isExpanded = true;
        }
      });
    }
  }

  Future<void> _toggleMainExpand() async {
    HapticFeedbackUtil.light();
    if (_isExpanded) {
      setState(() => _isExpanded = false);
      return;
    }

    if (_loadedLongText != null || widget.status.fullTextRaw != null) {
      setState(() => _isExpanded = true);
      return;
    }

    await _fetchMainLongText();
  }

  Future<void> _toggleRetweetExpand(WeiboStatusModel retweet) async {
    HapticFeedbackUtil.light();
    if (_isRetweetExpanded) {
      setState(() => _isRetweetExpanded = false);
      return;
    }

    if (_loadedRetweetLongText != null || retweet.fullTextRaw != null) {
      setState(() => _isRetweetExpanded = true);
      return;
    }

    setState(() => _isLoadingRetweetLongText = true);
    final repo = ref.read(detailRepositoryProvider);
    final longText = await repo.getLongText(retweet.mblogid ?? retweet.id);
    if (mounted) {
      setState(() {
        _isLoadingRetweetLongText = false;
        if (longText != null && longText.isNotEmpty) {
          _loadedRetweetLongText = longText;
          _isRetweetExpanded = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final poll = _poll ?? status.poll;
    final isDetail = widget.isDetail;
    final weiboStyle = ref.watch(weiboStyleProvider);
    final layout = weiboStyle.cardBackgroundLayout;
    final isRounded = layout == 'card_rounded' || layout == 'floating_rounded';
    final isFloating =
        layout == 'floating_rect' || layout == 'floating_rounded';
    final hasThinDivider = layout == 'normal_thin_divider';
    final isNormal = layout == 'normal';
    final linkColor = weiboStyle.linkColorFollowTheme
        ? Theme.of(context).colorScheme.primary
        : const Color(0xFF3366CC);

    final cardMargin = isDetail
        ? EdgeInsets.zero
        : (isFloating
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
            : (layout == 'card_rounded'
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                : EdgeInsets.zero));

    final cardElevation = isDetail
        ? 0.0
        : (isFloating ? 3.5 : (layout == 'card_rounded' ? 1.0 : 0.0));

    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(isRounded ? 22 : 0),
      side: (isNormal && !isDetail)
          ? BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
              width: 0.5)
          : BorderSide.none,
    );

    final cardWidget = Card(
      margin: cardMargin,
      elevation: cardElevation,
      shape: cardShape,
      child: InkWell(
        borderRadius: BorderRadius.circular(isRounded ? 22 : 0),
        enableFeedback: false,
        onTap: isDetail
            ? null
            : () {
                try {
                  final storage = ref.read(storageServiceProvider);
                  storage.recordViewedStatusJson(
                      status.id, jsonEncode(status.toJson()));
                } catch (_) {}
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => StatusDetailPage(status: status),
                  ),
                );
              },
        onLongPress: isDetail
            ? null
            : () {
                _showMoreOptions(context);
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 0. Top Pinned or Title Banner (置顶 / 热门 / 赞过)
              if (status.isTop || status.titleText == '置顶') ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              const Color(0xFF4CAF50).withValues(alpha: 0.35),
                          width: 0.6,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.push_pin_rounded,
                            size: 11,
                            color: Color(0xFF388E3C),
                          ),
                          SizedBox(width: 3),
                          Text(
                            '置顶',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ] else if (status.titleText == '热门' ||
                  status.titleText?.contains('热门') == true) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5722).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              const Color(0xFFFF5722).withValues(alpha: 0.35),
                          width: 0.6,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_fire_department_rounded,
                            size: 12,
                            color: Color(0xFFFF5722),
                          ),
                          SizedBox(width: 2.5),
                          Text(
                            '热门',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF5722),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ] else if (status.titleText != null &&
                  status.titleText!.isNotEmpty &&
                  status.visibilityLabel == null) ...[
                Row(
                  children: [
                    Icon(
                      status.titleText!.contains('赞')
                          ? Icons.favorite_rounded
                          : Icons.repeat_rounded,
                      size: 13,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      status.titleText!,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],

              // 1. Author Header Row (Clickable to UserProfilePage)
              // Keep the compose-page short labels ("粉丝"/"好友" etc.)
              // separate from the content label. On cards, restricted posts
              // need an explicit scope, and the timeline should show it too.
              if (isDetail ||
                  (status.visibilityType != null &&
                      status.visibilityType != 0 &&
                      status.visibilityLabel != null))
                _buildVisibilityBanner(context, status),
              _buildHeaderRow(context, status.user, weiboStyle),

              // 1.5 Super Topic (超话) Badge
              if (status.chaohuaTitle != null &&
                  status.chaohuaTitle!.isNotEmpty) ...[
                const SizedBox(height: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => ChaohuaDetailPage(
                          containerid: status.chaohuaContainerId ?? '',
                          title: status.chaohuaTitle!,
                          avatar: status.chaohuaAvatar,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8200).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFF8200).withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.diamond_rounded,
                            size: 13, color: Color(0xFFFF8200)),
                        const SizedBox(width: 4),
                        Text(
                          status.chaohuaTitle!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF8200),
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.chevron_right_rounded,
                            size: 14, color: Color(0xFFFF8200)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),

              // 2. Main Rich Text with Long Text Expand/Collapse Support
              _buildMainText(context, weiboStyle, linkColor),

              // 3. Media Grid (if original has pictures)
              if (status.pics.isNotEmpty) ...[
                const SizedBox(height: 10),
                NineGridView(
                  pics: status.pics,
                  statusId: status.id,
                  isDetail: isDetail,
                  authorName: status.user.screenName,
                ),
              ] else if (status.videoCoverUrl != null &&
                  status.videoCoverUrl!.isNotEmpty) ...[
                // 3.5 Native Video Preview Card
                const SizedBox(height: 10),
                _buildVideoPreviewCard(context, status),
              ],

              // 3.8 Official Weibo poll card
              if (poll != null) ...[
                const SizedBox(height: 10),
                _buildPollCard(context, poll),
              ],

              // 4. Retweeted Quote Card (if retweeted)
              if (status.retweetedStatus != null) ...[
                const SizedBox(height: 10),
                _buildRetweetCard(
                    context, status.retweetedStatus!, weiboStyle, linkColor),
              ],

              // 4.5 Official hot-search topic card embedded in the status
              if (status.hotTopic != null) ...[
                const SizedBox(height: 10),
                _buildHotTopicCard(
                  context,
                  status.hotTopic!,
                  weiboStyle.fontSize,
                ),
              ],

              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: 4),

              // 6. Bottom Action Bar (Repost, Comment, Like, More Options)
              _buildActionBar(
                  context, Theme.of(context).colorScheme, weiboStyle),
            ],
          ),
        ),
      ),
    );

    if (hasThinDivider && !isDetail) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          cardWidget,
          Container(
            height: 8,
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF101114)
                : Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.35),
          ),
        ],
      );
    }

    return cardWidget;
  }

  Widget _buildMainText(
      BuildContext context, WeiboStyleSettings weiboStyle, Color linkColor) {
    final status = widget.status;
    final isDetail = widget.isDetail;
    final isShowingFull = isDetail ||
        _isExpanded ||
        (status.fullTextRaw != null && status.fullTextRaw!.isNotEmpty);
    final rawTextToDisplay = (isShowingFull
        ? (_loadedLongText ?? status.effectiveText)
        : status.textRaw);
    // 时间线接口的 text_raw 偶尔会在正文后带换行，Text.rich 会把它布局成
    // 真实的空行，导致列表卡片正文与操作栏之间出现异常留白。详情页使用
    // 单独请求的正文，保持原样；这里只收紧列表卡片的显示文本。
    final visibleText = _removeEmbeddedPollLink(
      isDetail
          ? rawTextToDisplay
          : _trimTimelineTrailingWhitespace(rawTextToDisplay),
      status,
    );

    final mainTextWidget = Text.rich(
      TextSpan(
        children: WeiboTextParser.parse(
          rawText: visibleText,
          context: context,
          urlStruct: status.urlStruct,
          htmlText: status.textHtml,
          linkColor: linkColor,
          defaultStyle: TextStyle(
            fontSize: weiboStyle.fontSize,
            height: weiboStyle.fontLineHeight,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isDetail) SelectionArea(child: mainTextWidget) else mainTextWidget,
        if (status.isLongText && !isDetail) ...[
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: _toggleMainExpand,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLoadingLongText) ...[
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    _isExpanded ? '收起' : '展开全文',
                    style: TextStyle(
                      fontSize: weiboStyle.fontSize - 1.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
        if (isDetail && status.isLongText && _isLoadingLongText) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '正在加载全文...',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Detail responses fill the visibility metadata asynchronously. Keep a
  /// fixed-height slot so the author header and body do not jump when the
  /// official response arrives; only the slot's contents change.
  Widget _buildVisibilityBanner(
    BuildContext context,
    WeiboStatusModel status,
  ) {
    final label = status.visibilityLabel;
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 24,
      child: label == null
          ? const SizedBox.shrink()
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.public_outlined,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeaderRow(
    BuildContext context,
    WeiboUserModel user,
    WeiboStyleSettings weiboStyle,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final cardSettings = ref.watch(cardDisplayProvider);

    final formattedTime = WeiboTimeFormatter.format(
      rawDate: widget.status.createdAt,
      settings: cardSettings,
      language: 'zh',
    );

    final showIp = weiboStyle.showIpLocationMode == 'all' ||
        (weiboStyle.showIpLocationMode == 'detail_only' && widget.isDetail);

    return Row(
      children: [
        // Avatar with Verified Badge
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (ctx) => UserProfilePage(
                    user: user, uid: user.id, screenName: user.screenName),
              ),
            );
          },
          child: AppAvatar(
            url: user.avatar,
            size: 42,
            name: user.screenName,
            verified: user.verified,
            verifiedType: user.verifiedType,
          ),
        ),
        const SizedBox(width: 10),

        // Screen Name & Subtitle Info
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => UserProfilePage(
                      user: user, uid: user.id, screenName: user.screenName),
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.screenName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: context.adjustWeight(FontWeight.bold),
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (weiboStyle.showRemarkAndName &&
                        user.description.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(${user.description})',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (weiboStyle.showUserActivityIcon && user.verified) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified,
                          size: 14, color: colorScheme.primary),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      formattedTime,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (cardSettings.showSource &&
                        widget.status.source.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.status.source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    if (cardSettings.showRegion &&
                        showIp &&
                        widget.status.regionName != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        widget.status.regionName!,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (widget.status.editCount > 0) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          HapticFeedbackUtil.light();
                          EditHistoryBottomSheet.show(
                            context,
                            statusId: widget.status.id,
                            mid: widget.status.mid.isNotEmpty
                                ? widget.status.mid
                                : widget.status.id,
                            authorName: widget.status.user.screenName,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer
                                .withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '已编辑',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: context.adjustWeight(FontWeight.w600),
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),

        // If Menu is NOT at bottom, display it on header top right
        if (!weiboStyle.showMenuAtBottom)
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded, size: 20),
            onPressed: () => _showMoreOptions(context),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _buildRetweetCard(
    BuildContext context,
    WeiboStatusModel retweet,
    WeiboStyleSettings weiboStyle,
    Color linkColor,
  ) {
    final theme = Theme.of(context);
    final isFlat = weiboStyle.cardBackgroundLayout == 'flat_tile';
    final isShowingRetweetFull = widget.isDetail ||
        _isRetweetExpanded ||
        (retweet.fullTextRaw != null && retweet.fullTextRaw!.isNotEmpty);
    final retweetTextToDisplay = (isShowingRetweetFull
        ? (_loadedRetweetLongText ?? retweet.effectiveText)
        : retweet.textRaw);
    final visibleRetweetText = widget.isDetail
        ? retweetTextToDisplay
        : _trimTimelineTrailingWhitespace(retweetTextToDisplay);

    final retweetRadius = isFlat ? 6.0 : 16.0;

    return InkWell(
      borderRadius: BorderRadius.circular(retweetRadius),
      onTap: () => _openRetweetDetail(context, retweet),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(retweetRadius),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 0.7,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (ctx) {
                final retweetTextWidget = Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '@${retweet.user.screenName}：',
                        style: TextStyle(
                          fontWeight: context.adjustWeight(FontWeight.bold),
                          fontSize: weiboStyle.fontSize - 1,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      ...WeiboTextParser.parse(
                        rawText: visibleRetweetText,
                        context: context,
                        urlStruct: retweet.urlStruct,
                        htmlText: retweet.textHtml,
                        linkColor: linkColor,
                        defaultStyle: TextStyle(
                          fontSize: weiboStyle.fontSize - 1,
                          height: weiboStyle.fontLineHeight,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
                // The detail page's SelectionArea consumes taps in this
                // nested card before the card can open. The original post is
                // therefore a direct tap target here; the main post text
                // remains selectable through _buildMainText.
                final retweetTextTapTarget = InkWell(
                  key: ValueKey('retweet-text-${retweet.id}'),
                  enableFeedback: false,
                  onTap: () => _openRetweetDetail(context, retweet),
                  child: retweetTextWidget,
                );
                return retweetTextTapTarget;
              },
            ),
            if (retweet.isLongText && !widget.isDetail) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => _toggleRetweetExpand(retweet),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLoadingRetweetLongText) ...[
                        SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        _isRetweetExpanded ? '收起' : '展开全文',
                        style: TextStyle(
                          fontSize: weiboStyle.fontSize - 2,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Icon(
                        _isRetweetExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 15,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (retweet.pics.isNotEmpty) ...[
              const SizedBox(height: 8),
              NineGridView(
                pics: retweet.pics,
                statusId: retweet.id,
                isDetail: widget.isDetail,
                authorName: retweet.user.screenName,
              ),
            ] else if (retweet.videoCoverUrl?.isNotEmpty == true ||
                retweet.videoStreamUrl?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _buildVideoPreviewCard(context, retweet),
            ],
          ],
        ),
      ),
    );
  }

  void _openRetweetDetail(BuildContext context, WeiboStatusModel retweet) {
    try {
      final storage = ref.read(storageServiceProvider);
      storage.recordViewedStatusJson(retweet.id, jsonEncode(retweet.toJson()));
    } catch (_) {}
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => StatusDetailPage(status: retweet),
      ),
    );
  }

  Future<void> _handlePollOptionTap(
    WeiboPollModel poll,
    WeiboPollOption option, {
    required bool showResult,
  }) async {
    if (showResult || poll.hasVoted || poll.isEnded || _isSubmittingPoll) {
      return;
    }
    HapticFeedbackUtil.light();

    if (poll.isMultiChoice) {
      setState(() {
        if (!_selectedPollOptionIds.add(option.id)) {
          _selectedPollOptionIds.remove(option.id);
        }
      });
      return;
    }

    await _submitPollVote(poll, [option.id]);
  }

  Future<void> _submitPollVote(
    WeiboPollModel poll,
    List<String> optionIds,
  ) async {
    if (_isSubmittingPoll) return;
    setState(() => _isSubmittingPoll = true);

    final result = await ref.read(feedRepositoryProvider).setPollVote(
          voteId: poll.id,
          optionIds: optionIds,
        );
    if (!mounted) return;

    setState(() {
      _isSubmittingPoll = false;
      _selectedPollOptionIds.clear();
      if (result.poll != null) {
        _poll = result.poll;
        _showPollResults = _hasPollResultData(result.poll!);
      }
    });

    if (!result.success) {
      AppToast.show(context, result.message ?? '投票失败，请检查网络或登录状态');
      return;
    }

    AppToast.show(context, '投票成功');
    if (result.poll == null || !_hasPollResultData(result.poll!)) {
      final refreshed = await _refreshPollResult(result.poll ?? poll);
      if (mounted && refreshed != null && _hasPollResultData(refreshed)) {
        setState(() => _showPollResults = true);
      }
    }
  }

  Future<void> _togglePollResults(WeiboPollModel poll) async {
    if (_showPollResults) {
      setState(() => _showPollResults = false);
      return;
    }

    final refreshed = await _refreshPollResult(poll);
    if (!mounted) return;
    if (refreshed == null || !_hasPollResultData(refreshed)) {
      AppToast.show(context, '暂时无法获取投票结果，请稍后重试');
      return;
    }
    setState(() => _showPollResults = true);
  }

  Future<WeiboPollModel?> _refreshPollResult(WeiboPollModel poll) async {
    if (_isLoadingPollResult) return null;
    setState(() => _isLoadingPollResult = true);

    final statusId =
        widget.status.mid.isNotEmpty ? widget.status.mid : widget.status.id;
    final refreshed = await ref.read(feedRepositoryProvider).getPollResult(
          statusId: statusId,
          pollId: poll.id,
        );
    if (!mounted) return refreshed;

    setState(() {
      _isLoadingPollResult = false;
      if (refreshed != null) _poll = refreshed;
    });
    return refreshed;
  }

  Widget _buildPollCard(BuildContext context, WeiboPollModel poll) {
    final colorScheme = Theme.of(context).colorScheme;
    final options = _showAllPollOptions || poll.options.length <= 3
        ? poll.options
        : poll.options.take(3).toList();
    final showResult = _hasPollResultData(poll) &&
        (_showPollResults || poll.hasVoted || poll.isEnded);
    final participantCount = poll.participantCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            poll.title,
            style: TextStyle(
              fontSize: 16,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          ...options.map(
            (option) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildPollOption(
                context,
                poll,
                option,
                showResult: showResult,
              ),
            ),
          ),
          if (poll.isMultiChoice &&
              !showResult &&
              _selectedPollOptionIds.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isSubmittingPoll
                    ? null
                    : () => _submitPollVote(
                          poll,
                          _selectedPollOptionIds.toList(),
                        ),
                child: Text(_isSubmittingPoll ? '提交中…' : '提交投票'),
              ),
            ),
          Row(
            children: [
              if (poll.options.length > 3)
                TextButton(
                  onPressed: () => setState(
                    () => _showAllPollOptions = !_showAllPollOptions,
                  ),
                  child: Text(
                    _showAllPollOptions ? '收起' : '查看全部选项 ›',
                    style: const TextStyle(fontSize: 15),
                  ),
                )
              else
                const SizedBox.shrink(),
              const Spacer(),
              if (!poll.isEnded &&
                  (!poll.hasVoted || !_hasPollResultData(poll)))
                TextButton(
                  onPressed: _isLoadingPollResult
                      ? null
                      : () => _togglePollResults(poll),
                  child: Text(
                    _showPollResults ? '返回选项' : '查看结果',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                '$participantCount人参与',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (poll.endDescription != null &&
                  poll.endDescription!.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  poll.endDescription!,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const Spacer(),
              if (poll.creatorName.isNotEmpty)
                Text(
                  '@${poll.creatorName} 创建',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPollOption(
    BuildContext context,
    WeiboPollModel poll,
    WeiboPollOption option, {
    required bool showResult,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final percent = option.percent ?? _calculatePollPercent(poll, option);
    final selected = !showResult &&
        poll.isMultiChoice &&
        _selectedPollOptionIds.contains(option.id);

    return InkWell(
      borderRadius: BorderRadius.circular(9),
      splashFactory: InkSplash.splashFactory,
      enableFeedback: false,
      onTap: showResult || poll.hasVoted || poll.isEnded
          ? null
          : () => _handlePollOptionTap(
                poll,
                option,
                showResult: showResult,
              ),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: showResult
                ? colorScheme.outlineVariant.withValues(alpha: 0.7)
                : selected
                    ? colorScheme.primary
                    : colorScheme.outline.withValues(alpha: 0.8),
          ),
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
        ),
        child: showResult
            ? Stack(
                children: [
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (percent / 100).clamp(0, 1),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          option.text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        '${option.votes}票',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${percent.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Center(
                child: Text(
                  option.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: colorScheme.primary,
                  ),
                ),
              ),
      ),
    );
  }

  double _calculatePollPercent(
    WeiboPollModel poll,
    WeiboPollOption option,
  ) {
    final total = poll.options.fold<int>(0, (sum, item) => sum + item.votes);
    if (total <= 0) return 0;
    return option.votes * 100 / total;
  }

  bool _hasPollResultData(WeiboPollModel poll) {
    return poll.options.any(
      (option) =>
          option.votes > 0 || (option.percent != null && option.percent! > 0),
    );
  }

  Widget _buildHotTopicCard(
    BuildContext context,
    WeiboHotTopicModel topic,
    double bodyFontSize,
  ) {
    // 正文默认字号为 16pt；热搜使用 13pt，明确比正文小一档，同时保留
    // 12pt 的可读下限，避免用户把正文字号调小时热搜变得过小。
    final topicFontSize = (bodyFontSize - 3).clamp(12.0, 20.0).toDouble();
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        HapticFeedbackUtil.light();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SearchResultsPage(keyword: topic.word),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFFF8200).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              size: topicFontSize + 2,
              color: const Color(0xFFFF8200),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                topic.discussionText.isEmpty
                    ? topic.word
                    : '${topic.word} · ${topic.discussionText}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFFFF8200),
                  fontSize: topicFontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(
    BuildContext context,
    ColorScheme colorScheme,
    WeiboStyleSettings weiboStyle,
  ) {
    final status = widget.status;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildActionBtn(
          icon: Icons.repeat_rounded,
          count: status.repostsCount,
          color: colorScheme.onSurfaceVariant,
          onTap: () {
            HapticFeedbackUtil.light();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ComposeTweetPage(
                  initialText:
                      '//@${status.user.screenName}: ${status.effectiveText}',
                ),
              ),
            );
          },
        ),
        _buildActionBtn(
          icon: Icons.chat_bubble_outline_rounded,
          count: status.commentsCount,
          color: colorScheme.onSurfaceVariant,
          onTap: () {
            if (!widget.isDetail) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => StatusDetailPage(status: status),
                ),
              );
            }
          },
        ),
        _buildActionBtn(
          icon: _effectiveLiked
              ? Icons.thumb_up_rounded
              : Icons.thumb_up_outlined,
          count: _effectiveAttitudesCount,
          color: _effectiveLiked
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
          onTap: _handleToggleLike,
        ),
        if (weiboStyle.showMenuAtBottom)
          _buildActionBtn(
            icon: Icons.more_horiz_rounded,
            count: 0,
            color: colorScheme.onSurfaceVariant,
            onTap: () => _showMoreOptions(context),
          ),
      ],
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    String text = count > 0
        ? (count > 10000 ? '${(count / 10000).toStringAsFixed(1)}w' : '$count')
        : '';

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            if (text.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPreviewCard(BuildContext context, WeiboStatusModel status) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final coverUrl = status.videoCoverUrl ?? '';
    final streamUrl = status.videoStreamUrl ?? '';
    final duration = status.videoDuration;
    final playCount = status.videoPlayCount;
    final playCountStr = playCount > 10000
        ? '${(playCount / 10000).toStringAsFixed(1)}万次播放'
        : (playCount > 0 ? '$playCount次播放' : '');

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: Colors.black,
        child: InkWell(
          onTap: () {
            HapticFeedbackUtil.light();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WeiboVideoPlayerPage(
                  videoUrl: streamUrl,
                  statusId: status.id,
                  coverUrl: coverUrl,
                  title: status.videoTitle ??
                      (status.effectiveText.length > 30
                          ? '${status.effectiveText.substring(0, 30)}...'
                          : status.effectiveText),
                  authorName: status.user.screenName,
                  videoQualityUrls: status.videoQualityUrls,
                ),
              ),
            );
          },
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (coverUrl.isNotEmpty)
                  Image.network(
                    coverUrl,
                    headers: ApiConstants.imageHeaders,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: const Center(
                          child: Icon(Icons.video_library_rounded, size: 36)),
                    ),
                  )
                else
                  Container(
                    color: Colors.black87,
                    child: const Center(
                        child: Icon(Icons.video_library_rounded,
                            size: 36, color: Colors.white70)),
                  ),

                // Center Play Button
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 1.5),
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 34),
                  ),
                ),

                // Bottom Overlay Bar (Duration & Play Count)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (playCountStr.isNotEmpty)
                          Text(
                            playCountStr,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500),
                          )
                        else
                          const SizedBox.shrink(),
                        if (duration != null && duration.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              duration,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
