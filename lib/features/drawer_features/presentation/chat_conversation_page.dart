import 'package:easy_refresh/easy_refresh.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/utils/weibo_text_parser.dart';
import '../../../core/utils/weibo_time_formatter.dart';
import '../../../core/utils/app_toast.dart';
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
  ConsumerState<ChatConversationPage> createState() =>
      _ChatConversationPageState();
}

class _ChatConversationPageState extends ConsumerState<ChatConversationPage> {
  static const _messagePageSize = 40;

  final List<Map<String, dynamic>> _messages = [];
  final Map<String, Map<String, dynamic>> _userCache = {};
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingOlder = false;
  bool _hasOlder = true;
  String? _oldestMessageId;
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

  Future<void> _fetchMessages({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    final client = ref.read(weiboDioClientProvider);
    final extracted = <Map<String, dynamic>>[];

    try {
      if (widget.isGroup) {
        // 1. 群聊消息接口
        final res = await client.dio.get(
          'https://api.weibo.com/webim/groupchat/query_messages.json',
          queryParameters: {
            'id': widget.targetId,
            'count': _messagePageSize,
            'convert_emoji': 1,
            'query_sender': 1,
            'max_mid': 0,
            'source': '209678993',
          },
          options: Options(
            headers: {'Referer': 'https://api.weibo.com/chat'},
          ),
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

    if (widget.isGroup) {
      _sortMessagesChronologically(extracted);
    }

    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(extracted);
        if (widget.isGroup) {
          _oldestMessageId =
              _messageId(extracted.isEmpty ? null : extracted.first);
          _hasOlder = extracted.length >= _messagePageSize;
        }
        _isLoading = false;
      });
      if (widget.isGroup) _scrollToLatest();
      // 深度异步解析发言人头像与昵称
      _resolveMessageSenders(extracted);
    }
  }

  Future<void> _fetchOlderMessages() async {
    if (!widget.isGroup ||
        _isLoading ||
        _isLoadingOlder ||
        !_hasOlder ||
        _messages.isEmpty) {
      return;
    }

    final maxMid = _oldestMessageId;
    if (maxMid == null || maxMid.isEmpty) {
      if (mounted) setState(() => _hasOlder = false);
      return;
    }

    setState(() => _isLoadingOlder = true);
    final client = ref.read(weiboDioClientProvider);
    final previousOldest = _messages.first;
    final extracted = <Map<String, dynamic>>[];
    var requestSucceeded = false;

    try {
      final res = await client.dio.get(
        'https://api.weibo.com/webim/groupchat/query_messages.json',
        queryParameters: {
          'id': widget.targetId,
          'count': _messagePageSize,
          'convert_emoji': 1,
          'query_sender': 1,
          'max_mid': maxMid,
          'source': '209678993',
        },
        options: Options(
          headers: {'Referer': 'https://api.weibo.com/chat'},
        ),
      );
      requestSucceeded = true;
      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        final rawList = data['messages'] as List? ?? [];
        for (final item in rawList) {
          if (item is Map<String, dynamic>) extracted.add(item);
        }
      }
    } catch (_) {}

    if (!mounted) return;

    if (!requestSucceeded) {
      setState(() => _isLoadingOlder = false);
      return;
    }

    _sortMessagesChronologically(extracted);
    final existingKeys = _messages.map(_messageKey).toSet();
    final newMessages = extracted
        .where((message) => existingKeys.add(_messageKey(message)))
        .toList();
    final pageAdvanced = extracted.isNotEmpty &&
        _compareMessages(extracted.first, previousOldest) < 0;

    setState(() {
      _messages.insertAll(0, newMessages);
      _oldestMessageId = _messageId(_messages.first);
      _hasOlder = pageAdvanced && extracted.length >= _messagePageSize;
      _isLoadingOlder = false;
    });
    _resolveMessageSenders(newMessages);
  }

  void _sortMessagesChronologically(List<Map<String, dynamic>> messages) {
    messages.sort(_compareMessages);
  }

  int _compareMessages(Map<String, dynamic> a, Map<String, dynamic> b) {
    final timeCompare = _messageTime(a).compareTo(_messageTime(b));
    if (timeCompare != 0) return timeCompare;
    return _numericMessageId(a).compareTo(_numericMessageId(b));
  }

