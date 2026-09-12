import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/weibo_text_parser.dart';
import '../../../core/utils/weibo_time_formatter.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../auth/presentation/login_page.dart';
import '../../detail/data/detail_repository.dart';
import '../../detail/data/models/weibo_comment_model.dart';
import '../../detail/presentation/status_detail_page.dart';
import '../../feed/data/models/weibo_status_model.dart';

/// 收到的赞 独立通知页面 (无多余顶栏 Tab，专注呈现赞记录)
class ReceivedLikesPage extends ConsumerWidget {
  const ReceivedLikesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLoggedIn = authState.isLoggedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('收到的赞', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: !isLoggedIn
          ? _buildNotLoggedIn(context, colorScheme)
          : const _AttitudesListView(),
    );
  }
}

/// 发出的评论 独立记录页面 (无多余顶栏 Tab，专注呈现发出的评论)
class SentCommentsPage extends ConsumerWidget {
  const SentCommentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLoggedIn = authState.isLoggedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('发出的评论', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: !isLoggedIn
          ? _buildNotLoggedIn(context, colorScheme)
          : const _CommentsListView(endpoint: '/ajax/message/myCmt', isOutbox: true),
    );
  }
}

/// 收到的评论 独立互动页面 (无多余顶栏 Tab，专注呈现收到的评论与回复)
class ReceivedCommentsPage extends ConsumerWidget {
  const ReceivedCommentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLoggedIn = authState.isLoggedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('收到的评论', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: !isLoggedIn
          ? _buildNotLoggedIn(context, colorScheme)
          : const _CommentsListView(endpoint: '/ajax/message/cmt', isOutbox: false),
    );
  }
}

Widget _buildNotLoggedIn(BuildContext context, ColorScheme colorScheme) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.mark_email_unread_outlined,
            size: 60, color: colorScheme.primary.withValues(alpha: 0.6)),
        const SizedBox(height: 16),
        const Text('登录后即可同步查看记录与通知',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (ctx) => const LoginPage()),
            );
          },
          icon: const Icon(Icons.login_rounded),
          label: const Text('立即登录'),
        ),
      ],
    ),
  );
}

/// 互动通知页面 (按指定索引直接定向到对应独立页面)
class LikesCommentsPage extends StatelessWidget {
  final int initialTabIndex;

  const LikesCommentsPage({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (initialTabIndex == 1) {
      return const SentCommentsPage();
    } else if (initialTabIndex == 2) {
      return const ReceivedCommentsPage();
    }
    return const ReceivedLikesPage();
  }
}

/// 官方原生收到的赞列表 (精准直连 /ajax/message/attitudes)
class _AttitudesListView extends ConsumerStatefulWidget {
  const _AttitudesListView();

  @override
  ConsumerState<_AttitudesListView> createState() => _AttitudesListViewState();
}

class _AttitudesListViewState extends ConsumerState<_AttitudesListView>
    with AutomaticKeepAliveClientMixin {
  final List<Map<String, dynamic>> _attitudes = [];
  bool _isLoading = true;
  int _page = 1;
  bool _hasMore = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchAttitudes(refresh: true);
  }

  Future<void> _fetchAttitudes({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      setState(() => _isLoading = true);
    }

    final client = ref.read(weiboDioClientProvider);
    final extracted = <Map<String, dynamic>>[];

    try {
      final res = await client.dio.get(
        '/ajax/message/attitudes',
        queryParameters: {'page': _page},
      );
      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        final rawList = data['data']?['attitudes'] as List? ??
            data['attitudes'] as List? ??
            [];
        extracted.addAll(rawList.whereType<Map<String, dynamic>>());
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        if (refresh) {
          _attitudes.clear();
        }
        _attitudes.addAll(extracted);
        _hasMore = extracted.isNotEmpty;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    return EasyRefresh(
      onRefresh: () => _fetchAttitudes(refresh: true),
      onLoad: () async {
        _page++;
        await _fetchAttitudes(refresh: false);
        return _hasMore ? IndicatorResult.success : IndicatorResult.noMore;
      },
      child: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : _attitudes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_rounded,
                          size: 54, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text(
                        '暂无收到的赞',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _attitudes.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 64, thickness: 0.5),
                  itemBuilder: (context, index) {
                    final item = _attitudes[index];
                    final user = item['user'] is Map ? (item['user'] as Map<String, dynamic>) : {};
                    final nick = user['screen_name']?.toString() ?? '微博用户';
                    final avatar = user['avatar_hd']?.toString() ??
                        user['avatar_large']?.toString() ??
                        user['profile_image_url']?.toString() ??
                        '';
                    final createdAt = item['created_at']?.toString() ?? '';
                    final status =
                        item['status'] is Map ? (item['status'] as Map<String, dynamic>) : null;
                    final comment =
                        item['comment'] is Map ? (item['comment'] as Map<String, dynamic>) : null;
                    final isCommentLike = comment != null;

                    return ListTile(
                      leading: AppAvatar(url: avatar, size: 40, name: nick),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              nick,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.favorite_rounded, size: 14, color: Colors.red.shade400),
                          const SizedBox(width: 4),
                          Text(
                            isCommentLike ? '赞了你的评论' : '赞了你的微博',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (createdAt.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              WeiboTimeFormatter.format(rawDate: createdAt),
                              style: TextStyle(fontSize: 12, color: colorScheme.outline),
                            ),
                          ],
                          const SizedBox(height: 6),
                          // Quoted Status / Comment Container
                          if (status != null || comment != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color:
                                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                isCommentLike
                                    ? (comment['text_raw']?.toString() ??
                                        comment['text']?.toString() ??
                                        '')
                                    : (status!['text_raw']?.toString() ??
                                        status['text']?.toString() ??
                                        ''),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.3,
                                ),
                              ),
                            ),
                        ],
                      ),
                      onTap: () {
                        if (status != null) {
                          final statusModel = WeiboStatusModel.fromJson(status);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (ctx) => StatusDetailPage(status: statusModel)),
                          );
                        }
                      },
                    );
                  },
                ),
    );
  }
}

