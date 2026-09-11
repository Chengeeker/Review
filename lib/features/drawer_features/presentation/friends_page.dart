import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../auth/presentation/login_page.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../../profile/presentation/user_profile_page.dart';

/// 关注的人 / 关注列表大厅 (精准直连 https://weibo.com/u/page/follow/{uid}/231093_-_selffollowed)
class FriendsPage extends ConsumerStatefulWidget {
  final bool embedded;

  const FriendsPage({
    super.key,
    this.embedded = false,
  });

  @override
  ConsumerState<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends ConsumerState<FriendsPage> {
  final List<WeiboUserModel> _friends = [];
  bool _isLoading = true;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchFriends(refresh: true);
  }

  Future<void> _fetchFriends({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      setState(() => _isLoading = true);
    }

    final authState = ref.read(authProvider);
    final client = ref.read(weiboDioClientProvider);
    var uid = authState.uid ?? '';

    if (uid.isEmpty) {
      await ref.read(authProvider.notifier).refreshUserProfile();
      uid = ref.read(authProvider).uid ?? '';
    }

    final usersList = <WeiboUserModel>[];

    // 官方原生关注列表接口 (https://weibo.com/u/page/follow/{uid}/231093_-_selffollowed)
    final candidateUrls = [
      if (uid.isNotEmpty) '/ajax/profile/followContent?uid=$uid&containerid=231093${uid}_-_selffollowed&page=$_page',
      if (uid.isNotEmpty) '/ajax/profile/followContent?uid=$uid&tab=selffollowed&page=$_page',
      if (uid.isNotEmpty) '/ajax/profile/followContent?uid=$uid&containerid=231093_-_selffollowed&page=$_page',
      if (uid.isNotEmpty) '/ajax/profile/followContent?uid=$uid&page=$_page',
      '/ajax/profile/followContent?page=$_page',
    ];

    for (final url in candidateUrls) {
      try {
        final res = await client.dio.get(url);
        if (res.data is Map<String, dynamic>) {
          final data = res.data as Map<String, dynamic>;
          final parsed = _parseUsersFromResponse(data);
          if (parsed.isNotEmpty) {
            usersList.addAll(parsed);
            break;
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        if (refresh) {
          _friends.clear();
        }
        _friends.addAll(usersList);
        _hasMore = usersList.isNotEmpty;
        _isLoading = false;
      });
    }
  }

  List<WeiboUserModel> _parseUsersFromResponse(Map<String, dynamic> json) {
    final results = <WeiboUserModel>[];
    final data = json['data'];

    List? rawList;
    if (data is Map<String, dynamic>) {
      final follows = data['follows'];
      if (follows is Map<String, dynamic>) {
        rawList = follows['users'] as List? ??
            follows['cards'] as List? ??
            follows['follows'] as List? ??
            follows['list'] as List?;
      } else if (follows is List) {
        rawList = follows;
      } else {
        rawList = data['users'] as List? ?? data['cards'] as List? ?? data['list'] as List?;
      }
    } else if (data is List) {
      rawList = data;
    }

    if (rawList != null) {
      for (final item in rawList) {
        if (item is Map<String, dynamic>) {
          if (item['card_group'] is List) {
            for (final sub in item['card_group']) {
              if (sub is Map<String, dynamic>) {
                final u = _extractUser(sub);
                if (u != null) results.add(u);
              }
            }
          } else {
            final u = _extractUser(item);
            if (u != null) results.add(u);
          }
        }
      }
    }
    return results;
  }

  WeiboUserModel? _extractUser(Map<String, dynamic> item) {
    if (item['user'] is Map<String, dynamic>) {
      final u = WeiboUserModel.fromJson(item['user'] as Map<String, dynamic>);
      if (u.id.isNotEmpty || u.screenName.isNotEmpty) return u;
    }
    final u = WeiboUserModel.fromJson(item);
    if (u.id.isNotEmpty || (u.screenName.isNotEmpty && u.screenName != '匿名用户')) {
      return u;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isLoggedIn = authState.isLoggedIn;

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('关注的人', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
      body: !isLoggedIn
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline_rounded, size: 60, color: colorScheme.primary.withValues(alpha: 0.6)),
                  const SizedBox(height: 16),
                  const Text('登录后即可同步您关注的好友与博主列表', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
              onRefresh: () => _fetchFriends(refresh: true),
              onLoad: () async {
                _page++;
                await _fetchFriends(refresh: false);
                return _hasMore ? IndicatorResult.success : IndicatorResult.noMore;
              },
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
                  : _friends.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline_rounded, size: 54, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                              const SizedBox(height: 12),
                              Text(
                                '暂无关注的人',
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _friends.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
                          itemBuilder: (context, index) {
                            final user = _friends[index];
                            return ListTile(
                              leading: AppAvatar(
                                url: user.avatar,
                                size: 46,
                                name: user.screenName,
                                verified: user.verified,
                                verifiedType: user.verifiedType,
                              ),
                              title: Text(user.screenName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                user.verifiedReason.isNotEmpty
                                    ? user.verifiedReason
                                    : (user.description.isNotEmpty ? user.description : '粉丝 ${user.followersCountStr}'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                              onTap: () {
                                HapticFeedbackUtil.light();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (ctx) => UserProfilePage(user: user, uid: user.id, screenName: user.screenName),
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),
    );
  }
}
