import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:extended_image/extended_image.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/card_display_provider.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/utils/weibo_text_parser.dart';
import '../../../core/utils/weibo_time_formatter.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../../feed/presentation/widgets/tweet_card.dart';
import '../../profile/presentation/user_profile_page.dart';
import '../data/detail_repository.dart';
import '../data/models/weibo_comment_model.dart';
import '../data/models/weibo_attitude_model.dart';
import 'widgets/comment_bottom_sheet.dart';
import 'widgets/image_gallery_page.dart';

/// Material You Status Detail Page with Two-Level Comment Tree and Comment Posting
class StatusDetailPage extends ConsumerStatefulWidget {
  final WeiboStatusModel? status;
  final String? statusId;

  const StatusDetailPage({
    super.key,
    this.status,
    this.statusId,
  }) : assert(status != null || statusId != null, 'Either status or statusId must be provided');

  @override
  ConsumerState<StatusDetailPage> createState() => _StatusDetailPageState();
}

class _StatusDetailPageState extends ConsumerState<StatusDetailPage> {
  WeiboStatusModel? _currentStatus;

  // Tabs: 0 = 转发, 1 = 评论, 2 = 赞
  int _selectedTabIndex = 1;
  // Comment Sorting: 0 = 按热度, 1 = 按时间
  int _commentSortFlow = 0;

  // Comments State
  final List<WeiboCommentModel> _comments = [];
  bool _isLoadingComments = true;
  String _maxId = '0';
  bool _hasMore = true;

  // Reposts State
  final List<WeiboStatusModel> _reposts = [];
  bool _isLoadingReposts = false;
  int _repostPage = 1;
  bool _hasMoreReposts = true;

  // Attitudes (Likes) State
  final List<WeiboAttitudeModel> _attitudes = [];
  bool _isLoadingAttitudes = false;
  int _attitudePage = 1;
  bool _hasMoreAttitudes = true;

  String get _effectiveStatusId {
    final candidate = (_currentStatus?.mid.isNotEmpty == true)
        ? _currentStatus!.mid
        : ((_currentStatus?.id.isNotEmpty == true)
            ? _currentStatus!.id
            : ((widget.status?.mid.isNotEmpty == true)
                ? widget.status!.mid
                : ((widget.status?.id.isNotEmpty == true)
                    ? widget.status!.id
                    : (widget.statusId ?? ''))));
    return WeiboStatusModel.mblogidToMid(candidate);
  }

  late final ScrollController _scrollController;
  double _savedScrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _currentStatus = widget.status;
    _fetchDetailAndComments();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      _savedScrollOffset = _scrollController.offset;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetailAndComments() async {
    if (_currentStatus != null) {
      _fetchComments();
      _fetchReposts();
      _fetchAttitudes();
    }
    _fetchFullStatus();
  }

  Future<void> _fetchFullStatus() async {
    final id = _effectiveStatusId;
    if (id.isEmpty) return;
    final repo = ref.read(detailRepositoryProvider);
    final updated = await repo.getStatusDetail(id);
    if (updated != null && mounted) {
      setState(() {
        _currentStatus = updated;
      });
      if (_comments.isEmpty) {
        _fetchComments();
      }
      if (_reposts.isEmpty) {
        _fetchReposts();
      }
      if (_attitudes.isEmpty) {
        _fetchAttitudes();
      }
    }
  }

  Future<void> _fetchComments() async {
    final id = _effectiveStatusId;
    if (id.isEmpty) return;
    setState(() {
      _isLoadingComments = true;
    });

    final repo = ref.read(detailRepositoryProvider);
    final result = await repo.getComments(
      id: id,
      uid: _currentStatus?.user.id ?? '',
      maxId: '0',
      flow: _commentSortFlow,
    );

    if (mounted) {
      setState(() {
        _comments.clear();
        _comments.addAll(result.comments);
        _maxId = result.maxId;
        _hasMore = result.hasMore;
        _isLoadingComments = false;
      });
    }
  }