class _CommentsListView extends ConsumerStatefulWidget {
  final String endpoint;
  final bool isOutbox;

  const _CommentsListView({
    required this.endpoint,
    required this.isOutbox,
  });

  @override
  ConsumerState<_CommentsListView> createState() => _CommentsListViewState();
}

class _CommentsListViewState extends ConsumerState<_CommentsListView>
    with AutomaticKeepAliveClientMixin {
  final List<Map<String, dynamic>> _comments = [];
  final Set<String> _deletingCommentIds = <String>{};
  bool _isLoading = true;
  int _page = 1;
  bool _hasMore = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchComments(refresh: true);
  }

  Future<void> _fetchComments({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      setState(() => _isLoading = true);
    }

    final client = ref.read(weiboDioClientProvider);
    final extracted = <Map<String, dynamic>>[];

    try {
      final res = await client.dio.get(
        widget.endpoint,
        queryParameters: {'page': _page},
      );
      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        final rawList = data['data']?['comments'] as List? ??
            data['comments'] as List? ??
            data['data'] as List? ??
            [];
        extracted.addAll(rawList.whereType<Map<String, dynamic>>());
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        if (refresh) {
          _comments.clear();
        }
        _comments.addAll(extracted);
        _hasMore = extracted.isNotEmpty;
        _isLoading = false;
      });
    }
  }

  static Map<String, dynamic>? _mapValue(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String _firstNonEmptyString(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static bool _isUsableCommentId(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isNotEmpty &&
        normalized != '0' &&
        normalized != '-1' &&
        normalized != 'null';
  }

  String _commentIdFromJson(Map<String, dynamic> json) {
    final id = _firstNonEmptyString(
      json,
      const [
        'id',
        'idstr',
        'cid',
        'cidstr',
        'comment_id',
        'comment_idstr',
        'commentId',
        'commentIdStr',
        'mid',
      ],
    );
    return _isUsableCommentId(id) ? id : '';
  }

  List<String> _parentChainFromValue(Object? value, {int depth = 0}) {
    if (depth > 8) return const [];

    final map = _mapValue(value);
    if (map == null) {
      final id = value?.toString().trim() ?? '';
      return _isUsableCommentId(id) ? [id] : const [];
    }

    final chain = <String>[];
    final ownId = _commentIdFromJson(map);
    if (ownId.isNotEmpty) chain.add(ownId);

    for (final key in const [
      'rootid',
      'rootidstr',
      'root_id',
      'rootId',
      'root_comment',
      'rootComment',
      'root_comment_id',
      'rootCommentId',
      'reply_comment',
      'replyComment',
      'reply_comment_id',
      'replyCommentId',
      'reply_cid',
      'replyCid',
      'parent_comment_id',
      'parentCommentId',
      'parent_cid',
      'parentCid',
    ]) {
      final nestedChain =
          _parentChainFromValue(map[key], depth: depth + 1);
      for (final id in nestedChain) {
        if (_isUsableCommentId(id) && !chain.contains(id)) chain.add(id);
      }
    }
    return chain;
  }

  String _replyParentIdFromJson(Map<String, dynamic> json) {
    for (final key in const [
      'rootid',
      'rootidstr',
      'root_id',
      'rootId',
      'root_comment',
      'rootComment',
      'root_comment_id',
      'rootCommentId',
      'reply_comment',
      'replyComment',
      'reply_comment_id',
      'replyCommentId',
      'reply_cid',
      'replyCid',
      'parent_comment_id',
      'parentCommentId',
      'parent_cid',
      'parentCid',
    ]) {
      final chain = _parentChainFromValue(json[key]);
      if (chain.isNotEmpty) return chain.last;
    }
    return '';
  }

  Map<String, dynamic>? _statusFromComment(Map<String, dynamic> json) {
    for (final key in const [
      'status',
      'root_status',
      'rootStatus',
      'mblog',
      'weibo',
    ]) {
      final status = _mapValue(json[key]);
      if (status != null) return status;
    }
    return null;
  }

  String _statusIdFromComment(
    Map<String, dynamic> comment,
    Map<String, dynamic>? status,
  ) {
    if (status != null) {
      final statusId = _firstNonEmptyString(
        status,
        const ['id', 'mblogid', 'mid', 'idstr'],
      );
      if (statusId.isNotEmpty) return statusId;
    }
    return _firstNonEmptyString(
      comment,
      const [
        'status_id',
        'statusId',
        'status_mid',
        'mblogid',
        'mblog_id',
        'weibo_id',
        'weibo_mid',
      ],
    );
  }

  bool _sameCommentId(String left, String right) {
    final leftId = left.trim();
    final rightId = right.trim();
    if (leftId.isEmpty || rightId.isEmpty) return false;
    if (leftId == rightId) return true;
    return WeiboStatusModel.mblogidToMid(leftId) ==
        WeiboStatusModel.mblogidToMid(rightId);
  }

  void _openComment(BuildContext context, Map<String, dynamic> comment) {
    final statusJson = _statusFromComment(comment);
    final statusId = _statusIdFromComment(comment, statusJson);
    if (statusJson == null && statusId.isEmpty) return;

    final commentId = _commentIdFromJson(comment);
    final parentId = _replyParentIdFromJson(comment);
    final status = statusJson == null
        ? null
        : WeiboStatusModel.fromJson(statusJson);
    final initialComment = commentId.isEmpty
        ? null
        : WeiboCommentModel.fromJson(comment);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => StatusDetailPage(
          status: status,
          statusId: statusId.isEmpty ? null : statusId,
          initialComment: initialComment,
          initialCommentId: commentId.isEmpty ? null : commentId,
          initialCommentParentId: parentId.isEmpty ? null : parentId,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteComment(
    BuildContext context,
    Map<String, dynamic> comment,
  ) async {
    final commentId = _commentIdFromJson(comment);
    if (commentId.isEmpty) {
      AppToast.show(context, '未找到评论编号，无法删除');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除评论'),
        content: const Text('确定要删除这条评论吗？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingCommentIds.add(commentId));
    final result = await ref
        .read(detailRepositoryProvider)
        .destroyComment(cid: commentId);
    if (!mounted) return;

    setState(() {
      _deletingCommentIds.remove(commentId);
      if (result.success) {
        _comments.removeWhere(
          (item) => _sameCommentId(_commentIdFromJson(item), commentId),
        );
      }
    });
    final message = result.success
        ? '评论已删除'
        : (result.message?.isNotEmpty == true ? result.message! : '删除失败，请稍后重试');
    if (!context.mounted) return;
    AppToast.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    return EasyRefresh(
      onRefresh: () => _fetchComments(refresh: true),
      onLoad: () async {
        _page++;
        await _fetchComments(refresh: false);
        return _hasMore ? IndicatorResult.success : IndicatorResult.noMore;
      },
      child: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : _comments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded,
                          size: 54, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text(
                        widget.isOutbox ? '暂无发出的评论' : '暂无收到的评论',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _comments.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 64, thickness: 0.5),
                  itemBuilder: (context, index) {
                    final c = _comments[index];
                    final user = _mapValue(c['user']) ?? <String, dynamic>{};
                    final text = c['text_raw']?.toString() ?? c['text']?.toString() ?? '';
                    final nick = user['screen_name']?.toString() ?? '微博用户';
                    final avatar = user['avatar_hd']?.toString() ??
                        user['profile_image_url']?.toString() ??
                        '';
                    final createdAt = c['created_at']?.toString() ?? '';
                    final replyComment = _mapValue(c['reply_comment']) ??
                        _mapValue(c['replyComment']);
                    final rootStatus = _statusFromComment(c);
                    final commentId = _commentIdFromJson(c);
                    final isDeleting = _deletingCommentIds.contains(commentId);

                    return ListTile(
                      leading: AppAvatar(url: avatar, size: 40, name: nick),
                      title: Text(nick,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (createdAt.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              WeiboTimeFormatter.format(rawDate: createdAt),
                              style: TextStyle(fontSize: 12, color: colorScheme.outline),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text.rich(
                            TextSpan(
                              children: WeiboTextParser.parse(
                                rawText: text,
                                context: context,
                                defaultStyle: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                          if (replyComment != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '回复 @${replyComment['user']?['screen_name'] ?? ''}：${replyComment['text_raw'] ?? replyComment['text'] ?? ''}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: colorScheme.outline),
                              ),
                            ),
                          ],
                          if (rootStatus != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '原微博：${rootStatus['text_raw'] ?? rootStatus['text'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: colorScheme.outline),
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: widget.isOutbox
                          ? OutlinedButton.icon(
                              onPressed: isDeleting || commentId.isEmpty
                                  ? null
                                  : () => _confirmDeleteComment(context, c),
                              icon: isDeleting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.delete_outline_rounded),
                              label: Text(isDeleting ? '删除中' : '删除'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.primary,
                                side: BorderSide(
                                  color: colorScheme.outline,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                minimumSize: const Size(0, 40),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            )
                          : null,
                      onTap: () => _openComment(context, c),
                    );
                  },
                ),
    );
  }
}
