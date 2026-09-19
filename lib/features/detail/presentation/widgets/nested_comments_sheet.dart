import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:extended_image/extended_image.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/card_display_provider.dart';
import '../../../../core/utils/haptic_feedback_util.dart';
import '../../../../core/utils/weibo_text_parser.dart';
import '../../../../core/utils/weibo_time_formatter.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../feed/data/models/weibo_status_model.dart';
import '../../../profile/presentation/user_profile_page.dart';
import '../../data/detail_repository.dart';
import '../../data/models/weibo_comment_model.dart';
import 'image_gallery_page.dart';

/// Displays the complete second-level comment thread.
///
/// The comment object embedded in the first-level response is only a preview.
/// This sheet fetches the official second-level endpoint and follows its
/// returned max_id cursor instead of assuming that preview length is the
/// complete thread.
class NestedCommentsSheet extends ConsumerStatefulWidget {
  final WeiboCommentModel parentComment;
  final int totalCount;
  final String statusAuthorId;
  final ValueChanged<WeiboCommentModel> onCommentTap;

  const NestedCommentsSheet({
    super.key,
    required this.parentComment,
    required this.totalCount,
    required this.statusAuthorId,
    required this.onCommentTap,
  });

  @override
  ConsumerState<NestedCommentsSheet> createState() =>
      _NestedCommentsSheetState();
}

class _NestedCommentsSheetState extends ConsumerState<NestedCommentsSheet> {
  final _scrollController = ScrollController();
  final _comments = <WeiboCommentModel>[];
  String _maxId = '0';
  bool _hasMore = true;
  bool _isLoading = false;

  int get _displayedCount {
    final count = widget.totalCount;
    return count > _comments.length ? count : _comments.length;
  }

