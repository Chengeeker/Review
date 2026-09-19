import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import 'followed_topics_page.dart';
import 'user_relations_page.dart';

/// Aggregates the official relation lists for the current account or a
/// visited profile. The current account also gets its own followed-topic tab;
/// another profile never gets that tab because its followed topics are not
/// publicly exposed by this page.
class MyFollowsPage extends ConsumerStatefulWidget {
  final int initialIndex;
  final String? ownerUid;
  final String? ownerName;
  final int? followingCount;
  final int? followersCount;

  const MyFollowsPage({
    super.key,
    this.initialIndex = 0,
    this.ownerUid,
    this.ownerName,
    this.followingCount,
    this.followersCount,
  });

  @override
  ConsumerState<MyFollowsPage> createState() => _MyFollowsPageState();
}

class _MyFollowsPageState extends ConsumerState<MyFollowsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final bool _showOwnTopics;

  bool get _isSelf {
    final ownerUid = widget.ownerUid?.trim() ?? '';
    final authUid = ref.read(authProvider).uid?.trim() ?? '';
    return ownerUid.isEmpty || (authUid.isNotEmpty && ownerUid == authUid);
  }

  List<String> get _tabs => <String>[
        '关注列表',
        _showOwnTopics ? '我的粉丝' : '粉丝列表',
        if (_showOwnTopics) '我的超话',
      ];

  int get _tabCount => _showOwnTopics ? 3 : 2;

  @override
  void initState() {
    super.initState();
    _showOwnTopics = _isSelf;
    _tabController = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, _tabCount - 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabLabels = _tabs;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.ownerName?.isNotEmpty == true
              ? '${widget.ownerName}的关注列表'
              : '关注列表',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.normal, fontSize: 14.5),
          tabs: tabLabels.map((label) => Tab(text: label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          FriendsPage(
            embedded: true,
            ownerUid: widget.ownerUid,
            ownerName: widget.ownerName,
            expectedCount: widget.followingCount,
          ),
          FollowersPage(
            embedded: true,
            ownerUid: widget.ownerUid,
            ownerName: widget.ownerName,
            expectedCount: widget.followersCount,
          ),
          if (_showOwnTopics)
            FollowedTopicsPage(
              embedded: true,
              ownerUid: widget.ownerUid,
              ownerName: widget.ownerName,
            ),
        ],
      ),
    );
  }
}
