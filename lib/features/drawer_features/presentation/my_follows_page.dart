import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'followed_topics_page.dart';
import 'friends_page.dart';

/// 「我的关注」聚合页面 (双顶栏：关注的人 / 关注的超话)
class MyFollowsPage extends ConsumerStatefulWidget {
  final int initialIndex;

  const MyFollowsPage({
    super.key,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<MyFollowsPage> createState() => _MyFollowsPageState();
}

class _MyFollowsPageState extends ConsumerState<MyFollowsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = ['关注的人', '关注的超话'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, _tabs.length - 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的关注', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14.5),
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          FriendsPage(embedded: true),
          FollowedTopicsPage(embedded: true),
        ],
      ),
    );
  }
}
