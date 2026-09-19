import 'package:dio/dio.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../auth/presentation/login_page.dart';
import 'chaohua_detail_page.dart';

const _followedTopicsTabId = '231093_-_chaohua';

/// Performs a read-only capability check for a profile's followed-topic tab.
/// A third tab is only shown when Weibo returns a real topic payload. Empty
/// public lists are accepted; login/privacy/error shells are not.
Future<bool> probeFollowedTopics(WeiboDioClient client, String uid) async {
  if (uid.trim().isEmpty) return false;

  try {
    final response = await client.dio.get(
      '/ajax/profile/topicContent',
      queryParameters: _topicRequestParameters(1),
      options: Options(
        headers: {
          'Referer': _topicReferer(uid),
          'X-Requested-With': 'XMLHttpRequest',
        },
      ),
    );
    return _isAccessibleTopicResponse(response.data);
  } catch (_) {
    return false;
  }
}

bool _isAccessibleTopicResponse(dynamic payload) {
  if (payload is! Map) return false;
  final root = Map<String, dynamic>.from(payload);
  final data = root['data'];
  final message = _topicResponseMessage(root);
  if (RegExp(r'隐私|权限|不可见|未公开|仅自己|禁止|不存在').hasMatch(message)) {
    return false;
  }
  // The web endpoint is accepted only when it exposes the actual list field.
  // A generic `ok=1` shell is not enough: it is how a private/error response
  // previously became a false "暂无关注的超话" result.
  return _topicItems(data).isNotEmpty || _hasTopicListField(data);
}

Map<String, dynamic> _topicRequestParameters(int page) => {
      'tabid': _followedTopicsTabId,
      'page': page,
    };

String _topicReferer(String uid) =>
    'https://weibo.com/u/page/follow/$uid/$_followedTopicsTabId';

bool _hasTopicListField(dynamic value) {
  if (value is! Map) return value is List;
  return const ['list', 'topics', 'cards'].any(value.containsKey);
}

List<dynamic> _topicItems(dynamic value) {
  if (value is List) return value;
  if (value is! Map) return const [];
  for (final key in const ['list', 'topics', 'cards']) {
    final nested = value[key];
    if (nested is List) return nested;
    if (nested is Map) return nested.values.toList();
  }
  return const [];
}

