import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/utils/weibo_text_parser.dart';
import '../../../core/utils/weibo_time_formatter.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../profile/presentation/user_profile_page.dart';
import 'group_info_page.dart';

/// 微博原生聊天会话页面 (支持群聊/私信、双向气泡、表情富文本、时间分割线与消息即时发送)
class ChatConversationPage extends ConsumerStatefulWidget {
  static final Map<String, Map<String, dynamic>> globalUserCache = {};

  final String targetId;
  final String targetName;
  final String targetAvatar;
  final bool isGroup;

  const ChatConversationPage({
    super.key,
    required this.targetId,
    required this.targetName,
    required this.targetAvatar,
    this.isGroup = false,
  });

  @override
  ConsumerState<ChatConversationPage> createState() => _ChatConversationPageState();
}

class _ChatConversationPageState extends ConsumerState<ChatConversationPage> {
  final List<Map<String, dynamic>> _messages = [];
  final Map<String, Map<String, dynamic>> _userCache = {};
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _userCache.addAll(ChatConversationPage.globalUserCache);
    _fetchMessages();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    setState(() => _isLoading = true);
    final client = ref.read(weiboDioClientProvider);
    final extracted = <Map<String, dynamic>>[];

    try {
      if (widget.isGroup) {
        // 1. 群聊消息接口
        final res = await client.dio.get(
          'https://api.weibo.com/webim/groupchat/query_messages.json',
          queryParameters: {
            'id': widget.targetId,
            'count': 40,
            'source': '209678993',
          },
        );
        if (res.data is Map<String, dynamic>) {
          final data = res.data as Map<String, dynamic>;
          final rawList = data['messages'] as List? ?? [];
          for (final item in rawList) {
            if (item is Map<String, dynamic>) {
              extracted.add(item);
            }
          }
        }
      } else {
        // 2. 单聊私信接口
        final res = await client.dio.get(
          'https://api.weibo.com/webim/2/direct_messages/conversation.json',
          queryParameters: {
            'uid': widget.targetId,
            'count': 40,
            'source': '209678993',
          },
        );
        if (res.data is Map<String, dynamic>) {
          final data = res.data as Map<String, dynamic>;
          final rawList = data['direct_messages'] as List? ?? [];
          for (final item in rawList) {
            if (item is Map<String, dynamic>) {
              extracted.add(item);
            }
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(extracted);
        _isLoading = false;
      });
      // 深度异步解析发言人头像与昵称
      _resolveMessageSenders(extracted);
    }
  }