  int _messageTime(Map<String, dynamic>? message) {
    if (message == null) return 0;
    for (final key in const ['time', 'timestamp', 'created_at', 'createdAt']) {
      final value = message[key];
      if (value is num) {
        final number = value.toInt();
        return number < 100000000000 ? number * 1000 : number;
      }
      final parsed = DateTime.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return _numericMessageId(message);
  }

  int _numericMessageId(Map<String, dynamic>? message) =>
      int.tryParse(message?['id']?.toString() ?? '') ?? 0;

  String _messageId(Map<String, dynamic>? message) =>
      message?['id']?.toString().trim() ?? '';

  String _messageKey(Map<String, dynamic> message) {
    final id = _messageId(message);
    if (id.isNotEmpty) return id;
    return [
      message['from_uid'] ?? message['sender_id'] ?? '',
      message['time'] ?? message['created_at'] ?? '',
      message['content'] ?? message['text'] ?? '',
    ].join('|');
  }

  void _scrollToLatest({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
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
              'avatar':
                  uData['avatar_large'] ?? uData['profile_image_url'] ?? '',
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
    final sentAt = DateTime.now();
    _inputController.clear();

    // A successful HTTP status alone is not proof that Weibo accepted the
    // message. Do not render a synthetic outgoing bubble; verify the API
    // business response and then read the conversation back from the server.
    var requestAccepted = false;
    try {
      if (widget.isGroup) {
        final response = await client.dio.post(
          'https://api.weibo.com/webim/groupchat/send_message.json',
          data: {
            'id': widget.targetId,
            'content': text,
            'source': '209678993',
          },
        );
        requestAccepted = _isSuccessfulMessageResponse(response.data) &&
            response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 300;
      } else {
        final response = await client.dio.post(
          'https://api.weibo.com/webim/2/direct_messages/new.json',
          data: {
            'uid': widget.targetId,
            'text': text,
            'source': '209678993',
          },
        );
        requestAccepted = _isSuccessfulMessageResponse(response.data) &&
            response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 300;
      }
    } catch (_) {}

    var confirmed = false;
    if (requestAccepted) {
      await _fetchMessages(showLoading: false);
      confirmed = _messages.any((message) {
        final body = (message['content'] ?? message['text'] ?? '').toString();
        final sender = (message['from_uid'] ??
                message['sender_id'] ??
                message['user_id'] ??
                _asMessageMap(message['sender'])?['id'] ??
                '')
            .toString();
        return body == text &&
            sender == myUid &&
            _messageTime(message) >=
                sentAt
                    .subtract(const Duration(minutes: 1))
                    .millisecondsSinceEpoch;
      });
    }

    if (mounted) {
      setState(() => _isSending = false);
      if (confirmed) {
        if (widget.isGroup) _scrollToLatest(animated: true);
      } else if (requestAccepted) {
        AppToast.show(context, '接口已接受请求，但服务器暂未回读到消息；请先刷新核实，避免重复发送');
      } else {
        AppToast.show(context, '微博服务器未确认消息发送成功');
      }
    }
  }

  bool _isSuccessfulMessageResponse(dynamic response) {
    final data = _asMessageMap(response);
    if (data == null || data.isEmpty) return false;
    if (data['error'] != null && data['error'].toString().isNotEmpty) {
      return false;
    }
    if (data.containsKey('error_code') &&
        data['error_code']?.toString() != '0') {
      return false;
    }
    if (data.containsKey('ok')) {
      final ok = data['ok'];
      return ok == 1 || ok == '1' || ok == true;
    }
    if (data.containsKey('code')) {
      final code = data['code']?.toString();
      if (code != '0' && code != '100000') return false;
      return true;
    }
    for (final key in const ['id', 'idstr', 'msg_id', 'message_id']) {
      if (data[key] != null) return true;
    }
    for (final key in const ['message', 'direct_message', 'data']) {
      final nested = _asMessageMap(data[key]);
      if (nested != null && nested.isNotEmpty) {
        if ((nested['error'] != null &&
                nested['error'].toString().isNotEmpty) ||
            (nested.containsKey('error_code') &&
                nested['error_code']?.toString() != '0')) {
          return false;
        }
        if (nested['ok'] == 1 || nested['ok'] == '1' || nested['ok'] == true) {
          return true;
        }
        if (nested['id'] != null || nested['idstr'] != null) return true;
      }
    }
    return false;
  }

  Map<String, dynamic>? _asMessageMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
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
            AppAvatar(
                url: widget.targetAvatar, size: 36, name: widget.targetName),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.targetName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.isGroup)
                    Text(
                      '群聊会话',
                      style:
                          TextStyle(fontSize: 11, color: colorScheme.outline),
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
                ? Center(
                    child:
                        CircularProgressIndicator(color: colorScheme.primary))
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 54,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.35)),
                            const SizedBox(height: 12),
                            Text(
                              '暂无聊天消息，打个招呼吧',
                              style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : EasyRefresh(
                        onRefresh: () => HapticFeedbackUtil.refresh(
                          widget.isGroup ? _fetchOlderMessages : _fetchMessages,
                        ),
                        child: ListView.builder(
                          controller: _scrollController,
                          reverse: !widget.isGroup,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
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
                        color: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.55),
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
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
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

  Widget _buildMessageItem(
      BuildContext context, Map<String, dynamic> msg, String myUid) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 提取字段
    final isGroup = widget.isGroup;
    final senderUid = isGroup
        ? (msg['from_uid']?.toString() ?? '')
        : (msg['sender_id']?.toString() ?? '');
    final text = isGroup
        ? (msg['content']?.toString() ?? '')
        : (msg['text']?.toString() ?? '');

    final isMe =
        senderUid == myUid || (senderUid.isNotEmpty && senderUid == 'me');
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
    final rawTime =
        msg['time']?.toString() ?? msg['created_at']?.toString() ?? '';
    String timeStr = '';
    if (rawTime.isNotEmpty) {
      if (int.tryParse(rawTime) != null) {
        final dt =
            DateTime.fromMillisecondsSinceEpoch(int.parse(rawTime) * 1000);
        timeStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else {
        timeStr = WeiboTimeFormatter.format(rawDate: rawTime);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: () {
                if (senderUid.isNotEmpty) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => UserProfilePage(
                          uid: senderUid, screenName: senderNick),
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
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.7),
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
                      style:
                          TextStyle(fontSize: 10, color: colorScheme.outline),
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
