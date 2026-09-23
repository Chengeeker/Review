import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/utils/weibo_time_formatter.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../auth/presentation/login_page.dart';
import '../data/message_unread_service.dart';
import 'chat_conversation_page.dart';
import 'likes_comments_page.dart';
import 'mentions_page.dart';

/// 我的消息 综合中心 (聚合 @我的、收到的赞、评论、原生私信会话与群聊)
class MyMessagesPage extends ConsumerStatefulWidget {
  const MyMessagesPage({super.key});

  @override
  ConsumerState<MyMessagesPage> createState() => _MyMessagesPageState();
}

class _MyMessagesPageState extends ConsumerState<MyMessagesPage> {
  final List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;
  bool _isClearingUnread = false;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _clearUnreadMessages() async {
    if (_isClearingUnread) return;
    HapticFeedbackUtil.light();
    final client = ref.read(weiboDioClientProvider);
    setState(() {
      _isClearingUnread = true;
      for (final c in _contacts) {
        c['unread'] = 0;
        c['unread_count'] = 0;
        c['badge'] = 0;
      }
    });

    // Persist local baselines before the remote requests so a contacts refresh
    // cannot bring the just-cleared counters back from a stale server response.
    await MessageUnreadService(ref.read(storageServiceProvider))
        .markCurrentAsRead(client.dio, _contacts);
    if (!mounted) return;

    // Ask Weibo to clear direct messages and the four notification sections.
    var remoteSuccess = false;
    try {
      Future<dynamic> safeRequest(Future<dynamic> request) async {
        try {
          return await request;
        } catch (_) {
          return null;
        }
      }

      final results = await Future.wait<dynamic>([
        safeRequest(client.dio.post(
          'https://api.weibo.com/webim/2/direct_messages/set_all_read.json',
          queryParameters: {'source': '209678993'},
        )),
        safeRequest(client.dio.get(
          'https://api.weibo.com/webim/2/direct_messages/clear_unread.json',
          queryParameters: {'source': '209678993'},
        )),
        safeRequest(client.dio.get(
          'https://weibo.com/ajax/message/clearUnread',
          queryParameters: {'type': 'all'},
        )),
      ]);
      remoteSuccess = results.any(_isClearResponseConfirmed);
    } catch (_) {}

    if (!mounted) return;
    setState(() => _isClearingUnread = false);
    AppToast.show(
      context,
      remoteSuccess ? '已清除未读消息' : '本地未读计数已清零，服务器未确认同步',
    );
  }

  bool _isClearResponseConfirmed(dynamic response) {
    final statusCode = response?.statusCode;
    if (statusCode is! int || statusCode < 200 || statusCode >= 300) {
      return false;
    }
    final data = response.data;
    if (data is Map) {
      if (data['error'] != null && data['error'].toString().isNotEmpty) {
        return false;
      }
      if (data['ok'] != null) {
        return data['ok'] == 1 || data['ok'] == '1' || data['ok'] == true;
      }
      if (data['code'] != null) {
        final code = data['code'].toString();
        return code == '0' || code == '100000';
      }
      return false;
    }
    return data == null || data == '';
  }

  Future<void> _fetchContacts() async {
    final authState = ref.read(authProvider);
    if (!authState.isLoggedIn) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    final client = ref.read(weiboDioClientProvider);
    final extracted = <Map<String, dynamic>>[];

    try {
      final res = await client.dio.get(
        'https://api.weibo.com/webim/2/direct_messages/contacts.json',
      );
      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        final rawList = data['contacts'] as List? ?? [];
        extracted.addAll(rawList.whereType<Map<String, dynamic>>());

        for (final c in extracted) {
          final u = c['user'] is Map ? c['user'] as Map<String, dynamic> : null;
          if (u != null) {
            final uid = u['id']?.toString() ?? u['idstr']?.toString() ?? '';
            final name =
                u['screen_name']?.toString() ?? u['name']?.toString() ?? '';
            final avatar = u['avatar_large']?.toString() ??
                u['profile_image_url']?.toString() ??
                '';
            if (uid.isNotEmpty) {
              ChatConversationPage.globalUserCache[uid] = {
                'nick': name,
                'avatar': avatar,
              };
            }
          }
        }
      }
    } catch (_) {}

    final displayContacts = await MessageUnreadService(
      ref.read(storageServiceProvider),
    ).applyContactUnreadBaselines(extracted);

