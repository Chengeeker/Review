import 'dart:collection';

import 'detail_repository.dart';
import 'models/weibo_comment_model.dart';

/// A bounded, resumable scan: reply previews cannot prove author absence.
class AuthorCommentFilter {
  AuthorCommentFilter({
    required this.authorId,
    required this.includeReplies,
    required this.fetchRoots,
    required this.fetchReplies,
    required this.isCurrent,
  });

  final String authorId;
  final bool includeReplies;
  final Future<CommentResult> Function(String cursor) fetchRoots;
  final Future<CommentResult> Function(String id, String cursor) fetchReplies;
  final bool Function() isCurrent;
  final Queue<WeiboCommentModel> _pending = Queue();
  final Set<String> _seen = {};
  final Set<String> _rootCursors = {'0'};
  final Set<String> _replyCursors = {'0'};
  String _rootCursor = '0';
  String _replyCursor = '0';
  bool _moreRoots = true;
  int _batch = 0;

  bool _containsAuthor(WeiboCommentModel comment) =>
      comment.user.id == authorId || comment.subComments.any(_containsAuthor);

  void _finishRoot() {
    _pending.removeFirst();
    _replyCursor = '0';
    _replyCursors
      ..clear()
      ..add('0');
  }

  Future<CommentResult> next() async {
    final matches = <WeiboCommentModel>[];
    var requests = 0;
    while (isCurrent()) {
      if (_pending.isEmpty) {
        if (!_moreRoots || requests >= 4 || matches.isNotEmpty) break;
        final page = await fetchRoots(_rootCursor);
        requests++;
        if (!isCurrent()) break;
        _moreRoots = page.hasMore && _rootCursors.add(page.maxId);
        _rootCursor = page.maxId;
        _pending.addAll(page.comments.where((c) => _seen.add(c.id)));
        continue;
      }
      final root = _pending.first;
      if (root.user.id == authorId ||
          (includeReplies && _containsAuthor(root))) {
        matches.add(root);
        _finishRoot();
        continue;
      }
      if (!includeReplies ||
          (root.replyCountKnown &&
              root.subCommentsCount <= root.subComments.length)) {
        _finishRoot();
        continue;
      }
      if (requests >= 4 || matches.isNotEmpty) break;
      final page = await fetchReplies(root.id, _replyCursor);
      requests++;
      if (!isCurrent()) break;
      final found = page.comments.any(_containsAuthor);
      if (found || !page.hasMore || !_replyCursors.add(page.maxId)) {
        _finishRoot();
        if (found) matches.add(root);
      } else {
        _replyCursor = page.maxId;
      }
    }
    return CommentResult(
      comments: matches,
      maxId: '${++_batch}',
      hasMore: _pending.isNotEmpty || _moreRoots,
    );
  }
}
