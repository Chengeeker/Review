import 'package:flutter_test/flutter_test.dart';
import 'package:review/features/detail/data/author_comment_filter.dart';
import 'package:review/features/detail/data/detail_repository.dart';
import 'package:review/features/detail/data/models/weibo_comment_model.dart';

WeiboCommentModel comment(
  String id,
  String uid, {
  int? count = 0,
  List<WeiboCommentModel> replies = const [],
}) => WeiboCommentModel.fromJson({
  'id': id,
  'user': {'id': uid, 'screen_name': uid},
  if (count != null) 'total_number': count,
  'comments': [
    for (final r in replies)
      {
        'id': r.id,
        'user': {'id': r.user.id, 'screen_name': r.user.id},
      },
  ],
});

void main() {
  test('only author excludes threads merely replied to by author', () async {
    final scan = AuthorCommentFilter(
      authorId: 'owner',
      includeReplies: false,
      isCurrent: () => true,
      fetchRoots: (_) async => CommentResult(
        comments: [
          comment('1', 'owner'),
          comment('2', 'other', replies: [comment('3', 'owner')]),
        ],
        hasMore: false,
      ),
      fetchReplies: (_, _) => throw StateError('must not fetch replies'),
    );
    final result = await scan.next();
    expect(result.comments.map((c) => c.id), ['1']);
    expect(result.hasMore, isFalse);
  });

  test(
    'includes original thread when author is beyond inline preview',
    () async {
      var calls = 0;
      final scan = AuthorCommentFilter(
        authorId: 'owner',
        includeReplies: true,
        isCurrent: () => true,
        fetchRoots: (_) async => CommentResult(
          comments: [
            comment(
              'root',
              'other',
              count: 30,
              replies: [comment('preview', 'other')],
            ),
          ],
          hasMore: false,
        ),
        fetchReplies: (_, cursor) async {
          calls++;
          return cursor == '0'
              ? CommentResult(comments: [comment('a', 'other')], maxId: 'next')
              : CommentResult(
                  comments: [comment('b', 'owner')],
                  hasMore: false,
                );
        },
      );
      final result = await scan.next();
      expect(result.comments.single.id, 'root');
      expect(calls, 2);
      expect(result.hasMore, isFalse);
    },
  );

  test(
    'large thread continues across bounded batches without skipping replies',
    () async {
      var calls = 0;
      final scan = AuthorCommentFilter(
        authorId: 'owner',
        includeReplies: true,
        isCurrent: () => true,
        fetchRoots: (_) async => CommentResult(
          comments: [comment('root', 'other', count: 100)],
          hasMore: false,
        ),
        fetchReplies: (_, cursor) async {
          calls++;
          return CommentResult(
            comments: [comment('r$calls', calls == 6 ? 'owner' : 'other')],
            maxId: '$calls',
            hasMore: calls < 6,
          );
        },
      );
      final first = await scan.next();
      expect(first.comments, isEmpty);
      expect(first.hasMore, isTrue);
      expect(calls, 3); // root request plus three reply requests
      final second = await scan.next();
      expect(second.comments.single.id, 'root');
      expect(second.hasMore, isFalse);
    },
  );

  test(
    'missing reply count is not mistaken for a complete empty preview',
    () async {
      final scan = AuthorCommentFilter(
        authorId: 'owner',
        includeReplies: true,
        isCurrent: () => true,
        fetchRoots: (_) async => CommentResult(
          comments: [comment('root', 'other', count: null)],
          hasMore: false,
        ),
        fetchReplies: (_, _) async => CommentResult(
          comments: [comment('reply', 'owner')],
          hasMore: false,
        ),
      );
      expect((await scan.next()).comments.single.id, 'root');
    },
  );

  test('failed reply page remains retryable at the same cursor', () async {
    var fail = true;
    final cursors = <String>[];
    final scan = AuthorCommentFilter(
      authorId: 'owner',
      includeReplies: true,
      isCurrent: () => true,
      fetchRoots: (_) async => CommentResult(
        comments: [comment('root', 'other', count: 10)],
        hasMore: false,
      ),
      fetchReplies: (_, cursor) async {
        cursors.add(cursor);
        if (fail) {
          fail = false;
          throw StateError('offline');
        }
        return CommentResult(
          comments: [comment('reply', 'owner')],
          hasMore: false,
        );
      },
    );
    await expectLater(scan.next(), throwsStateError);
    expect((await scan.next()).comments.single.id, 'root');
    expect(cursors, ['0', '0']);
  });
}
