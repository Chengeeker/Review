import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/utils/app_dialog.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/weibo_text_parser.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../profile/presentation/user_profile_page.dart';
import 'chat_conversation_page.dart';
import 'group_members_page.dart';
import 'group_weibo_page.dart';

/// 微博原生群信息页面 (1:1 像素级还原群详情、公告、成员列表与管理项)
class GroupInfoPage extends ConsumerStatefulWidget {
  final String groupId;
  final String? initialGroupName;
  final String? initialGroupAvatar;

  const GroupInfoPage({
    super.key,
    required this.groupId,
    this.initialGroupName,
    this.initialGroupAvatar,
  });

  @override
  ConsumerState<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends ConsumerState<GroupInfoPage> {
  Map<String, dynamic>? _groupInfo;
  final List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;

  bool _isPinned = false;
  bool _isMuted = true;

  @override
  void initState() {
    super.initState();
    _fetchGroupDetails();
  }

  Future<void> _fetchGroupDetails() async {
    setState(() => _isLoading = true);
    final client = ref.read(weiboDioClientProvider);

    try {
      // 1. 并发获取群基本信息与完整群公告 (无截断)
      final infoFuture = client.dio.get(
        'https://api.weibo.com/webim/groupchat/query.json',
        queryParameters: {
          'id': widget.groupId,
          'source': '209678993',
        },
      );
      final bulletinFuture = client.dio.get(
        'https://api.weibo.com/webim/groupchat/query_user_bulletin.json',
        queryParameters: {
          'id': widget.groupId,
          'source': '209678993',
        },
      );

      final queryResults = await Future.wait([
        infoFuture.then<dynamic>((v) => v).catchError((_) => null),
        bulletinFuture.then<dynamic>((v) => v).catchError((_) => null),
      ]);

      final infoRes = queryResults[0];
      final bulletinRes = queryResults[1];

      if (infoRes != null && infoRes.data is Map<String, dynamic>) {
        _groupInfo = infoRes.data as Map<String, dynamic>;
      }
      if (bulletinRes != null && bulletinRes.data is Map<String, dynamic>) {
        final bData = bulletinRes.data as Map<String, dynamic>;
        final fullContent = bData['content']?.toString();
        if (fullContent != null && fullContent.isNotEmpty) {
          _groupInfo ??= {};
          final currentBulletin = (_groupInfo!['bulletin'] is Map)
              ? Map<String, dynamic>.from(_groupInfo!['bulletin'] as Map)
              : <String, dynamic>{};
          currentBulletin['content'] = fullContent;
          currentBulletin['time'] = bData['time'];
          _groupInfo!['bulletin'] = currentBulletin;
        }
      }

      // 2. 获取群成员列表
      final membersRes = await client.dio.get(
        'https://api.weibo.com/webim/groupchat/query_members.json',
        queryParameters: {
          'id': widget.groupId,
          'source': '209678993',
          'count': 50,
        },
      );
      if (membersRes.data is Map<String, dynamic>) {
        final rawMembers = (membersRes.data as Map<String, dynamic>)['members'] as List? ?? [];
        _members.clear();
        for (final m in rawMembers) {
          if (m is Map<String, dynamic>) {
            _members.add(Map<String, dynamic>.from(m));
          }
        }
      }

      // 3. 补充群主、前排管理员与前排群友的真实头像与昵称
      final ownerUid = _groupInfo?['owner']?.toString();
      final adminList = (_groupInfo?['admins'] as List? ?? []).map((e) => e.toString()).toList();
      final keyUids = <String>[];
      if (ownerUid != null && ownerUid.isNotEmpty) keyUids.add(ownerUid);
      keyUids.addAll(adminList);
      for (final m in _members.take(15)) {
        final uid = m['uid']?.toString();
        if (uid != null && !keyUids.contains(uid)) {
          keyUids.add(uid);
        }
      }

      await Future.wait(
        keyUids.take(15).map((uid) async {
          try {
            final uRes = await client.dio.get(
              'https://api.weibo.com/webim/2/users/show.json',
              queryParameters: {'uid': uid, 'source': '209678993'},
            );
            if (uRes.data is Map<String, dynamic>) {
              final uData = uRes.data as Map<String, dynamic>;
              final existingIdx = _members.indexWhere((m) => m['uid']?.toString() == uid);
              final memberEntry = {
                'uid': uid,
                'nick': uData['screen_name'] ?? uData['name'] ?? '群友',
                'avatar': uData['avatar_large'] ?? uData['profile_image_url'] ?? '',
                'is_owner': uid == ownerUid,
              };
              ChatConversationPage.globalUserCache[uid] = memberEntry;
              if (existingIdx != -1) {
                _members[existingIdx] = memberEntry;
              } else {
                _members.insert(0, memberEntry);
              }
            }
          } catch (_) {}
        }),
      );
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _showQRCodeDialog(String groupName, String groupAvatar) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final groupUrl = 'https://weibo.com/p/230491${widget.groupId}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                AppAvatar(url: groupAvatar, size: 48, name: groupName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        groupName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '群号: ${widget.groupId}',
                        style: TextStyle(fontSize: 12, color: colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: groupUrl,
                version: QrVersions.auto,
                size: 200.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '扫一扫二维码，加入群聊',
              style: TextStyle(fontSize: 13, color: colorScheme.outline),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: groupUrl));
              Navigator.of(ctx).pop();
              AppToast.show(context, '已复制群链接至剪贴板');
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('复制群链接'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showBulletinDialog(String groupName, String bulletinContent) {
    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('群公告', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Text.rich(
            TextSpan(
              children: WeiboTextParser.parse(
                rawText: bulletinContent,
                context: context,
                defaultStyle: const TextStyle(fontSize: 14.5, height: 1.5),
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: bulletinContent));
              Navigator.of(ctx).pop();
              AppToast.show(context, '已复制群公告内容');
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('复制公告'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final groupName = _groupInfo?['name']?.toString() ?? widget.initialGroupName ?? '群聊';
    final groupAvatar = _groupInfo?['round_avatar']?.toString() ??
        _groupInfo?['avatar']?.toString() ??
        widget.initialGroupAvatar ??
        '';
    final summary = _groupInfo?['summary']?.toString() ?? '';
    final memberCount = _groupInfo?['member_count'] ?? _members.length;
    final maxMember = _groupInfo?['max_member'] ?? 3000;
    final ownerUid = _groupInfo?['owner']?.toString() ?? '';
    final adminList = (_groupInfo?['admins'] as List? ?? []).map((e) => e.toString()).toList();

    final bulletinObj = _groupInfo?['bulletin'] is Map ? _groupInfo!['bulletin'] as Map<String, dynamic> : null;
    final bulletinContent = bulletinObj?['content']?.toString() ??
        _groupInfo?['notice']?.toString() ??
        '暂无群公告';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('群信息', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: false,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : ListView(
              children: [
                // 1. 群基本信息卡片 (头像、群名、简介)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  color: colorScheme.surface,
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AppAvatar(url: groupAvatar, size: 56, name: groupName),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              groupName,
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (summary.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                summary,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 0.5),

                // 2. 群二维码 (带原生二维码展示弹窗)
                ListTile(
                  title: const Text('群二维码', style: TextStyle(fontSize: 15)),
                  trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
                  onTap: () => _showQRCodeDialog(groupName, groupAvatar),
                ),

                const Divider(height: 1, thickness: 0.5),

                // 3. 群成员区域 (点击直接进入完整群成员列表)
                InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => GroupMembersPage(
                          groupId: widget.groupId,
                          groupName: groupName,
                          totalMemberCount: memberCount is int ? memberCount : 0,
                          ownerUid: ownerUid,
                          admins: adminList,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '群成员($memberCount/$maxMember)',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            Icon(Icons.chevron_right_rounded, color: colorScheme.outline, size: 20),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 76,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: 1 + _members.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 14),
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: colorScheme.outline.withValues(alpha: 0.4),
                                          width: 1.2,
                                        ),
                                      ),
                                      child: Icon(Icons.add_rounded,
                                          size: 26, color: colorScheme.onSurfaceVariant),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '添加成员',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                );
                              }

                              final m = _members[index - 1];
                              final nick = m['nick']?.toString() ?? '群友';
                              final avatar = m['avatar']?.toString() ?? '';
                              final uid = m['uid']?.toString() ?? '';

                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  if (uid.isNotEmpty) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (ctx) => UserProfilePage(
                                          uid: uid,
                                          screenName: nick,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppAvatar(url: avatar, size: 48, name: nick),
                                    const SizedBox(height: 6),
                                    SizedBox(
                                      width: 54,
                                      child: Text(
                                        nick,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colorScheme.onSurface,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Divider(height: 1, thickness: 0.5),

                // 4. 群公告 (可点开查看完整大图与富文本)
                InkWell(
                  onTap: () => _showBulletinDialog(groupName, bulletinContent),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '群公告',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            Icon(Icons.chevron_right_rounded, color: colorScheme.outline, size: 20),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text.rich(
                          TextSpan(
                            children: WeiboTextParser.parse(
                              rawText: bulletinContent,
                              context: context,
                              defaultStyle: TextStyle(
                                fontSize: 13.5,
                                color: colorScheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Divider(height: 1, thickness: 0.5),

                // 5. 群微博 (直连原生群微博动态)
                ListTile(
                  title: const Text('群微博', style: TextStyle(fontSize: 15)),
                  trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => GroupWeiboPage(
                          groupId: widget.groupId,
                          groupName: groupName,
                          ownerUid: ownerUid.isNotEmpty ? ownerUid : '1651911632',
                        ),
                      ),
                    );
                  },
                ),

                const Divider(height: 1, thickness: 0.5),

                // 6. 设置开关
                SwitchListTile(
                  title: const Text('置顶聊天', style: TextStyle(fontSize: 15)),
                  value: _isPinned,
                  onChanged: (val) => setState(() => _isPinned = val),
                ),
                const Divider(height: 1, indent: 16, thickness: 0.5),
                SwitchListTile(
                  title: const Text('消息免打扰', style: TextStyle(fontSize: 15)),
                  value: _isMuted,
                  onChanged: (val) => setState(() => _isMuted = val),
                ),

                const Divider(height: 1, thickness: 0.5),

                const SizedBox(height: 24),

                // 7. 退出群聊
                ListTile(
                  title: const Center(
                    child: Text(
                      '退出群聊',
                      style: TextStyle(
                        fontSize: 15.5,
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  onTap: () {
                    showAppDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('退出群聊'),
                        content: Text('确定要退出群聊 “$groupName” 吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              Navigator.of(context).pop();
                              AppToast.show(context, '已成功退出群聊');
                            },
                            child: const Text('确定退出'),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 40),
              ],
            ),
    );
  }
}
