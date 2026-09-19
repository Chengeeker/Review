import 'package:dio/dio.dart';
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

/// The two relation lists exposed by a Weibo profile.
enum UserRelationKind { following, followers }

/// Official following/follower list page.
///
/// The list is always read from Weibo's profile relation endpoint. It does
/// not use a locally cached list as a fallback because an empty local list is
/// indistinguishable from a private profile.
class UserRelationsPage extends ConsumerStatefulWidget {
  final UserRelationKind kind;
  final bool embedded;
  final String? ownerUid;
  final String? ownerName;
  final int? expectedCount;

  const UserRelationsPage({
    super.key,
    required this.kind,
    this.embedded = false,
    this.ownerUid,
    this.ownerName,
    this.expectedCount,
  });

  bool get isFollowers => kind == UserRelationKind.followers;

  String get title => isFollowers ? '粉丝列表' : '关注列表';

  String get emptyTitle => isFollowers ? '暂无粉丝' : '暂无关注的人';

  String get relationName => isFollowers ? '粉丝列表' : '关注列表';

  @override
  ConsumerState<UserRelationsPage> createState() => _UserRelationsPageState();
}

/// Compatibility wrapper for the existing drawer entry and older call sites.
class FriendsPage extends UserRelationsPage {
  const FriendsPage({
    super.key,
    super.embedded,
    super.ownerUid,
    super.ownerName,
    super.expectedCount,
  }) : super(kind: UserRelationKind.following);
}

/// Follower list wrapper used by the aggregate relation page.
class FollowersPage extends UserRelationsPage {
  const FollowersPage({
    super.key,
    super.embedded,
    super.ownerUid,
    super.ownerName,
    super.expectedCount,
  }) : super(kind: UserRelationKind.followers);
}