  Future<bool> _loadMoreComments() async {
    if (!_hasMore) return false;
    final id = _effectiveStatusId;
    if (id.isEmpty) return false;
    final repo = ref.read(detailRepositoryProvider);
    final result = await repo.getComments(
      id: id,
      uid: _currentStatus?.user.id ?? '',
      maxId: _maxId,
      flow: _commentSortFlow,
    );

    if (mounted) {
      setState(() {
        _comments.addAll(result.comments);
        _maxId = result.maxId;
        _hasMore = result.hasMore;
      });
      return result.hasMore;
    }
    return false;
  }

  Future<void> _fetchReposts() async {
    final id = _effectiveStatusId;
    if (id.isEmpty) return;
    setState(() {
      _isLoadingReposts = true;
      _repostPage = 1;
    });

    final repo = ref.read(detailRepositoryProvider);
    final result = await repo.getReposts(id: id, page: 1);

    if (mounted) {
      setState(() {
        _reposts.clear();
        _reposts.addAll(result.reposts);
        _hasMoreReposts = result.hasMore;
        _isLoadingReposts = false;
      });
    }
  }

  Future<bool> _loadMoreReposts() async {
    if (!_hasMoreReposts) return false;
    final id = _effectiveStatusId;
    if (id.isEmpty) return false;

    final repo = ref.read(detailRepositoryProvider);
    final nextPage = _repostPage + 1;
    final result = await repo.getReposts(id: id, page: nextPage);

    if (mounted) {
      setState(() {
        _reposts.addAll(result.reposts);
        _repostPage = nextPage;
        _hasMoreReposts = result.hasMore;
      });
      return result.hasMore;
    }
    return false;
  }

  Future<void> _fetchAttitudes() async {
    final id = _effectiveStatusId;
    if (id.isEmpty) return;
    setState(() {
      _isLoadingAttitudes = true;
      _attitudePage = 1;
    });

    final repo = ref.read(detailRepositoryProvider);
    final result = await repo.getAttitudes(id: id, page: 1);

    if (mounted) {
      setState(() {
        _attitudes.clear();
        _attitudes.addAll(result.attitudes);
        _hasMoreAttitudes = result.hasMore;
        _isLoadingAttitudes = false;
      });
    }
  }

  Future<bool> _loadMoreAttitudes() async {
    if (!_hasMoreAttitudes) return false;
    final id = _effectiveStatusId;
    if (id.isEmpty) return false;

    final repo = ref.read(detailRepositoryProvider);
    final nextPage = _attitudePage + 1;
    final result = await repo.getAttitudes(id: id, page: nextPage);

    if (mounted) {
      setState(() {
        _attitudes.addAll(result.attitudes);
        _attitudePage = nextPage;
        _hasMoreAttitudes = result.hasMore;
      });
      return result.hasMore;
    }
    return false;
  }

