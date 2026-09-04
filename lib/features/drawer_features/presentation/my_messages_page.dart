import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/utils/weibo_time_formatter.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../auth/presentation/login_page.dart';
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
  int _totalContacts = 0;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _clearUnreadMessages() async {
    HapticFeedbackUtil.light();
    final client = ref.read(weiboDioClientProvider);

    // 1. 本地乐观清除全部未读标记
    setState(() {
      for (final c in _contacts) {
        c['unread'] = 0;
        c['unread_count'] = 0;
        c['badge'] = 0;
      }
    });

    // 2. 异步调用微博多重未读清除接口
    try {
      await Future.wait([
        client.dio.post(
          'https://api.weibo.com/webim/2/direct_messages/set_all_read.json',
          queryParameters: {'source': '209678993'},
        ).then<dynamic>((v) => v).catchError((_) => null),
        client.dio.get(
          'https://api.weibo.com/webim/2/direct_messages/clear_unread.json',
          queryParameters: {'source': '209678993'},
        ).then<dynamic>((v) => v).catchError((_) => null),
        client.dio.get(
          'https://weibo.com/ajax/message/clearUnread',
          queryParameters: {'type': 'all'},
        ).then<dynamic>((v) => v).catchError((_) => null),
      ]);
    } catch (_) {}

    if (mounted) {
      AppToast.show(context, '已清除未读信息');
    }
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
    int total = 0;

    try {
      final res = await client.dio.get(
        'https://api.weibo.com/webim/2/direct_messages/contacts.json',
      );
      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        total = data['totalNumber'] is int ? data['totalNumber'] as int : 0;
        final rawList = data['contacts'] as List? ?? [];
        extracted.addAll(rawList.whereType<Map<String, dynamic>>());

        for (final c in extracted) {
          final u = c['user'] is Map ? c['user'] as Map<String, dynamic> : null;
          if (u != null) {
            final uid = u['id']?.toString() ?? u['idstr']?.toString() ?? '';
            final name = u['screen_name']?.toString() ?? u['name']?.toString() ?? '';
            final avatar = u['avatar_large']?.toString() ?? u['profile_image_url']?.toString() ?? '';
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

    if (mounted) {
      setState(() {
        _contacts.clear();
        _contacts.addAll(extracted);
        _totalContacts = total > 0 ? total : _contacts.length;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLoggedIn = authState.isLoggedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的消息', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: !isLoggedIn
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mail_outline_rounded,
                      size: 60, color: colorScheme.primary.withValues(alpha: 0.6)),
                  const SizedBox(height: 16),
                  const Text('登录后即可同步查看您的消息与私信会话',
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
            )
          : EasyRefresh(
              onRefresh: _fetchContacts,
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
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (ctx) => const MentionsPage()),
                                  );
                                },
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
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (ctx) => const ReceivedLikesPage(),
                                    ),
                                  );
                                },
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
                                      builder: (ctx) => const SentCommentsPage(),
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
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (ctx) => const ReceivedCommentsPage(),
                                    ),
                                  );
                                },
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

                  // 2. 私信会话列表标题与清除未读信息按钮
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              '私信与群聊',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_totalContacts > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$_totalContacts',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: _clearUnreadMessages,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cleaning_services_rounded,
                                  size: 15,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '清除未读信息',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                        child: CircularProgressIndicator(color: colorScheme.primary),
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
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35)),
                            const SizedBox(height: 12),
                            Text(
                              '暂无私信会话',
                              style: TextStyle(
                                  color: colorScheme.onSurfaceVariant, fontSize: 14),
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
                        final unreadCount = contact['unread_count'] is int
                            ? contact['unread_count'] as int
                            : 0;
                        final sigMsgs = contact['significant_msgs'] as List? ?? [];
                        final hasSpecialAt = sigMsgs.isNotEmpty;

                        final rawId = user['id']?.toString() ?? '';
                        final name = user['name']?.toString() ??
                            user['screen_name']?.toString() ??
                            '私信用户';
                        final isGroup = contact['is_group'] == true ||
                            rawId.length > 12 ||
                            name.contains('群') ||
                            name.contains('交流');

                        final avatar = user['avatar_large']?.toString() ??
                            user['round_avatar_large']?.toString() ??
                            user['profile_image_url']?.toString() ??
                            '';
                        final lastText = message['text']?.toString() ?? '';
                        final createdAt = message['created_at']?.toString() ?? '';

                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AppAvatar(url: avatar, size: 48, name: name),
                              if (unreadCount > 0)
                                Positioned(
                                  top: -2,
                                  right: -2,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade600,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    constraints: const BoxConstraints(minWidth: 16),
                                    child: Text(
                                      unreadCount > 99 ? '99+' : '$unreadCount',
                                      style: const TextStyle(
                                        color: Colors.white,
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
                          onTap: () {
                            // 直接进入微博原生聊天界面！
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (ctx) => ChatConversationPage(
                                  targetId: rawId,
                                  targetName: name,
                                  targetAvatar: avatar,
                                  isGroup: isGroup,
                                ),
                              ),
                            );
                          },
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
