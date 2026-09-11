import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../core/utils/app_toast.dart';
import '../../../../core/utils/haptic_feedback_util.dart';
import '../../../auth/presentation/login_page.dart';
import '../../../compose/presentation/widgets/weibo_emoji_keyboard.dart';
import '../../data/detail_repository.dart';
import '../../data/models/weibo_comment_model.dart';

/// Interactive Comment & Reply Bottom Sheet with Emoji Keyboard
class CommentBottomSheet extends ConsumerStatefulWidget {
  final String statusId;
  final WeiboCommentModel? replyToComment;
  final VoidCallback onCommentSuccess;

  const CommentBottomSheet({
    super.key,
    required this.statusId,
    this.replyToComment,
    required this.onCommentSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required String statusId,
    WeiboCommentModel? replyToComment,
    required VoidCallback onCommentSuccess,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CommentBottomSheet(
        statusId: statusId,
        replyToComment: replyToComment,
        onCommentSuccess: onCommentSuccess,
      ),
    );
  }

  @override
  ConsumerState<CommentBottomSheet> createState() => _CommentBottomSheetState();
}

class _CommentBottomSheetState extends ConsumerState<CommentBottomSheet> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _showEmoji = false;
  bool _isSending = false;

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onEmojiSelected(String phrase) {
    HapticFeedbackUtil.light();
    final text = _textController.text;
    final selection = _textController.selection;
    if (selection.start >= 0 && selection.end >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, phrase);
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + phrase.length),
      );
    } else {
      _textController.text += phrase;
    }
  }

  void _onBackspace() {
    HapticFeedbackUtil.light();
    final text = _textController.text;
    final selection = _textController.selection;
    if (text.isEmpty) return;

    if (selection.start > 0) {
      // Check if ends with [xxx] emoji
      final sub = text.substring(0, selection.start);
      final emojiMatch = RegExp(r'\[[a-zA-Z0-9\u4e00-\u9fa5]+\]$').firstMatch(sub);
      if (emojiMatch != null) {
        final start = emojiMatch.start;
        final newText = text.replaceRange(start, selection.start, '');
        _textController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: start),
        );
        return;
      }

      final newText = text.replaceRange(selection.start - 1, selection.start, '');
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start - 1),
      );
    }
  }

  Future<void> _submitComment() async {
    final content = _textController.text.trim();
    if (content.isEmpty) {
      AppToast.show(context, '请输入评论内容');
      return;
    }

    final authState = ref.read(authProvider);
    if (!authState.isLoggedIn) {
      final loginSuccess = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (loginSuccess != true) return;
    }

    setState(() => _isSending = true);

    bool success = false;
    String? errorMsg;
    if (widget.replyToComment == null) {
      // Direct Comment to Status
      final result = await ref.read(detailRepositoryProvider).sendComment(
            id: widget.statusId,
            content: content,
          );
      success = result.success;
      errorMsg = result.message;
    } else {
      // Reply to Comment
      final result = await ref.read(detailRepositoryProvider).replyComment(
            statusId: widget.statusId,
            commentId: widget.replyToComment!.id,
            content: content,
          );
      success = result.success;
      errorMsg = result.message;
    }

    setState(() => _isSending = false);

    if (mounted) {
      if (success) {
        Navigator.of(context).pop();
        AppToast.show(context, widget.replyToComment == null ? '评论发表成功！' : '回复发表成功！');
        widget.onCommentSuccess();
      } else {
        AppToast.show(context, errorMsg?.isNotEmpty == true ? errorMsg! : '发送失败，请检查登录状态与网络后重试');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isReply = widget.replyToComment != null;
    final replyTargetName = isReply ? widget.replyToComment!.user.screenName : '';

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isReply ? '回复 @$replyTargetName' : '发表评论',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Input Text Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              maxLines: 4,
              minLines: 2,
              autofocus: true,
              style: TextStyle(fontSize: 15, color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: isReply ? '回复 @$replyTargetName...' : '写下你的友善评论...',
                hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              onTap: () {
                if (_showEmoji) {
                  setState(() => _showEmoji = false);
                }
              },
            ),
          ),

          // Action Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _showEmoji ? Icons.keyboard_rounded : Icons.sentiment_satisfied_alt_rounded,
                    color: _showEmoji ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                  tooltip: _showEmoji ? '切换键盘' : '插入表情',
                  onPressed: () {
                    HapticFeedbackUtil.light();
                    setState(() {
                      _showEmoji = !_showEmoji;
                      if (_showEmoji) {
                        _focusNode.unfocus();
                      } else {
                        _focusNode.requestFocus();
                      }
                    });
                  },
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _isSending ? null : _submitComment,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: _isSending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('发送', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

          // Emoji Keyboard View
          if (_showEmoji)
            WeiboEmojiKeyboard(
              onEmojiSelected: _onEmojiSelected,
              onBackspace: _onBackspace,
            ),
        ],
      ),
    );
  }
}