  @override
  void initState() {
    super.initState();
    _comments.addAll(widget.parentComment.subComments);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPage(reset: true);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoading || !_hasMore) return;
    if (_scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <
        240) {
      _loadPage();
    }
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_isLoading || (!reset && !_hasMore)) return;

    final requestedMaxId = reset ? '0' : _maxId;
    setState(() => _isLoading = true);
    final result = await ref.read(detailRepositoryProvider).getSecondComments(
          commentId: widget.parentComment.id,
          uid: widget.statusAuthorId,
          maxId: requestedMaxId,
        );

    if (!mounted) return;

    setState(() {
      if (reset && result.comments.isNotEmpty) {
        _comments
          ..clear()
          ..addAll(result.comments);
        // Keep any preview item that the official response omitted, without
        // duplicating rows. This is useful when the first request is served
        // from a slightly different cache than the parent status response.
        _appendMissing(widget.parentComment.subComments);
      } else {
        _appendMissing(result.comments);
      }

      final nextMaxId = result.maxId.trim();
      _maxId = nextMaxId.isEmpty ? '0' : nextMaxId;
      _hasMore = result.hasMore &&
          result.comments.isNotEmpty &&
          _maxId != '0' &&
          _maxId != requestedMaxId;
      _isLoading = false;
    });
  }

  void _appendMissing(Iterable<WeiboCommentModel> incoming) {
    for (final comment in incoming) {
      final id = comment.id.trim();
      final alreadyExists = id.isNotEmpty
          ? _comments.any((existing) => existing.id.trim() == id)
          : false;
      if (!alreadyExists) _comments.add(comment);
    }
  }

  bool _isStatusAuthor(WeiboUserModel user) {
    final statusAuthorId = widget.statusAuthorId.trim();
    final userId = user.id.trim();
    return statusAuthorId.isNotEmpty &&
        userId.isNotEmpty &&
        statusAuthorId == userId;
  }

  Widget _bloggerBadge(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.orange.shade700,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          '博主',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            height: 1.1,
            fontWeight: context.adjustWeight(FontWeight.w600),
          ),
        ),
      ),
    );
  }

  void _openProfile(WeiboUserModel user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfilePage(
          user: user,
          uid: user.id,
          screenName: user.screenName,
        ),
      ),
    );
  }

  Widget _buildReplyPics(BuildContext context, WeiboCommentModel reply) {
    final pics = reply.pics
        .where((pic) => pic.largeUrl.isNotEmpty || pic.thumbnail.isNotEmpty)
        .toList();
    if (pics.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: pics.map((pic) {
        final url = pic.bmiddleUrl.isNotEmpty
            ? pic.bmiddleUrl
            : (pic.largeUrl.isNotEmpty ? pic.largeUrl : pic.thumbnail);
        return GestureDetector(
          onTap: () {
            HapticFeedbackUtil.light();
            Navigator.of(context).push(
              PageRouteBuilder(
                opaque: false,
                barrierColor: Colors.black,
                transitionDuration: const Duration(milliseconds: 220),
                reverseTransitionDuration: const Duration(milliseconds: 200),
                pageBuilder: (_, __, ___) => ImageGalleryPage(
                  pics: pics,
                  initialIndex: pics.indexOf(pic),
                  statusId: reply.id,
                  authorName: reply.user.screenName,
                ),
                transitionsBuilder: (_, animation, __, child) =>
                    FadeTransition(opacity: animation, child: child),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ExtendedImage.network(
              url,
              headers: ApiConstants.imageHeaders,
              width: 92,
              height: 92,
              fit: BoxFit.cover,
              cache: true,
              loadStateChanged: (state) {
                switch (state.extendedImageLoadState) {
                  case LoadState.loading:
                    return Container(
                      width: 92,
                      height: 92,
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    );
                  case LoadState.completed:
                    return state.completedWidget;
                  case LoadState.failed:
                    return Container(
                      width: 92,
                      height: 92,
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined),
                    );
                }
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildReply(BuildContext context, WeiboCommentModel reply) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('nested-reply-${reply.id}'),
      onTap: () => widget.onCommentTap(reply),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppAvatar(
              url: reply.user.avatar,
              size: 40,
              name: reply.user.screenName,
              verified: reply.user.verified,
              verifiedType: reply.user.verifiedType,
              onTap: () => _openProfile(reply.user),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: InkWell(
                                onTap: () => _openProfile(reply.user),
                                child: Text(
                                  reply.user.screenName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontSize: 14,
                                    fontWeight:
                                        context.adjustWeight(FontWeight.w600),
                                  ),
                                ),
                              ),
                            ),
                            if (reply.user.verified) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.verified_rounded,
                                size: 14,
                                color: reply.user.verifiedType == 0
                                    ? Colors.amber
                                    : Colors.blue,
                              ),
                            ],
                            if (_isStatusAuthor(reply.user)) ...[
                              const SizedBox(width: 4),
                              _bloggerBadge(context),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 66,
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (reply.likeCount > 0)
                                Text(
                                  '${reply.likeCount}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              const SizedBox(width: 4),
                              Icon(
                                reply.liked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 20,
                                color: reply.liked
                                    ? Colors.pink.shade400
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reply.formattedIpOrSource.isEmpty
                        ? WeiboTimeFormatter.format(
                            rawDate: reply.createdAt,
                            settings: ref.watch(cardDisplayProvider),
                            language: 'zh',
                          )
                        : '${WeiboTimeFormatter.format(
                            rawDate: reply.createdAt,
                            settings: ref.watch(cardDisplayProvider),
                            language: 'zh',
                          )}  ${reply.formattedIpOrSource}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (reply.textRaw.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onCommentTap(reply),
                      child: SelectionArea(
                        child: Text.rich(
                          TextSpan(
                            children: WeiboTextParser.parse(
                              rawText: reply.textRaw,
                              context: context,
                              urlStruct: reply.urlStruct,
                              defaultStyle: TextStyle(
                                fontSize: 15,
                                height: 1.4,
                                color: colorScheme.onSurface,
                              ),
                              onPlainTextTap: () => widget.onCommentTap(reply),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (reply.pics.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _buildReplyPics(context, reply),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: Text(
                      '共$_displayedCount条回复',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: context.adjustWeight(FontWeight.w600),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新回复',
                    onPressed: _isLoading ? null : () => _loadPage(reset: true),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
            Expanded(
              child: _comments.isEmpty && _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _comments.isEmpty
                      ? Center(
                          child: Text(
                            '暂无回复',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: _comments.length +
                              (_isLoading ? 1 : 0) +
                              (!_isLoading && _hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _comments.length) {
                              if (!_isLoading && _hasMore) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 8, 16, 18),
                                  child: OutlinedButton.icon(
                                    onPressed: () => _loadPage(),
                                    icon: const Icon(Icons.expand_more_rounded),
                                    label: const Text('加载更多回复'),
                                  ),
                                );
                              }
                              return const Padding(
                                padding: EdgeInsets.all(18),
                                child: Center(
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              );
                            }
                            return _buildReply(context, _comments[index]);
                          },
                        ),
            ),
            if (!_isLoading && _comments.isNotEmpty && !_hasMore)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  '没有更多回复',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