  void _showCommentOptions(BuildContext context, WeiboCommentModel comment) {
    HapticFeedbackUtil.light();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final authState = ref.read(authProvider);
    final myUid = authState.uid;
    final statusAuthorId = _currentStatus?.user.id ?? widget.status?.user.id;
    final isMyComment = (myUid != null && myUid.isNotEmpty && comment.user.id == myUid);
    final isMyStatus = (myUid != null && myUid.isNotEmpty && statusAuthorId != null && statusAuthorId == myUid);
    final canDelete = isMyComment || isMyStatus;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2.25),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text('回复 @${comment.user.screenName}'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  CommentBottomSheet.show(
                    context,
                    statusId: _effectiveStatusId,
                    replyToComment: comment,
                    onCommentSuccess: _fetchComments,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('复制评论内容'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await Clipboard.setData(ClipboardData(text: comment.textRaw));
                  if (context.mounted) {
                    AppToast.show(context, '评论已复制到剪贴板');
                  }
                },
              ),
              if (canDelete)
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
                  title: Text(
                    '删除评论',
                    style: TextStyle(
                      color: colorScheme.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: isMyStatus && !isMyComment
                      ? Text(
                          '博主可删除他人评论',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.error.withValues(alpha: 0.8),
                          ),
                        )
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _confirmDeleteComment(
                      context,
                      comment,
                      isMyStatus: isMyStatus && !isMyComment,
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteComment(
    BuildContext context,
    WeiboCommentModel comment, {
    bool isMyStatus = false,
  }) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(isMyStatus ? '删除他人评论' : '删除评论'),
        content: Text(
          isMyStatus
              ? '确定要删除 @${comment.user.screenName} 的这条评论吗？删除后不可恢复。'
              : '确定要删除这条评论吗？删除后不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final res = await ref.read(detailRepositoryProvider).destroyComment(cid: comment.id);
      if (res.success) {
        if (mounted) {
          AppToast.show(context, '评论已删除');
          HapticFeedbackUtil.medium();
          setState(() {
            _comments.removeWhere((c) => c.id == comment.id);
            for (final c in _comments) {
              c.subComments.removeWhere((sub) => sub.id == comment.id);
            }
          });
        }
      } else {
        if (mounted) {
          AppToast.show(context, res.message?.isNotEmpty == true ? res.message! : '删除失败，请稍后重试');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_currentStatus == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('文章详情'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('文章详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: '更多操作',
            onPressed: () {
              TweetCard(status: _currentStatus!, isDetail: true).showMoreOptions(context, ref);
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Main Scrollable Area
          Expanded(
            child: EasyRefresh(
              onRefresh: () async {
                if (_selectedTabIndex == 0) {
                  await _fetchReposts();
                } else if (_selectedTabIndex == 1) {
                  await _fetchDetailAndComments();
                } else {
                  await _fetchAttitudes();
                }
              },
              onLoad: () async {
                if (_selectedTabIndex == 0) {
                  final hasMore = await _loadMoreReposts();
                  return hasMore ? IndicatorResult.success : IndicatorResult.noMore;
                } else if (_selectedTabIndex == 1) {
                  final hasMore = await _loadMoreComments();
                  return hasMore ? IndicatorResult.success : IndicatorResult.noMore;
                } else {
                  final hasMore = await _loadMoreAttitudes();
                  return hasMore ? IndicatorResult.success : IndicatorResult.noMore;
                }
              },
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // 1. Original Tweet Card
                  SliverToBoxAdapter(
                    child: TweetCard(status: _currentStatus!, isDetail: true),
                  ),

                  // 2. Interactive 3-Tab Bar (转发, 评论, 赞) + Sort Button
                  SliverToBoxAdapter(
                    child: _buildSectionTabBar(context),
                  ),

                  // 3. Tab Content
                  if (_selectedTabIndex == 0) ...[
                    // Reposts Tab
                    if (_isLoadingReposts && _reposts.isEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          constraints: BoxConstraints(
                            minHeight: _calculateMinTabHeight(context),
                          ),
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (_reposts.isEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          constraints: BoxConstraints(
                            minHeight: _calculateMinTabHeight(context),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '暂无转发内容',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final repost = _reposts[index];
                            return _buildRepostItem(context, repost);
                          },
                          childCount: _reposts.length,
                        ),
                      ),
                  ] else if (_selectedTabIndex == 1) ...[
                    // Comments Tab
                    if (_isLoadingComments && _comments.isEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          constraints: BoxConstraints(
                            minHeight: _calculateMinTabHeight(context),
                          ),
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (_comments.isEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          constraints: BoxConstraints(
                            minHeight: _calculateMinTabHeight(context),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '暂无评论，快来抢沙发吧~',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final comment = _comments[index];
                            return _buildCommentItem(context, comment);
                          },
                          childCount: _comments.length,
                        ),
                      ),
                  ] else ...[
                    // Attitudes (Likes) Tab
                    if (_isLoadingAttitudes && _attitudes.isEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          constraints: BoxConstraints(
                            minHeight: _calculateMinTabHeight(context),
                          ),
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (_attitudes.isEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          constraints: BoxConstraints(
                            minHeight: _calculateMinTabHeight(context),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '暂无点赞用户',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final attitude = _attitudes[index];
                            return _buildAttitudeItem(context, attitude);
                          },
                          childCount: _attitudes.length,
                        ),
                      ),
                  ],

                  // 4. Dynamic Bottom Spacer to prevent scroll extent collapse
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: _savedScrollOffset > 0 ? 120 : 24,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Quick Comment Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        CommentBottomSheet.show(
                          context,
                          statusId: _effectiveStatusId,
                          onCommentSuccess: _fetchComments,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Text('发送一条友善的评论...', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.send_rounded, color: colorScheme.primary),
                    tooltip: '发表评论',
                    onPressed: () {
                      CommentBottomSheet.show(
                        context,
                        statusId: _effectiveStatusId,
                        onCommentSuccess: _fetchComments,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTabBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final repostsCount = _currentStatus?.repostsCount ?? _reposts.length;
    final commentsCount = _currentStatus?.commentsCount ?? _comments.length;
    final attitudesCount = _currentStatus?.attitudesCount ?? _attitudes.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          // 3 Tabs: 转发, 评论, 赞
          _buildTabItem(context, index: 0, label: '转发 $repostsCount'),
          const SizedBox(width: 20),
          _buildTabItem(context, index: 1, label: '评论 $commentsCount'),
          const SizedBox(width: 20),
          _buildTabItem(context, index: 2, label: '赞 $attitudesCount'),

          const Spacer(),

          // Sort Button (Only visible in Comments Tab)
          if (_selectedTabIndex == 1)
            PopupMenuButton<int>(
              initialValue: _commentSortFlow,
              tooltip: '排序方式',
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (val) {
                if (_commentSortFlow != val) {
                  HapticFeedbackUtil.light();
                  final currentOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                  _savedScrollOffset = currentOffset;
                  setState(() {
                    _commentSortFlow = val;
                    _comments.clear();
                    _maxId = '0';
                    _hasMore = true;
                    _isLoadingComments = true;
                  });
                  _fetchComments();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _scrollController.hasClients && _savedScrollOffset > 0) {
                      final maxExt = _scrollController.position.maxScrollExtent;
                      final target = _savedScrollOffset.clamp(0.0, maxExt);
                      if ((_scrollController.offset - target).abs() > 1.0) {
                        _scrollController.jumpTo(target);
                      }
                    }
                  });
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.swap_vert_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _commentSortFlow == 0 ? '按热度' : '按时间',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              itemBuilder: (ctx) => [
                PopupMenuItem<int>(
                  value: 0,
                  child: Row(
                    children: [
                      Icon(
                        Icons.local_fire_department_rounded,
                        size: 18,
                        color: _commentSortFlow == 0 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '按热度',
                        style: TextStyle(
                          fontWeight: _commentSortFlow == 0 ? FontWeight.bold : FontWeight.normal,
                          color: _commentSortFlow == 0 ? colorScheme.primary : colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<int>(
                  value: 1,
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 18,
                        color: _commentSortFlow == 1 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '按时间',
                        style: TextStyle(
                          fontWeight: _commentSortFlow == 1 ? FontWeight.bold : FontWeight.normal,
                          color: _commentSortFlow == 1 ? colorScheme.primary : colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  double _calculateMinTabHeight(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final base = _savedScrollOffset > 0 ? _savedScrollOffset + 400.0 : screenHeight * 0.6;
    return base.clamp(screenHeight * 0.5, screenHeight * 2.5);
  }

  Widget _buildTabItem(BuildContext context, {required int index, required String label}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _selectedTabIndex == index;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (_selectedTabIndex != index) {
          HapticFeedbackUtil.selection();
          final currentOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
          _savedScrollOffset = currentOffset;
          setState(() {
            _selectedTabIndex = index;
          });
          if (index == 0 && _reposts.isEmpty && !_isLoadingReposts) {
            _fetchReposts();
          } else if (index == 2 && _attitudes.isEmpty && !_isLoadingAttitudes) {
            _fetchAttitudes();
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scrollController.hasClients && _savedScrollOffset > 0) {
              final maxExt = _scrollController.position.maxScrollExtent;
              final target = _savedScrollOffset.clamp(0.0, maxExt);
              if ((_scrollController.offset - target).abs() > 1.0) {
                _scrollController.jumpTo(target);
              }
            }
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected
                    ? context.adjustWeight(FontWeight.bold)
                    : FontWeight.normal,
                color: isSelected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              height: 3,
              width: isSelected ? 24 : 0,
              decoration: BoxDecoration(
                color: isSelected ? colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepostItem(BuildContext context, WeiboStatusModel repost) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => StatusDetailPage(status: repost, statusId: repost.id),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppAvatar(
              url: repost.user.avatar,
              size: 36,
              name: repost.user.screenName,
              verified: repost.user.verified,
              verifiedType: repost.user.verifiedType,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => UserProfilePage(
                      user: repost.user,
                      uid: repost.user.id,
                      screenName: repost.user.screenName,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => UserProfilePage(
                            user: repost.user,
                            uid: repost.user.id,
                            screenName: repost.user.screenName,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      repost.user.screenName,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: context.adjustWeight(FontWeight.bold),
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    WeiboTimeFormatter.format(
                      rawDate: repost.createdAt,
                      settings: ref.watch(cardDisplayProvider),
                      language: 'zh',
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectionArea(
                    child: Text.rich(
                      TextSpan(
                        children: WeiboTextParser.parse(
                          rawText: (repost.fullTextRaw != null && repost.fullTextRaw!.isNotEmpty)
                              ? repost.fullTextRaw!
                              : repost.textRaw,
                          context: context,
                          urlStruct: repost.urlStruct,
                          defaultStyle: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurface,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttitudeItem(BuildContext context, WeiboAttitudeModel attitude) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => UserProfilePage(
              user: attitude.user,
              uid: attitude.user.id,
              screenName: attitude.user.screenName,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            AppAvatar(
              url: attitude.user.avatar,
              size: 40,
              name: attitude.user.screenName,
              verified: attitude.user.verified,
              verifiedType: attitude.user.verifiedType,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          attitude.user.screenName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: context.adjustWeight(FontWeight.bold),
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (attitude.user.verified) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.verified_rounded,
                          size: 14,
                          color: attitude.user.verifiedType == 0 ? Colors.amber : Colors.blue,
                        ),
                      ],
                    ],
                  ),
                  if (attitude.user.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      attitude.user.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.favorite_rounded,
              size: 20,
              color: Colors.pink.shade400,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentItem(BuildContext context, WeiboCommentModel comment) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      enableFeedback: false,
      onTap: () => _showCommentOptions(context, comment),
      onLongPress: () => _showCommentOptions(context, comment),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            AppAvatar(
              url: comment.user.avatar,
              size: 36,
              name: comment.user.screenName,
              verified: comment.user.verified,
              verifiedType: comment.user.verifiedType,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => UserProfilePage(
                      user: comment.user,
                      uid: comment.user.id,
                      screenName: comment.user.screenName,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 10),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Username + Verified & Like Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (ctx) => UserProfilePage(
                                        user: comment.user,
                                        uid: comment.user.id,
                                        screenName: comment.user.screenName,
                                      ),
                                    ),
                                  );
                                },
                                child: Text(
                                  comment.user.screenName,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: context.adjustWeight(FontWeight.bold),
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            if (comment.user.verified) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.verified_rounded,
                                size: 14,
                                color: comment.user.verifiedType == 0 ? Colors.amber : Colors.blue,
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Heart Like Icon & Count
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          HapticFeedbackUtil.light();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (comment.likeCount > 0) ...[
                                Text(
                                  '${comment.likeCount}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: comment.liked ? Colors.pink.shade400 : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Icon(
                                comment.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                size: 16,
                                color: comment.liked ? Colors.pink.shade400 : colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),

                  // Subtitle: Time + IP / AI generation label (e.g. "10分钟前 来自 湖北", "18分钟前 来自 AI生成")
                  Text(
                    comment.formattedIpOrSource.isNotEmpty
                        ? '${WeiboTimeFormatter.format(
                            rawDate: comment.createdAt,
                            settings: ref.watch(cardDisplayProvider),
                            language: 'zh',
                          )}  ${comment.formattedIpOrSource}'
                        : WeiboTimeFormatter.format(
                            rawDate: comment.createdAt,
                            settings: ref.watch(cardDisplayProvider),
                            language: 'zh',
                          ),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Comment Text (Text.rich avoids scroll conflicts)
                  if (comment.textRaw.isNotEmpty) ...[
                    SelectionArea(
                      child: Text.rich(
                        TextSpan(
                          children: WeiboTextParser.parse(
                            rawText: comment.textRaw,
                            context: context,
                            urlStruct: comment.urlStruct,
                            defaultStyle: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurface,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // Comment Images if any
                  if (comment.pics.isNotEmpty) ...[
                    _buildCommentPics(context, comment.pics, comment.id, comment.user.screenName),
                    const SizedBox(height: 6),
                  ],

                  // Sub-comments if any
                  if (comment.subComments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: comment.subComments.map((sub) {
                          return InkWell(
                            borderRadius: BorderRadius.circular(6),
                            enableFeedback: false,
                            onTap: () => _showCommentOptions(context, sub),
                            onLongPress: () => _showCommentOptions(context, sub),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectionArea(
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          WidgetSpan(
                                            alignment: PlaceholderAlignment.middle,
                                            child: InkWell(
                                              onTap: () {
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (ctx) => UserProfilePage(
                                                      user: sub.user,
                                                      uid: sub.user.id,
                                                      screenName: sub.user.screenName,
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: Text(
                                                '${sub.user.screenName}: ',
                                                style: TextStyle(
                                                  fontWeight: context.adjustWeight(FontWeight.bold),
                                                  fontSize: 12.5,
                                                  color: colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (sub.textRaw.isNotEmpty)
                                            ...WeiboTextParser.parse(
                                              rawText: sub.textRaw,
                                              context: context,
                                              urlStruct: sub.urlStruct,
                                              defaultStyle: TextStyle(
                                                fontSize: 12.5,
                                                color: colorScheme.onSurface,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (sub.pics.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    _buildCommentPics(context, sub.pics, sub.id, sub.user.screenName),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentPics(BuildContext context, List<WeiboPicModel> pics, String commentId, String authorName) {
    final validPics = pics.where((p) => p.largeUrl.isNotEmpty || p.thumbnail.isNotEmpty).toList();
    if (validPics.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (validPics.length == 1) {
      final pic = validPics.first;
      double aspectRatio = 1.0;
      if (pic.width > 0 && pic.height > 0) {
        aspectRatio = pic.width / pic.height;
        if (aspectRatio > 2.2) aspectRatio = 2.2;
        if (aspectRatio < 0.5) aspectRatio = 0.5;
      }

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
                pics: validPics,
                initialIndex: 0,
                statusId: commentId,
                authorName: authorName,
              ),
              transitionsBuilder: (_, animation, __, child) => FadeTransition(
                opacity: animation,
                child: child,
              ),
            ),
          );
        },
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 160,
            maxHeight: 180,
          ),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ExtendedImage.network(
                    pic.bmiddleUrl.isNotEmpty ? pic.bmiddleUrl : pic.largeUrl,
                    headers: ApiConstants.imageHeaders,
                    fit: BoxFit.cover,
                    cache: true,
                    loadStateChanged: (ExtendedImageState state) {
                      switch (state.extendedImageLoadState) {
                        case LoadState.loading:
                          return Container(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          );
                        case LoadState.completed:
                          return state.completedWidget;
                        case LoadState.failed:
                          return const SizedBox.shrink();
                      }
                    },
                  ),
                ),
                if (pic.isLivePhoto)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.motion_photos_on_rounded, size: 10, color: Colors.white),
                          SizedBox(width: 2),
                          Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  )
                else if (pic.isGif || pic.isLong)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        pic.isGif ? 'GIF' : '长图',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Multiple images (grid)
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(validPics.length, (idx) {
        final pic = validPics[idx];
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
                  pics: validPics,
                  initialIndex: idx,
                  statusId: commentId,
                  authorName: authorName,
                ),
                transitionsBuilder: (_, animation, __, child) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 80,
              height: 80,
              child: ExtendedImage.network(
                pic.bmiddleUrl.isNotEmpty ? pic.bmiddleUrl : pic.largeUrl,
                headers: ApiConstants.imageHeaders,
                fit: BoxFit.cover,
                cache: true,
                loadStateChanged: (ExtendedImageState state) {
                  switch (state.extendedImageLoadState) {
                    case LoadState.loading:
                      return Container(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      );
                    case LoadState.completed:
                      return state.completedWidget;
                    case LoadState.failed:
                      return const SizedBox.shrink();
                  }
                },
              ),
            ),
          ),
        );
      }),
    );
  }
}
