import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../profile/presentation/user_profile_page.dart';
import 'chat_conversation_page.dart';

/// 微博原生群成员列表页面 (完整支持群成员检索、头像与昵称深度解析、身份徽章与个人主页直达)
class GroupMembersPage extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;
  final int totalMemberCount;
  final String? ownerUid;
  final List<String> admins;

  const GroupMembersPage({
    super.key,
    required this.groupId,
    required this.groupName,
    this.totalMemberCount = 0,
    this.ownerUid,
    this.admins = const [],
  });

  @override
  ConsumerState<GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends ConsumerState<GroupMembersPage> {
  final List<Map<String, dynamic>> _allMembers = [];
  final Map<String, Map<String, dynamic>> _userCache = {};
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchMembers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchMembers() async {
    setState(() => _isLoading = true);
    final client = ref.read(weiboDioClientProvider);

    try {
      // 1. 获取群成员列表 (一次性拉取高达 500 个群成员)
      final res = await client.dio.get(
        'https://api.weibo.com/webim/groupchat/query_members.json',
        queryParameters: {
          'id': widget.groupId,
          'source': '209678993',
          'count': 500,
        },
      );

      if (res.data is Map<String, dynamic>) {
        final rawList = (res.data as Map<String, dynamic>)['members'] as List? ?? [];
        _allMembers.clear();
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            final uid = item['uid']?.toString() ?? '';
            if (uid.isNotEmpty) {
              _allMembers.add(item);
            }
          }
        }
      }

      // 确保群主与管理员处于最前排
      if (widget.ownerUid != null && widget.ownerUid!.isNotEmpty) {
        if (!_allMembers.any((m) => m['uid']?.toString() == widget.ownerUid)) {
          _allMembers.insert(0, {'uid': widget.ownerUid, 'time': 0});
        }
      }
      for (final a in widget.admins) {
        if (!_allMembers.any((m) => m['uid']?.toString() == a)) {
          _allMembers.add({'uid': a, 'time': 0});
        }
      }

      // 2. 异步并行解析前 50 名群成员的真实昵称与高清头像
      _resolveMemberBatch(_allMembers.take(50).map((m) => m['uid'].toString()).toList());
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resolveMemberBatch(List<String> uids) async {
    final client = ref.read(weiboDioClientProvider);
    final toFetch = uids.where((u) => !_userCache.containsKey(u)).toList();
    if (toFetch.isEmpty) return;

    await Future.wait(
      toFetch.map((uid) async {
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
              'desc': uData['description'] ?? '',
            };
            _userCache[uid] = entry;
            ChatConversationPage.globalUserCache[uid] = entry;
          }
        } catch (_) {}
      }),
    );

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final filteredMembers = _allMembers.where((m) {
      final uid = m['uid']?.toString() ?? '';
      if (_searchQuery.isEmpty) return true;
      final cached = _userCache[uid];
      final nick = cached?['nick']?.toString().toLowerCase() ?? '';
      return uid.contains(_searchQuery) || nick.contains(_searchQuery.toLowerCase());
    }).toList();

    final countDisplay = widget.totalMemberCount > 0 ? widget.totalMemberCount : _allMembers.length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('群成员', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            Text(
              '${widget.groupName} (共 $countDisplay 人)',
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() => _searchQuery = val.trim());
                },
                decoration: InputDecoration(
                  hintText: '搜索群成员昵称或 UID...',
                  hintStyle: TextStyle(fontSize: 14, color: colorScheme.outline),
                  prefixIcon: Icon(Icons.search_rounded, size: 20, color: colorScheme.outline),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),

          // 成员列表
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
                : filteredMembers.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty ? '暂无群成员信息' : '未找到相关群成员',
                          style: TextStyle(color: colorScheme.outline, fontSize: 14),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filteredMembers.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 68, thickness: 0.5),
                        itemBuilder: (context, index) {
                          final m = filteredMembers[index];
                          final uid = m['uid']?.toString() ?? '';
                          final cached = _userCache[uid];

                          // 按需触发后续用户数据解析
                          if (cached == null) {
                            _resolveMemberBatch([uid]);
                          }

                          final nick = cached?['nick'] ?? (m['nick'] ?? '群友 $uid');
                          final avatar = cached?['avatar'] ?? '';
                          final isOwner = uid == widget.ownerUid;
                          final isAdmin = widget.admins.contains(uid);

                          final rawTime = m['time']?.toString() ?? '';
                          String joinTimeText = '';
                          if (rawTime.isNotEmpty && rawTime != '0') {
                            final ts = int.tryParse(rawTime);
                            if (ts != null) {
                              final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
                              joinTimeText = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} 加群';
                            }
                          }

                          return ListTile(
                            leading: AppAvatar(url: avatar, size: 44, name: nick),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    nick,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isOwner)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade700,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '群主',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                else if (isAdmin)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade600,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '管理员',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('UID: $uid',
                                    style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                                if (joinTimeText.isNotEmpty)
                                  Text(joinTimeText,
                                      style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                              ],
                            ),
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
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