class _UserRelationsPageState extends ConsumerState<UserRelationsPage> {
  final List<WeiboUserModel> _users = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _nextPage = 1;
  String _emptyMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchUsers(refresh: true);
  }

  Future<String> _resolveOwnerUid() async {
    var uid = widget.ownerUid?.trim() ?? '';
    if (uid.isNotEmpty) return uid;

    final authState = ref.read(authProvider);
    uid = authState.uid?.trim() ?? '';
    if (uid.isNotEmpty) return uid;

    if (authState.isLoggedIn) {
      await ref.read(authProvider.notifier).refreshUserProfile();
      return ref.read(authProvider).uid?.trim() ?? '';
    }
    return '';
  }

  Future<void> _fetchUsers({required bool refresh}) async {
    if (!refresh && (_isLoadingMore || !_hasMore)) return;

    if (refresh) {
      _nextPage = 1;
      _hasMore = true;
      _emptyMessage = '';
      if (mounted) {
        setState(() => _isLoading = true);
      }
    } else if (mounted) {
      setState(() => _isLoadingMore = true);
    }

    final uid = await _resolveOwnerUid();
    if (uid.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
          _hasMore = false;
          _emptyMessage = '登录后才能读取关系列表';
        });
      }
      return;
    }

    final page = _nextPage;
    final client = ref.read(weiboDioClientProvider);
    _ParsedRelationResponse? parsed;
    Object? lastError;
    String rejectedMessage = '';

    try {
      final response = await client.dio.get(
        '/ajax/friendships/friends',
        queryParameters: _requestParameters(uid: uid, page: page),
        options: Options(
          headers: {
            'Referer': _refererFor(uid),
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );
      final candidate = _parseResponse(response.data);
      if (candidate.accepted) {
        parsed = candidate;
      } else if (candidate.message.isNotEmpty) {
        rejectedMessage = candidate.message;
      }
    } catch (error) {
      lastError = error;
    }

    if (!mounted) return;

    if (parsed == null) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        if (refresh && _users.isEmpty) {
          _emptyMessage = rejectedMessage.isNotEmpty
              ? rejectedMessage
              : (lastError == null
                  ? '微博暂未返回${widget.relationName}，请稍后重试'
                  : '暂时无法加载${widget.relationName}，请检查网络后重试');
        }
      });
      return;
    }

    final incoming = parsed.users;
    final response = parsed;
    final existingIds = _users.map((user) => user.id).toSet();
    final newUsers = incoming.where((user) {
      if (user.id.isEmpty) return true;
      return existingIds.add(user.id);
    }).toList();

    setState(() {
      if (refresh) _users.clear();
      _users.addAll(newUsers);
      _nextPage = page + 1;
      _hasMore = response.hasMore ?? incoming.isNotEmpty;
      _isLoading = false;
      _isLoadingMore = false;

      if (_users.isEmpty) {
        _emptyMessage = response.message.isNotEmpty
            ? response.message
            : ((widget.expectedCount ?? 0) > 0
                ? '该用户的${widget.relationName}可能受隐私设置影响，暂未公开'
                : widget.emptyTitle);
      } else {
        _emptyMessage = '';
      }
    });
  }

  Map<String, dynamic> _requestParameters({
    required String uid,
    required int page,
  }) {
    // This is the endpoint used by the web profile relation page.  The
    // relation is selected by `relate=fans`; omitting it is the following
    // list.  Do not fall back between the two modes: a default following
    // response is valid JSON but is wrong data for a fans page.
    return {
      'uid': uid,
      'page': page,
      if (widget.isFollowers) ...{
        'relate': 'fans',
        'type': 'fans',
      },
    };
  }

  String _refererFor(String uid) {
    final uri = Uri(
      scheme: 'https',
      host: 'weibo.com',
      path: '/u/page/follow/$uid',
      queryParameters: widget.isFollowers ? {'relate': 'fans'} : null,
    );
    return uri.toString();
  }

  _ParsedRelationResponse _parseResponse(dynamic payload) {
    if (payload is! Map) return const _ParsedRelationResponse.notAccepted();

    final root = Map<String, dynamic>.from(payload);
    final data = root['data'];
    final source = _userListSource(root);
    final users = <WeiboUserModel>[];
    final seen = <String>{};
    _collectUsers(source, users, seen);

    final message = _findMessage(root);
    final accepted = _isAccepted(root, source);
    final hasMore = _readHasMore(data) ?? _readHasMore(root);

    return _ParsedRelationResponse(
      users: users,
      hasMore: hasMore,
      message: _privacyMessage(message),
      accepted: accepted,
    );
  }

  dynamic _userListSource(Map<String, dynamic> root) {
    final rootUsers = root['users'];
    if (rootUsers is List || rootUsers is Map) return rootUsers;

    final data = root['data'];
    if (data is! Map) return null;
    final dataMap = Map<String, dynamic>.from(data);
    final directUsers = dataMap['users'];
    if (directUsers is List || directUsers is Map) return directUsers;

    for (final key in const ['follows', 'fans']) {
      final relation = dataMap[key];
      if (relation is Map) {
        final users = relation['users'];
        if (users is List || users is Map) return users;
      }
    }
    return null;
  }

  bool _isAccepted(Map<String, dynamic> root, dynamic source) {
    if (source is! List && source is! Map) return false;
    final ok = root['ok'];
    if (ok is num && ok == 0) return false;
    return true;
  }

  void _collectUsers(
    dynamic node,
    List<WeiboUserModel> output,
    Set<String> seen,
  ) {
    if (node is List) {
      for (final item in node) {
        _collectUsers(item, output, seen);
      }
      return;
    }
    if (node is! Map) return;

    final map = Map<String, dynamic>.from(node);
    if (_looksLikeUser(map)) {
      _addUser(map, output, seen);
      return;
    }
    for (final item in map.values) {
      _collectUsers(item, output, seen);
    }
  }

  bool _looksLikeUser(Map<String, dynamic> map) {
    return map['id'] != null ||
        map['idstr'] != null ||
        map['uid'] != null ||
        (map['screen_name'] != null && map['avatar'] != null);
  }

  void _addUser(
    Map<String, dynamic> json,
    List<WeiboUserModel> output,
    Set<String> seen,
  ) {
    final user = WeiboUserModel.fromJson(json);
    final key = user.id.isNotEmpty ? user.id : user.screenName;
    if (key.isEmpty || key == '匿名用户' || !seen.add(key)) return;
    output.add(user);
  }

  bool? _readHasMore(dynamic node) {
    if (node is! Map) return null;
    final map = Map<String, dynamic>.from(node);
    final nextCursor = map['next_cursor'] ?? map['nextCursor'];
    if (nextCursor != null) {
      final cursor = _toInt(nextCursor);
      if (cursor != null) return cursor != 0;
      return nextCursor.toString().trim().isNotEmpty;
    }
    final raw = map['has_more'] ?? map['hasMore'] ?? map['more'];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw != null) {
      final value = raw.toString().toLowerCase();
      if (value == 'true' || value == '1') return true;
      if (value == 'false' || value == '0') return false;
    }
    final maxPage = _toInt(map['max_page'] ?? map['maxPage']);
    final page = _toInt(map['page']);
    if (maxPage != null && page != null) return page < maxPage;
    return null;
  }

  int? _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String _findMessage(Map<String, dynamic> root) {
    for (final key in const ['msg', 'message', 'error', 'tip', 'text']) {
      final value = root[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    final data = root['data'];
    if (data is Map) {
      for (final key in const ['msg', 'message', 'error', 'tip', 'text']) {
        final value = data[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
    }
    return '';
  }

  String _privacyMessage(String message) {
    if (message.isEmpty) return '';
    if (RegExp(r'隐私|权限|不可见|未公开|仅自己|禁止|不存在').hasMatch(message)) {
      return '该用户的${widget.relationName}可能受隐私设置影响，暂未公开';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(
                widget.ownerName?.isNotEmpty == true
                    ? '${widget.ownerName}${widget.title}'
                    : widget.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
      body: !authState.isLoggedIn
          ? _buildLoginPrompt(colorScheme)
          : EasyRefresh(
              onRefresh: () => HapticFeedbackUtil.refresh(
                () => _fetchUsers(refresh: true),
              ),
              onLoad: () async {
                await _fetchUsers(refresh: false);
                return _hasMore
                    ? IndicatorResult.success
                    : IndicatorResult.noMore;
              },
              child: _isLoading
                  ? Center(
                      child:
                          CircularProgressIndicator(color: colorScheme.primary),
                    )
                  : _users.isEmpty
                      ? _buildEmptyState(colorScheme)
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _users.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 64),
                          itemBuilder: (context, index) {
                            final user = _users[index];
                            return ListTile(
                              minVerticalPadding: 8,
                              leading: AppAvatar(
                                url: user.avatar,
                                size: 46,
                                name: user.screenName,
                                verified: user.verified,
                                verifiedType: user.verifiedType,
                              ),
                              title: Text(
                                user.screenName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                user.verifiedReason.isNotEmpty
                                    ? user.verifiedReason
                                    : (user.description.isNotEmpty
                                        ? user.description
                                        : '粉丝 ${user.followersCountStr}'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                              ),
                              onTap: () {
                                HapticFeedbackUtil.light();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (ctx) => UserProfilePage(
                                      user: user,
                                      uid: user.id,
                                      screenName: user.screenName,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),
    );
  }

  Widget _buildLoginPrompt(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 60,
            color: colorScheme.primary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          const Text(
            '登录后即可同步关注列表和粉丝列表',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
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
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    final message =
        _emptyMessage.isNotEmpty ? _emptyMessage : widget.emptyTitle;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 54,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParsedRelationResponse {
  final List<WeiboUserModel> users;
  final bool? hasMore;
  final String message;
  final bool accepted;

  const _ParsedRelationResponse({
    this.users = const [],
    this.hasMore,
    this.message = '',
    this.accepted = true,
  });

  const _ParsedRelationResponse.notAccepted()
      : users = const [],
        hasMore = false,
        message = '',
        accepted = false;
}
