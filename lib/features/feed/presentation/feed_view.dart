import 'dart:async';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../auth/presentation/login_page.dart';
import '../../compose/presentation/compose_tweet_page.dart';
import '../../home/presentation/main_scaffold.dart';
import '../../search/presentation/search_view.dart';
import 'feed_controller.dart';
import 'widgets/group_dropdown_panel.dart';
import 'widgets/tweet_card.dart';

/// Main Feed Timeline View with Top Group Dropdown Switcher and Compose Tweet Action
class FeedView extends ConsumerStatefulWidget {
  const FeedView({super.key});

  @override
  ConsumerState<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends ConsumerState<FeedView> with SingleTickerProviderStateMixin {
  bool _isDropdownOpen = false;
  late final AnimationController _animationController;
  late final Animation<double> _expandAnimation;
  late final ScrollController _scrollController;
  DateTime? _lastTopBarTapTime;
  Timer? _topBarSingleTapTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(timelineScrollProvider.notifier).attachController(_scrollController);
    });
  }

  @override
  void dispose() {
    _topBarSingleTapTimer?.cancel();
    ref.read(timelineScrollProvider.notifier).detachController();
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _toggleDropdown() {
    setState(() {
      _isDropdownOpen = !_isDropdownOpen;
      if (_isDropdownOpen) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void _closeDropdown() {
    if (_isDropdownOpen) {
      setState(() {
        _isDropdownOpen = false;
        _animationController.reverse();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(feedControllerProvider);
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isFriendsTab = feedState.currentCategory == 'friends' ||
        feedState.currentCategory == 'all_follow' ||
        feedState.currentCategory.startsWith('11000') ||
        feedState.currentCategory.startsWith('10001') ||
        feedState.userGroups.any((g) => g.gid == feedState.currentCategory);

    final showLoginBanner = isFriendsTab && !authState.isLoggedIn;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            final now = DateTime.now();
            if (_lastTopBarTapTime != null &&
                now.difference(_lastTopBarTapTime!) < const Duration(milliseconds: 300)) {
              // 连续点击两次：触发双击回顶/刷新
              _topBarSingleTapTimer?.cancel();
              _topBarSingleTapTimer = null;
              _lastTopBarTapTime = null;
              ref.read(timelineScrollProvider.notifier).handleTopBarDoubleTap();
            } else {
              _lastTopBarTapTime = now;
              _topBarSingleTapTimer?.cancel();
              _topBarSingleTapTimer = Timer(const Duration(milliseconds: 300), () {
                _lastTopBarTapTime = null;
              });
            }
          },
          child: AppBar(
            titleSpacing: 0,
            centerTitle: false,
            // Leading: 侧边栏入口 (当前用户头像，点击呼出全局侧边栏)
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    _closeDropdown();
                    ref.read(mainScaffoldKeyProvider).currentState?.openDrawer();
                  },
                  child: AppAvatar(
                    url: authState.avatar,
                    size: 34,
                    name: authState.nickname ?? '',
                  ),
                ),
              ),
            ),
            // Clickable Title with Dropdown Triangle (对齐截图 1: 最新微博 ▾)
            title: InkWell(
              onTap: _toggleDropdown,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      feedState.currentCategoryTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _isDropdownOpen ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.arrow_drop_down_rounded, size: 24),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              // Edit/Compose Tweet Button (对齐截图 1 右侧发微博铅笔图标)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: '发微博',
                onPressed: () {
                  HapticFeedbackUtil.light();
                  _closeDropdown();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (ctx) => const ComposeTweetPage()),
                  );
                },
              ),
              // Search Button (对齐截图 1 右侧搜索图标)
              IconButton(
                icon: const Icon(Icons.search_rounded),
                tooltip: '搜索',
                onPressed: () {
                  HapticFeedbackUtil.light();
                  _closeDropdown();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (ctx) => const SearchView()),
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // Main Timeline Feed Content
          showLoginBanner
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline_rounded, size: 56, color: colorScheme.primary),
                            const SizedBox(height: 16),
                            const Text(
                              '关注流需要登录',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '登录或导入微博账号凭据后，即可同步查看你关注的好友与特别关注动态',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              icon: const Icon(Icons.login_rounded),
                              label: const Text('去登录 / 导入凭据'),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (ctx) => const LoginPage()),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : EasyRefresh(
                  onRefresh: () async {
                    _closeDropdown();
                    await ref.read(feedControllerProvider.notifier).refreshFeed();
                  },
                  onLoad: () async {
                    final hasMore = await ref.read(feedControllerProvider.notifier).loadMore();
                    return hasMore ? IndicatorResult.success : IndicatorResult.noMore;
                  },
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.maxScrollExtent > 0) {
                        final progress = notification.metrics.pixels / notification.metrics.maxScrollExtent;
                        final remainingDistance = notification.metrics.maxScrollExtent - notification.metrics.pixels;
                        // 当滑动浏览达到 60% 阈值，或剩余可视距离小于 1500dp 时，提前在后台无感预加载下一页
                        if (progress >= 0.60 || remainingDistance < 1500) {
                          if (feedState.hasMore && !feedState.isLoading) {
                            ref.read(feedControllerProvider.notifier).loadMore();
                          }
                        }
                      }
                      return false;
                    },
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (feedState.isLoading && feedState.statuses.isEmpty)
                          const SliverFillRemaining(
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (feedState.statuses.isEmpty)
                          SliverFillRemaining(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.inbox_rounded,
                                      size: 56,
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      feedState.errorMessage ?? '暂无微博内容',
                                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 16),
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.refresh_rounded, size: 16),
                                      label: const Text('重新加载'),
                                      onPressed: () => ref.read(feedControllerProvider.notifier).refreshFeed(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: EdgeInsets.only(
                              top: 4,
                              bottom: ref.watch(themeProvider).useFloatingNavBar ? 72.0 : 16.0,
                            ),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  // 双保险：滑动到倒数第 8 条微博时，提前向后预请求下一页内容
                                  if (index >= feedState.statuses.length - 8 &&
                                      feedState.hasMore &&
                                      !feedState.isLoading) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      ref.read(feedControllerProvider.notifier).loadMore();
                                    });
                                  }
                                  final status = feedState.statuses[index];
                                  return TweetCard(status: status);
                                },
                                childCount: feedState.statuses.length,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

          // Semi-transparent Backdrop Barrier when Dropdown is open
          if (_isDropdownOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeDropdown,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.4),
                ),
              ),
            ),

          // Animated Top Group Dropdown Panel (对齐截图 1)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SizeTransition(
              sizeFactor: _expandAnimation,
              axisAlignment: -1.0,
              child: GroupDropdownPanel(
                currentCategoryId: feedState.currentCategory,
                customDefaultGroups: feedState.customDefaultGroups,
                customPersonalGroups: feedState.customPersonalGroups,
                userGroups: feedState.userGroups,
                customHotGroups: feedState.customHotGroups,
                onSelectGroup: (id, name) {
                  _closeDropdown();
                  ref.read(feedControllerProvider.notifier).setCategory(id, name);
                },
                onClose: _closeDropdown,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