String _topicResponseMessage(Map<String, dynamic> root) {
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

/// 关注的超话大厅 (精准直连 https://weibo.com/u/page/follow/{uid}/231093_-_chaohua)
class FollowedTopicsPage extends ConsumerStatefulWidget {
  final bool embedded;
  final String? ownerUid;
  final String? ownerName;
  final ValueChanged<bool>? onAvailability;

  const FollowedTopicsPage({
    super.key,
    this.embedded = false,
    this.ownerUid,
    this.ownerName,
    this.onAvailability,
  });

  @override
  ConsumerState<FollowedTopicsPage> createState() => _FollowedTopicsPageState();
}

class _FollowedTopicsPageState extends ConsumerState<FollowedTopicsPage> {
  final List<Map<String, dynamic>> _topics = [];
  bool _isLoading = true;
  int _page = 1;
  bool _hasMore = true;
  String _emptyMessage = '';
  bool _availabilityReported = false;

  @override
  void initState() {
    super.initState();
    _fetchTopics(refresh: true);
  }

  Future<void> _fetchTopics({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      setState(() => _isLoading = true);
    }

    final authState = ref.read(authProvider);
    final client = ref.read(weiboDioClientProvider);
    var uid = widget.ownerUid?.trim() ?? '';
    if (uid.isEmpty) uid = authState.uid ?? '';

    if (uid.isEmpty && authState.isLoggedIn) {
      await ref.read(authProvider.notifier).refreshUserProfile();
      uid = ref.read(authProvider).uid ?? '';
    }

    final extractedTopics = <Map<String, dynamic>>[];
    dynamic acceptedPayload;
    String responseMessage = '';

    if (uid.isNotEmpty) {
      try {
        final res = await client.dio.get(
          '/ajax/profile/topicContent',
          queryParameters: _topicRequestParameters(_page),
          options: Options(headers: {
            'Referer': _topicReferer(uid),
            'X-Requested-With': 'XMLHttpRequest',
          }),
        );
        responseMessage = res.data is Map
            ? _topicResponseMessage(Map<String, dynamic>.from(res.data))
            : responseMessage;
        if (_isAccessibleTopicResponse(res.data)) {
          acceptedPayload = res.data;
        }
      } catch (_) {
        // Keep the empty/error state; do not substitute another relation.
      }
    } else {
      responseMessage = '登录后才能读取关注的超话';
    }

    if (acceptedPayload is Map) {
      final data = acceptedPayload['data'];
      final rawList = _topicItems(data);
      for (final item in rawList) {
        if (item is Map) {
          final parsed = _extractChaohuaItem(Map<String, dynamic>.from(item));
          if (parsed != null) extractedTopics.add(parsed);
        }
      }
      if (data is Map) {
        final maxPage = int.tryParse(
              (data['max_page'] ?? data['maxPage'] ?? '1').toString(),
            ) ??
            1;
        _hasMore = _page < maxPage && rawList.isNotEmpty;
      } else {
        _hasMore = false;
      }
    } else {
      _hasMore = false;
    }

    if (mounted) {
      if (refresh && !_availabilityReported) {
        _availabilityReported = true;
        widget.onAvailability?.call(acceptedPayload != null);
      }
      setState(() {
        if (refresh) {
          _topics.clear();
        }
        _topics.addAll(extractedTopics);
        _emptyMessage = _privacyMessage(responseMessage);
        _isLoading = false;
      });
    }
  }

  String _privacyMessage(String message) {
    if (message.isEmpty) return '';
    if (RegExp(r'隐私|权限|不可见|未公开|仅自己|禁止|不存在').hasMatch(message)) {
      return '该用户的关注超话可能受隐私设置影响，暂未公开';
    }
    return message;
  }

  Map<String, dynamic>? _extractChaohuaItem(Map<String, dynamic> item) {
    final title = item['topic_name']?.toString() ??
        item['title']?.toString() ??
        item['name']?.toString() ??
        '';

    if (title.isEmpty) return null;

    final avatar = item['pic']?.toString() ??
        item['avatar']?.toString() ??
        item['avatar_large']?.toString() ??
        '';

    final desc = item['content1']?.toString() ??
        item['intro']?.toString() ??
        item['description']?.toString() ??
        '';

    final followCount = item['content2']?.toString() ??
        (item['follow_count'] != null ? '粉丝：${item['follow_count']}' : '');

    final statusCount = item['status_count'] is int
        ? item['status_count'] as int
        : int.tryParse(item['status_count']?.toString() ?? '') ?? 0;

    final oid = item['oid']?.toString() ?? '';
    final link = item['link']?.toString() ?? '';
    final scheme = item['scheme']?.toString() ?? '';

    // 提取纯净 containerid (例如 100808e42ac86fcd4c91f965e34411bd21f0b0)
    String containerid = '';
    if (oid.startsWith('1022:')) {
      containerid = oid.substring(5);
    } else if (oid.isNotEmpty) {
      containerid = oid;
    } else {
      final match = RegExp(r'100808[0-9a-zA-Z]+').firstMatch('$link $scheme');
      if (match != null) {
        containerid = match.group(0)!;
      }
    }

    return {
      'title': title,
      'avatar': avatar,
      'desc': desc,
      'followCount': followCount,
      'statusCount': statusCount,
      'containerid': containerid,
      'raw': item,
    };
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
              title: Text(
                widget.ownerName?.isNotEmpty == true
                    ? '${widget.ownerName}关注的超话'
                    : '关注的超话',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
      body: !isLoggedIn
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.diamond_outlined,
                      size: 60,
                      color: colorScheme.primary.withValues(alpha: 0.6)),
                  const SizedBox(height: 16),
                  const Text('登录后即可同步您关注的超话',
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
              onRefresh: () => HapticFeedbackUtil.refresh(
                () => _fetchTopics(refresh: true),
              ),
              onLoad: () async {
                _page++;
                await _fetchTopics(refresh: false);
                return _hasMore
                    ? IndicatorResult.success
                    : IndicatorResult.noMore;
              },
              child: _isLoading
                  ? Center(
                      child:
                          CircularProgressIndicator(color: colorScheme.primary))
                  : _topics.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.diamond_outlined,
                                  size: 54,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.4)),
                              const SizedBox(height: 12),
                              Text(
                                _emptyMessage.isNotEmpty
                                    ? _emptyMessage
                                    : '暂无关注的超话',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          itemCount: _topics.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 68),
                          itemBuilder: (context, index) {
                            final t = _topics[index];
                            final title = t['title']?.toString() ?? '超话';
                            final avatar = t['avatar']?.toString() ?? '';
                            final desc = t['desc']?.toString() ?? '';
                            final followCount =
                                t['followCount']?.toString() ?? '';
                            final statusCount = t['statusCount'] as int? ?? 0;
                            final containerid =
                                t['containerid']?.toString() ?? '';

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              leading: avatar.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        avatar,
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: colorScheme.primaryContainer,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Icon(Icons.diamond_rounded,
                                              color: colorScheme
                                                  .onPrimaryContainer),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.diamond_rounded,
                                          color:
                                              colorScheme.onPrimaryContainer),
                                    ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.diamond_rounded,
                                      size: 16, color: colorScheme.primary),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (followCount.isNotEmpty || statusCount > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        [
                                          if (followCount.isNotEmpty)
                                            followCount,
                                          if (statusCount > 0)
                                            '$statusCount 帖子',
                                        ].join(' · '),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  if (desc.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        desc,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () {
                                if (containerid.isNotEmpty) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (ctx) => ChaohuaDetailPage(
                                        containerid: containerid,
                                        title: title,
                                        avatar: avatar,
                                        desc: desc,
                                        followCount: followCount,
                                        statusCount: statusCount,
                                      ),
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        ),
            ),
    );
  }
}