    if (mounted) {
      setState(() {
        _contacts.clear();
        _contacts.addAll(displayContacts);
        _isLoading = false;
      });
    }
  }

  void _openNotificationPage(String category, Widget page) {
    // Mark the category as read independently of opening the page; this keeps
    // navigation immediate while persisting the local unread watermark.
    unawaited(
      MessageUnreadService(ref.read(storageServiceProvider)).markCategoryAsRead(
        ref.read(weiboDioClientProvider).dio,
        category,
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Future<void> _openConversation({
    required Map<String, dynamic> contact,
    required String id,
    required String name,
    required String avatar,
    required bool isGroup,
    required int unreadCount,
  }) async {
    if (unreadCount > 0 && id.isNotEmpty) {
      // Reflect the read immediately, then persist the raw server counter as
      // this conversation's baseline so a stale contacts response cannot
      // restore the badge after returning from the chat.
      setState(() => contact['unread_count'] = 0);
      await MessageUnreadService(ref.read(storageServiceProvider))
          .markContactAsRead(id, _contacts);
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatConversationPage(
          targetId: id,
          targetName: name,
          targetAvatar: avatar,
          isGroup: isGroup,
        ),
      ),
    );
    if (mounted) await _fetchContacts();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLoggedIn = authState.isLoggedIn;

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('我的消息', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: isLoggedIn
            ? [
                IconButton(
                  tooltip: '清除未读消息',
                  onPressed: _isClearingUnread ? null : _clearUnreadMessages,
                  icon: _isClearingUnread
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cleaning_services_rounded),
                ),
              ]
            : null,
      ),
      body: !isLoggedIn
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mail_outline_rounded,
                      size: 60,
                      color: colorScheme.primary.withValues(alpha: 0.6)),
                  const SizedBox(height: 16),
                  const Text('登录后即可同步查看您的消息与私信会话',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
            )
          : EasyRefresh(
              onRefresh: () => HapticFeedbackUtil.refresh(_fetchContacts),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  // 1. 顶部 4 个快捷通知功能卡片 (2x2 Grid)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '消息通知',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildQuickActionCard(
                                context,
                                icon: Icons.alternate_email_rounded,
                                iconColor: Colors.blue.shade600,
                                title: '@我的',
                                subtitle: '提及我的微博与评论',
                                onTap: () => _openNotificationPage(
                                  'mentions',
                                  const MentionsPage(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildQuickActionCard(
                                context,
                                icon: Icons.favorite_rounded,
                                iconColor: Colors.pink.shade500,
                                title: '收到的赞',
                                subtitle: '收到的点赞记录',
                                onTap: () => _openNotificationPage(
                                  'likes',
                                  const ReceivedLikesPage(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildQuickActionCard(
                                context,
                                icon: Icons.chat_bubble_outline_rounded,
                                iconColor: Colors.amber.shade700,
                                title: '发出的评论',
                                subtitle: '我发表的评论记录',
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (ctx) =>
                                          const SentCommentsPage(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildQuickActionCard(
                                context,
                                icon: Icons.forum_rounded,
                                iconColor: const Color(0xFF10B981),
                                title: '收到的评论',
                                subtitle: '与我互动的评论回复',
                                onTap: () => _openNotificationPage(
                                  'comments',
                                  const ReceivedCommentsPage(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Divider(height: 1, thickness: 0.5),
                  const SizedBox(height: 12),

                  // 2. 私信会话列表标题
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Row(
                          children: [
                            Text(
                              '私信与群聊',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 6),

                  // 3. 原生私信列表
                  if (_isLoading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: CircularProgressIndicator(
                            color: colorScheme.primary),
                      ),
                    )
                  else if (_contacts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 48,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.35)),
                            const SizedBox(height: 12),
                            Text(
                              '暂无私信会话',
                              style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _contacts.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72, thickness: 0.5),
                      itemBuilder: (context, index) {
                        final contact = _contacts[index];
                        final user = contact['user'] is Map
                            ? (contact['user'] as Map<String, dynamic>)
                            : <String, dynamic>{};
                        final message = contact['message'] is Map
                            ? (contact['message'] as Map<String, dynamic>)
                            : <String, dynamic>{};
                        final unreadCount = MessageUnreadService.readCount(
                            contact['unread_count']);
                        final sigMsgs =
                            contact['significant_msgs'] as List? ?? [];
                        final hasSpecialAt = sigMsgs.isNotEmpty;

                        final rawId = user['id']?.toString() ??
                            user['idstr']?.toString() ??
                            '';
                        final name = user['name']?.toString() ??
                            user['screen_name']?.toString() ??
                            '私信用户';
                        final isGroup =
                            MessageUnreadService.isGroupContact(contact);
                        // A stored mute ID comes from this group's info page,
                        // so use the exact conversation ID as the source of
                        // truth instead of depending on server group flags.
                        final isMuted = ref
                            .read(storageServiceProvider)
                            .isMessageGroupMuted(rawId);

                        final avatar = user['avatar_large']?.toString() ??
                            user['round_avatar_large']?.toString() ??
                            user['profile_image_url']?.toString() ??
                            '';
                        final lastText = message['text']?.toString() ?? '';
                        final createdAt =
                            message['created_at']?.toString() ?? '';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AppAvatar(url: avatar, size: 48, name: name),
                              if (unreadCount > 0)
                                Positioned(
                                  top: -2,
                                  right: -2,
                                  child: Container(
                                    key: ValueKey(
                                      'message-unread-badge-$rawId',
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: isMuted
                                          ? colorScheme.surfaceContainerHighest
                                          : Colors.red.shade600,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    constraints:
                                        const BoxConstraints(minWidth: 16),
                                    child: Text(
                                      unreadCount > 99 ? '99+' : '$unreadCount',
                                      style: TextStyle(
                                        color: isMuted
                                            ? colorScheme.onSurfaceVariant
                                            : Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (createdAt.isNotEmpty)
                                Text(
                                  WeiboTimeFormatter.format(rawDate: createdAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.outline,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                if (hasSpecialAt) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      '[有人@我]',
                                      style: TextStyle(
                                        color: Colors.orange.shade900,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                                Expanded(
                                  child: Text(
                                    lastText,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onTap: () => _openConversation(
                            contact: contact,
                            id: rawId,
                            name: name,
                            avatar: avatar,
                            isGroup: isGroup,
                            unreadCount: unreadCount,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildQuickActionCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.25),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
}