  Future<void> _resolveMessageSenders(List<Map<String, dynamic>> msgs) async {
    final client = ref.read(weiboDioClientProvider);
    final uids = <String>{};

    for (final m in msgs) {
      final uid = widget.isGroup
          ? m['from_uid']?.toString()
          : m['sender_id']?.toString();
      if (uid != null && uid.isNotEmpty) {
        if (ChatConversationPage.globalUserCache.containsKey(uid)) {
          _userCache[uid] = ChatConversationPage.globalUserCache[uid]!;
        } else if (!_userCache.containsKey(uid)) {
          uids.add(uid);
        }
      }
    }

    if (uids.isEmpty) return;

    await Future.wait(
      uids.map((uid) async {
        try {
          final uRes = await client.dio.get(
            'https://api.weibo.com/webim/2/users/show.json',
            queryParameters: {'uid': uid, 'source': '209678993'},
          );
          if (uRes.data is Map<String, dynamic>) {
            final uData = uRes.data as Map<String, dynamic>;
            final entry = {
              'nick': uData['screen_name'] ?? uData['name'] ?? '群友',
              'avatar': uData['avatar_large'] ?? uData['profile_image_url'] ?? '',
            };
            ChatConversationPage.globalUserCache[uid] = entry;
            _userCache[uid] = entry;
          }
        } catch (_) {}
      }),
    );

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    final client = ref.read(weiboDioClientProvider);
    final authState = ref.read(authProvider);
    final myUid = authState.uid ?? 'me';

    _inputController.clear();

    // 1. 本地乐观回显
    final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final optimisticMsg = widget.isGroup
        ? <String, dynamic>{
            'from_uid': myUid,
            'content': text,
            'time': nowTs,
            'type': 1,
            'id': nowTs,
          }
        : <String, dynamic>{
            'sender_id': myUid,
            'text': text,
            'created_at': DateTime.now().toIso8601String(),
            'id': nowTs,
          };

    setState(() {
      _messages.insert(0, optimisticMsg);
    });

    // 2. 发送网络请求
    try {
      if (widget.isGroup) {
        await client.dio.post(
          'https://api.weibo.com/webim/groupchat/send_message.json',
          data: {
            'id': widget.targetId,
            'content': text,
            'source': '209678993',
          },
        );
      } else {
        await client.dio.post(
          'https://api.weibo.com/webim/2/direct_messages/new.json',
          data: {
            'uid': widget.targetId,
            'text': text,
            'source': '209678993',
          },
        );
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authState = ref.watch(authProvider);
    final myUid = authState.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            AppAvatar(url: widget.targetAvatar, size: 36, name: widget.targetName),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.targetName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.isGroup)
                    Text(
                      '群聊会话',
                      style: TextStyle(fontSize: 11, color: colorScheme.outline),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (widget.isGroup)
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded),
              tooltip: '群信息',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => GroupInfoPage(
                      groupId: widget.targetId,
                      initialGroupName: widget.targetName,
                      initialGroupAvatar: widget.targetAvatar,
                    ),
                  ),
                );
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.person_outline_rounded),
              tooltip: '用户主页',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => UserProfilePage(
                      uid: widget.targetId,
                      screenName: widget.targetName,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // 消息列表展示区
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 54,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35)),
                            const SizedBox(height: 12),
                            Text(
                              '暂无聊天消息，打个招呼吧',
                              style: TextStyle(
                                  color: colorScheme.onSurfaceVariant, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : EasyRefresh(
                        onRefresh: _fetchMessages,
                        child: ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            return _buildMessageItem(context, msg, myUid);
                          },
                        ),
                      ),
          ),

          const Divider(height: 1, thickness: 0.5),

          // 底部输入控制栏
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: colorScheme.surface,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TextField(
                        controller: _inputController,
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: const InputDecoration(
                          hintText: '发送消息...',
                          hintStyle: TextStyle(fontSize: 14.5),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sendMessage,
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(BuildContext context, Map<String, dynamic> msg, String myUid) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 提取字段
    final isGroup = widget.isGroup;
    final senderUid = isGroup
        ? (msg['from_uid']?.toString() ?? '')
        : (msg['sender_id']?.toString() ?? '');
    final text = isGroup ? (msg['content']?.toString() ?? '') : (msg['text']?.toString() ?? '');

    final isMe = senderUid == myUid || (senderUid.isNotEmpty && senderUid == 'me');
    final isSystemOrRecall = msg['type'] == 344 || text.contains('撤回了一条消息');

    // 撤回或系统通知气泡
    if (isSystemOrRecall) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          ),
        ),
      );
    }

    // 用户资料解析 (从缓存中提取真实微博昵称与头像)
    final memberCache = _userCache[senderUid];
    final senderNick = isMe
        ? '我'
        : (memberCache?['nick']?.toString() ??
            msg['sender_screen_name']?.toString() ??
            (isGroup ? '群友 $senderUid' : widget.targetName));
    final senderAvatar = isMe
        ? ''
        : (memberCache?['avatar']?.toString() ??
            (isGroup ? '' : widget.targetAvatar));

    // 时间显示
    final rawTime = msg['time']?.toString() ?? msg['created_at']?.toString() ?? '';
    String timeStr = '';
    if (rawTime.isNotEmpty) {
      if (int.tryParse(rawTime) != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch(int.parse(rawTime) * 1000);
        timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else {
        timeStr = WeiboTimeFormatter.format(rawDate: rawTime);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: () {
                if (senderUid.isNotEmpty) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => UserProfilePage(uid: senderUid, screenName: senderNick),
                    ),
                  );
                }
              },
              child: AppAvatar(url: senderAvatar, size: 38, name: senderNick),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (isGroup && !isMe) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Text(
                      senderNick,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colorScheme.outline,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: WeiboTextParser.parse(
                        rawText: text,
                        context: context,
                        defaultStyle: TextStyle(
                          fontSize: 14.5,
                          color: isMe ? Colors.white : colorScheme.onSurface,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
                if (timeStr.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      timeStr,
                      style: TextStyle(fontSize: 10, color: colorScheme.outline),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            AppAvatar(
              url: ref.watch(authProvider).avatar ?? '',
              size: 38,
              name: '我',
            ),
          ],
        ],
      ),
    );
  }
}
