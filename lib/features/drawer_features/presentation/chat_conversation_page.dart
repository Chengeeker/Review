import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:review/core/design_system/components/review_frosted_app_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/services/link_routing_service.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/utils/spring_page_route.dart';
import '../../../core/utils/weibo_text_parser.dart';
import '../../../core/utils/weibo_time_formatter.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/cached_network_image.dart';
import '../../detail/presentation/widgets/image_gallery_page.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../data/chat_message_media.dart';
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
  final Map<String, Map<String, dynamic>> _completeLinkMessages = {};
  final Map<String, Object> _imageHeroScopes = {};
  final Set<String> _requestedLinkMessages = {};
  final Map<String, Future<Map<String, dynamic>>> _videoMetadata = {};
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingOlder = false;
  bool _hasOlder = true;
  String? _oldestMessageId;
  bool _isSending = false;
  bool _isRefreshing = false;
  bool _olderLoadFailed = false;
  String? _loadError;
  int _historyGeneration = 0;

  @override
  void initState() {
    super.initState();
    _userCache.addAll(ChatConversationPage.globalUserCache);
    _scrollController.addListener(_maybeLoadOlder);
    _fetchMessages();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _requestMessages({String? before}) async {
    final client = ref.read(weiboDioClientProvider);
    final response = await client.dio.get(
      widget.isGroup
          ? 'https://api.weibo.com/webim/groupchat/query_messages.json'
          : 'https://api.weibo.com/webim/2/direct_messages/conversation.json',
      queryParameters: {
        if (widget.isGroup) 'id': widget.targetId else 'uid': widget.targetId,
        'count': _messagePageSize,
        'convert_emoji': 1,
        'source': '209678993',
        if (widget.isGroup) ...{
          'query_sender': 1,
          'max_mid': before ?? '0',
        } else if (before != null)
          'max_id': before,
      },
      options: Options(headers: {'Referer': 'https://api.weibo.com/chat/'}),
    );
    final data = _asMessageMap(response.data);
    final raw = data?[widget.isGroup ? 'messages' : 'direct_messages'];
    if (data == null ||
        raw is! List ||
        (data['error'] != null && data['error'].toString().isNotEmpty) ||
        (data.containsKey('error_code') &&
            data['error_code'].toString() != '0') ||
        data['ok'] == 0 ||
        data['result'] == false) {
      throw const FormatException('聊天记录响应无效');
    }
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  Future<void> _fetchMessages({bool showLoading = true}) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    final generation = ++_historyGeneration;
    setState(() {
      if (showLoading) _isLoading = true;
      _loadError = null;
      _isLoadingOlder = false;
    });
    try {
      final extracted = await _requestMessages();
      if (!mounted || generation != _historyGeneration) return;
      final seen = <String>{};
      final messages = [
        ...extracted,
        if (!showLoading) ..._messages,
      ].where((m) => seen.add(_messageKey(m))).toList();
      _sortMessagesNewestFirst(messages);
      setState(() {
        _messages
          ..clear()
          ..addAll(messages);
        _oldestMessageId = _messageId(_messages.lastOrNull);
        if (showLoading) _hasOlder = extracted.isNotEmpty;
        _olderLoadFailed = false;
        _isLoading = false;
      });
      if (showLoading) _scrollToLatest();
      unawaited(_resolveMessageSenders(extracted));
      _queueOlderPrefetch();
    } catch (_) {
      if (mounted && generation == _historyGeneration) {
        setState(() {
          _isLoading = false;
          _loadError = '聊天记录加载失败，请重试';
        });
      }
    } finally {
      _isRefreshing = false;
    }
  }

  void _maybeLoadOlder() {
    if (!_scrollController.hasClients || _olderLoadFailed || _isRefreshing) {
      return;
    }
    if (_scrollController.position.extentAfter <= 480) {
      unawaited(_fetchOlderMessages());
    }
  }

  void _queueOlderPrefetch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadOlder();
    });
  }

  Future<void> _fetchOlderMessages() async {
    if (_isLoading ||
        _isRefreshing ||
        _isLoadingOlder ||
        !_hasOlder ||
        _messages.isEmpty) {
      return;
    }
    final oldestId = _oldestMessageId;
    final numericId = BigInt.tryParse(oldestId ?? '');
    if (numericId == null || numericId <= BigInt.zero) {
      setState(() => _hasOlder = false);
      return;
    }
    final generation = _historyGeneration;
    setState(() {
      _isLoadingOlder = true;
      _olderLoadFailed = false;
    });
    try {
      // WebIM cursors are inclusive; request before the oldest loaded ID.
      final extracted = await _requestMessages(
        before: (numericId - BigInt.one).toString(),
      );
      if (!mounted || generation != _historyGeneration) return;
      final existing = _messages.map(_messageKey).toSet();
      final older = extracted.where((message) {
        final id = BigInt.tryParse(_messageId(message));
        return id != null &&
            id < numericId &&
            existing.add(_messageKey(message));
      }).toList();
      _sortMessagesNewestFirst(older);
      setState(() {
        // Reverse layout keeps existing bubbles fixed when old messages append.
        _messages.addAll(older);
        _oldestMessageId = _messageId(_messages.last);
        _hasOlder = older.isNotEmpty;
        _isLoadingOlder = false;
      });
      unawaited(_resolveMessageSenders(older));
      _queueOlderPrefetch();
    } catch (_) {
      if (mounted && generation == _historyGeneration) {
        setState(() {
          _isLoadingOlder = false;
          _olderLoadFailed = true;
        });
      }
    }
  }

  void _sortMessagesNewestFirst(List<Map<String, dynamic>> messages) {
    messages.sort((a, b) {
      final aTime = _messageTime(a);
      final bTime = _messageTime(b);
      if (aTime > 0 && bTime > 0 && aTime != bTime) {
        return bTime.compareTo(aTime);
      }
      final aId = BigInt.tryParse(_messageId(a)) ?? BigInt.zero;
      final bId = BigInt.tryParse(_messageId(b)) ?? BigInt.zero;
      return bId.compareTo(aId);
    });
  }

  int _messageTime(Map<String, dynamic>? message) {
    if (message == null) return 0;
    for (final key in const ['time', 'timestamp', 'created_at', 'createdAt']) {
      final value = message[key];
      final number = int.tryParse(value?.toString() ?? '');
      if (number != null) return number < 100000000000 ? number * 1000 : number;
      final parsed = WeiboTimeFormatter.parseWeiboDate(value?.toString() ?? '');
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return 0;
  }

  String _messageId(Map<String, dynamic>? message) =>
      (message?['idstr'] ?? message?['id'] ?? message?['mid'])
          ?.toString()
          .trim() ??
      '';

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
      final target = _scrollController.position.minScrollExtent;
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
      final sender = _asMessageMap(m[widget.isGroup ? 'from_user' : 'sender']);
      final uid =
          (m[widget.isGroup ? 'from_uid' : 'sender_id'] ??
                  sender?['idstr'] ??
                  sender?['id'])
              ?.toString();
      if (uid == null || uid.isEmpty) continue;
      final nick = sender?['screen_name'] ?? sender?['name'];
      if (nick != null) {
        ChatConversationPage.globalUserCache[uid] = {
          'nick': nick,
          'avatar':
              sender?['avatar_large'] ?? sender?['profile_image_url'] ?? '',
        };
      }
      if (ChatConversationPage.globalUserCache.containsKey(uid)) {
        _userCache[uid] = ChatConversationPage.globalUserCache[uid]!;
      } else if (!_userCache.containsKey(uid)) {
        uids.add(uid);
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
    final draft = _inputController.text;
    final text = draft.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    final client = ref.read(weiboDioClientProvider);
    final authState = ref.read(authProvider);
    final myUid = authState.uid ?? 'me';
    final sentAt = DateTime.now();
    final previousMessageKeys = _messages.map(_messageKey).toSet();

    // A successful HTTP status alone is not proof that Weibo accepted the
    // message. Do not render a synthetic outgoing bubble; verify the API
    // business response and then read the conversation back from the server.
    var requestAccepted = false;
    var sentMessageId = '';
    var failureMessage = '微博服务器未确认消息发送成功，内容已保留';
    try {
      final response = await client.dio.post(
        widget.isGroup
            ? 'https://api.weibo.com/webim/groupchat/send_message.json'
            : 'https://api.weibo.com/webim/2/direct_messages/new.json',
        data: {
          'source': '209678993',
          'is_encoded': 0,
          if (widget.isGroup) ...{
            'id': widget.targetId,
            'content': text,
            'media_type': 0,
            'setTimeout': 50,
            'annotations': jsonEncode({'webchat': 1, 'clientid': ''}),
          } else ...{
            'uid': widget.targetId,
            'text': text,
            'decodetime': 1,
            // No Comet connection is registered, as in the Web client's empty-id state.
            'extensions': jsonEncode({'clientid': ''}),
          },
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Referer': 'https://api.weibo.com/chat/',
            'Origin': 'https://api.weibo.com',
          },
        ),
      );
      requestAccepted =
          _isSuccessfulMessageResponse(response.data) &&
          response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
      sentMessageId = _messageId(_asMessageMap(response.data));
      failureMessage = _messageSendFailure(response.data, response.statusCode);
    } on DioException catch (error) {
      failureMessage = error.response == null
          ? '发送结果未确认，内容已保留；请先核实会话，避免重复发送'
          : _messageSendFailure(
              error.response?.data,
              error.response?.statusCode,
            );
    } catch (_) {
      failureMessage = '发送结果未确认，内容已保留；请先核实会话，避免重复发送';
    }

    if (!mounted) return;
    var confirmed = false;
    if (requestAccepted) {
      if (_inputController.text == draft) _inputController.clear();
      await _fetchMessages(showLoading: false);
      confirmed = _messages.any((message) {
        if (sentMessageId.isNotEmpty) {
          return _messageId(message) == sentMessageId;
        }
        final body = (message['content'] ?? message['text'] ?? '').toString();
        final sender =
            (message['from_uid'] ??
                    message['sender_id'] ??
                    message['user_id'] ??
                    _asMessageMap(message['sender'])?['id'] ??
                    '')
                .toString();
        return !previousMessageKeys.contains(_messageKey(message)) &&
            body == text &&
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
        _scrollToLatest(animated: true);
      } else if (requestAccepted) {
        AppToast.show(context, '服务器暂未回读到消息；请重新打开会话核实，避免重复发送');
      } else {
        AppToast.show(context, failureMessage);
      }
    }
  }

  String _messageSendFailure(dynamic response, int? statusCode) {
    final data = _asMessageMap(response);
    final error = data?['error']?.toString().trim() ?? '';
    if (error.isEmpty) {
      return statusCode != null && statusCode >= 400
          ? '发送请求失败（HTTP $statusCode），内容已保留'
          : '微博服务器未确认消息发送成功，内容已保留';
    }
    final code = data?['error_code']?.toString() ?? '';
    return code.isEmpty ? '发送失败：$error' : '发送失败：$error（$code）';
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
    for (final key in const ['id', 'idstr', 'mid', 'msg_id', 'message_id']) {
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
        if (_messageId(nested).isNotEmpty) return true;
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
      appBar: ReviewFrostedAppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            AppAvatar(
              url: widget.targetAvatar,
              size: 36,
              name: widget.targetName,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.targetName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.isGroup)
                    Text(
                      '群聊会话',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.outline,
                      ),
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
                    child: CircularProgressIndicator(
                      color: colorScheme.primary,
                    ),
                  )
                : _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 54,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.35,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _loadError ?? '暂无聊天消息，打个招呼吧',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                        if (_loadError != null)
                          TextButton(
                            onPressed: _fetchMessages,
                            child: const Text('重试'),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    itemCount: _messages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return _buildHistoryStatus();
                      }
                      final msg = _messages[index];
                      return KeyedSubtree(
                        key: ValueKey(_messageKey(msg)),
                        child: _buildMessageItem(context, msg, myUid),
                      );
                    },
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
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.55,
                        ),
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
                    onPressed: _isSending ? null : _sendMessage,
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
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

  Widget _buildHistoryStatus() => SizedBox(
    height: 48,
    child: Center(
      child: _isLoadingOlder
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : _olderLoadFailed
          ? TextButton(
              onPressed: _fetchOlderMessages,
              child: const Text('历史消息加载失败，点击重试'),
            )
          : !_hasOlder
          ? const Text('已到最早消息')
          : const SizedBox.shrink(),
    ),
  );

  Future<void> _completeLinkMessage(Map<String, dynamic> message) async {
    final id = _messageKey(message);
    if (!mounted) return;
    try {
      final response = await ref
          .read(weiboDioClientProvider)
          .dio
          .get(
            widget.isGroup
                ? 'https://api.weibo.com/webim/groupchat/query_message.json'
                : 'https://api.weibo.com/webim/2/direct_messages/show_batch.json',
            queryParameters: widget.isGroup
                ? {'id': widget.targetId, 'mid': id}
                : {'dmids': id, 'is_complete': 1, 'is_encoded': 0},
            options: Options(
              headers: {'Referer': 'https://api.weibo.com/chat/'},
            ),
          );
      final raw = response.data;
      final complete = widget.isGroup && raw is Map
          ? raw['message']
          : raw is List && raw.isNotEmpty
          ? raw.first
          : null;
      if (complete is! Map || !mounted) return;
      final merged = {...message, ...Map<String, dynamic>.from(complete)};
      if (ChatLinkPreview.fromMessage(merged) == null &&
          chatMessageImageUrls(merged).isEmpty) {
        return;
      }
      setState(() => _completeLinkMessages[id] = merged);
    } catch (_) {
      // Keep the original clickable URL if Weibo has no complete card response.
    }
  }

  Widget _buildLinkPreview(ChatLinkPreview card) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: '链接卡片：${card.title}',
      button: true,
      child: InkWell(
        onTap: () =>
            LinkRoutingService.openUrl(context, card.url, title: card.title),
        child: SizedBox(
          width: 260,
          child: Row(
            children: [
              if (card.imageUrl != null)
                CachedNetworkImage(
                  card.imageUrl!,
                  width: 52,
                  height: 52,
                  cacheWidth: (52 * MediaQuery.devicePixelRatioOf(context))
                      .round()
                      .clamp(1, 256),
                  fit: BoxFit.cover,
                  headers: ApiConstants.imageHeaders,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(Icons.link_rounded),
                  ),
                )
              else
                const SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(Icons.link_rounded),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      card.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    if (card.description.isNotEmpty)
                      Text(
                        card.description.replaceAll(RegExp(r'<[^>]*>'), ''),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _loadVideoMetadata(String fid) async {
    try {
      Future<Map<String, dynamic>> query(bool replace) async {
        final response = await ref
            .read(weiboDioClientProvider)
            .dio
            .get(
              'https://upload.api.weibo.com/2/mss/meta_query.json',
              queryParameters: {
                'source': '209678993',
                'fid': fid,
                'replace': '$replace',
                'callback': '__review_video_meta',
              },
              options: Options(
                responseType: ResponseType.plain,
                headers: {'Referer': 'https://api.weibo.com/chat/'},
              ),
            );
        return chatAttachmentMetadata(response.data);
      }

      final original = await query(false);
      if (original['extension']?.toString().toLowerCase() != 'mp4') {
        return original;
      }
      // WebIM resolves MP4 again with replace=true to obtain the playable fid.
      if (!mounted) return original;
      try {
        final playable = await query(true);
        return {...original, ...playable};
      } catch (_) {
        return original;
      }
    } catch (_) {
      return {};
    }
  }

  Widget _buildMessageVideo(Map<String, dynamic> message, String fid) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _videoMetadata.putIfAbsent(fid, () => _loadVideoMetadata(fid)),
      builder: (context, snapshot) {
        final pic = chatMessageVideo(message, fid, snapshot.data ?? {});
        if (pic == null) {
          if (message['media_type']?.toString() == '5' &&
              snapshot.data?['extension']?.toString().toLowerCase() != 'mp4') {
            return const SizedBox.shrink();
          }
          return Text(
            snapshot.data?['is_delete']?.toString() == '1' ||
                    snapshot.data?['is_delete'] == true
                ? '视频已失效或未通过审核'
                : snapshot.connectionState == ConnectionState.done
                ? '附件暂不可播放'
                : '正在加载附件…',
          );
        }
        final scope = _imageHeroScopes.putIfAbsent(
          '${_messageKey(message)}-video-$fid',
          Object.new,
        );
        final width = (MediaQuery.sizeOf(context).width * .6).clamp(1.0, 240.0);
        final height = pic.width > 0 && pic.height > 0
            ? (width * pic.height / pic.width).clamp(100.0, 300.0)
            : 160.0;
        return Semantics(
          label: '播放聊天视频',
          button: true,
          child: GestureDetector(
            onTap: snapshot.connectionState != ConnectionState.done
                ? null
                : () => _openChatGallery([pic], 0, scope, ''),
            child: ImageGalleryHeroThumbnail(
              scope: scope,
              index: 0,
              pic: pic,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.center,
                    children: [
                      const ColoredBox(color: Colors.black87),
                      if (pic.previewUrl.isNotEmpty)
                        CachedNetworkImage(
                          pic.previewUrl,
                          fit: BoxFit.contain,
                          cacheWidth:
                              (width * MediaQuery.devicePixelRatioOf(context))
                                  .round()
                                  .clamp(1, 1024),
                          headers: ref
                              .read(weiboDioClientProvider)
                              .imageHeadersForUrl(pic.previewUrl),
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openChatGallery(
    List<WeiboPicModel> pics,
    int initialIndex,
    Object scope,
    String statusId,
  ) {
    if (!mounted) return;
    HapticFeedbackUtil.light();
    PhysicsSpringGalleryRoute.openFromSource(
      context,
      PhysicsSpringGalleryRoute(
        child: ImageGalleryPage(
          pics: pics,
          initialIndex: initialIndex,
          statusId: statusId,
          heroScope: scope,
        ),
      ),
    );
  }

  Widget _buildMessageImage(
    String url,
    Map<String, dynamic> message,
    List<String> imageUrls,
    int index,
  ) {
    final messageId = _messageKey(message);
    final heroScope = _imageHeroScopes.putIfAbsent(messageId, Object.new);
    final pics = [
      for (var picIndex = 0; picIndex < imageUrls.length; picIndex++)
        WeiboPicModel(
          pid: '$messageId-$picIndex',
          thumbnail: imageUrls[picIndex],
          large: imageUrls[picIndex],
          original: imageUrls[picIndex],
        ),
    ];
    return Semantics(
      label: '查看聊天图片',
      button: true,
      child: GestureDetector(
        onTap: () => _openChatGallery(
          pics,
          index,
          heroScope,
          'chat-${widget.targetId}-$messageId',
        ),
        child: ImageGalleryHeroThumbnail(
          scope: heroScope,
          index: index,
          pic: pics[index],
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (MediaQuery.sizeOf(context).width * .6).clamp(
                  1.0,
                  240.0,
                ),
                maxHeight: 300,
              ),
              child: CachedNetworkImage(
                url,
                fit: BoxFit.contain,
                cacheWidth: (220 * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(1, 1024),
                headers: ref
                    .read(weiboDioClientProvider)
                    .imageHeadersForUrl(url),
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 180,
                  height: 100,
                  child: Center(child: Text('图片加载失败，点击重试')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageItem(
    BuildContext context,
    Map<String, dynamic> msg,
    String myUid,
  ) {
    final id = _messageKey(msg);
    msg = _completeLinkMessages[id] ?? msg;
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

    final imageUrls = chatMessageImageUrls(msg);
    final videoIds = chatMessageVideoIds(msg);
    final card = imageUrls.isEmpty && videoIds.isEmpty
        ? ChatLinkPreview.fromMessage(msg)
        : null;
    if (card == null &&
        imageUrls.isEmpty &&
        id.isNotEmpty &&
        RegExp(r'^https?://\S+$').hasMatch(text.trim()) &&
        _requestedLinkMessages.add(id)) {
      final message = msg;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_completeLinkMessage(message));
      });
    }
    final caption = chatMessageCaption(
      text,
      hasImages: imageUrls.isNotEmpty,
      hasVideo: videoIds.isNotEmpty,
    );
    final displayText =
        card != null &&
            (text.trim() == card.url ||
                text.trim() == msg['url_short'] ||
                RegExp(r'^https?://\S+$').hasMatch(text.trim()))
        ? ''
        : caption;
    final mediaOnly =
        (imageUrls.isNotEmpty || videoIds.isNotEmpty) && displayText.isEmpty;

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
        final dt = DateTime.fromMillisecondsSinceEpoch(
          int.parse(rawTime) * 1000,
        );
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
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: senderUid.isEmpty
                  ? null
                  : () {
                      HapticFeedbackUtil.light();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => UserProfilePage(
                            uid: senderUid,
                            screenName: senderNick,
                          ),
                        ),
                      );
                    },
              child: AppAvatar(url: senderAvatar, size: 38, name: senderNick),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
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
                  key: ValueKey('chat-message-content-${_messageKey(msg)}'),
                  padding: mediaOnly
                      ? const EdgeInsets.all(4)
                      : const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                  decoration: BoxDecoration(
                    color: mediaOnly
                        ? Colors.transparent
                        : card != null
                        ? colorScheme.surfaceContainerLow
                        : isMe
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.7,
                          ),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < imageUrls.length; index++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: displayText.isNotEmpty ? 8 : 0,
                          ),
                          child: _buildMessageImage(
                            imageUrls[index],
                            msg,
                            imageUrls,
                            index,
                          ),
                        ),
                      if (card != null) _buildLinkPreview(card),
                      for (final fid in videoIds) _buildMessageVideo(msg, fid),
                      if (displayText.isNotEmpty ||
                          (imageUrls.isEmpty &&
                              videoIds.isEmpty &&
                              card == null))
                        Text.rich(
                          TextSpan(
                            children: WeiboTextParser.parse(
                              rawText: displayText,
                              context: context,
                              defaultStyle: TextStyle(
                                fontSize: 14.5,
                                color: isMe
                                    ? Colors.white
                                    : colorScheme.onSurface,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (timeStr.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.outline,
                      ),
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
