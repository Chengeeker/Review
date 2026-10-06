import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/components/review_navigation_bar.dart';
import '../../../core/theme/theme_provider.dart';
import '../../feed/presentation/feed_controller.dart';
import '../../feed/presentation/feed_view.dart';
import '../../search/presentation/hot_trends_view.dart';
import '../../settings/presentation/settings_view.dart';
import 'widgets/app_drawer.dart';

final mainScaffoldKeyProvider = Provider<GlobalKey<ScaffoldState>>((ref) {
  return GlobalKey<ScaffoldState>();
});

/// Main Application Shell with Adaptive NavigationBar (Floating Pill / Full-width)
class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  int _currentIndex = 0;
  DateTime? _lastTimelineTapTime;
  Timer? _timelineSingleTapTimer;
  DateTime? _lastHotSearchTapTime;
  Timer? _hotSearchSingleTapTimer;
  final GlobalKey<HotTrendsViewState> _hotTrendsKey =
      GlobalKey<HotTrendsViewState>();

  late final List<Widget> _pages = [
    const FeedView(),
    HotTrendsView(key: _hotTrendsKey),
    const SettingsView(),
  ];

  @override
  void dispose() {
    _timelineSingleTapTimer?.cancel();
    _hotSearchSingleTapTimer?.cancel();
    super.dispose();
  }

  void _onNavigationItemSelected(int index) {
    if (index != _currentIndex) {
      _timelineSingleTapTimer?.cancel();
      _lastTimelineTapTime = null;
      _hotSearchSingleTapTimer?.cancel();
      _lastHotSearchTapTime = null;
      setState(() => _currentIndex = index);
      return;
    }

    // 用户在当前“时间线”页面上再次点击时间线底栏
    if (index == 0) {
      final now = DateTime.now();
      if (_lastTimelineTapTime != null &&
          now.difference(_lastTimelineTapTime!) <
              const Duration(milliseconds: 300)) {
        // 双击时间线：连点两下即触发回到顶部并刷新
        _timelineSingleTapTimer?.cancel();
        _timelineSingleTapTimer = null;
        _lastTimelineTapTime = null;
        ref.read(timelineScrollProvider.notifier).handleDoubleTap();
      } else {
        // 单击时间线：首次回顶，再次返回原位
        _lastTimelineTapTime = now;
        _timelineSingleTapTimer?.cancel();
        _timelineSingleTapTimer = Timer(const Duration(milliseconds: 300), () {
          ref.read(timelineScrollProvider.notifier).handleSingleTap();
          _lastTimelineTapTime = null;
        });
      }
    }

    // 用户在当前“热搜”页面上再次点击热搜底栏。
    if (index == 1) {
      final now = DateTime.now();
      if (_lastHotSearchTapTime != null &&
          now.difference(_lastHotSearchTapTime!) <
              const Duration(milliseconds: 300)) {
        _hotSearchSingleTapTimer?.cancel();
        _hotSearchSingleTapTimer = null;
        _lastHotSearchTapTime = null;
        _hotTrendsKey.currentState?.handleBottomBarDoubleTap();
      } else {
        _lastHotSearchTapTime = now;
        _hotSearchSingleTapTimer?.cancel();
        _hotSearchSingleTapTimer = Timer(const Duration(milliseconds: 300), () {
          _hotTrendsKey.currentState?.handleBottomBarSingleTap();
          _lastHotSearchTapTime = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final useFloating = themeState.useFloatingNavBar;
    final scaffoldKey = ref.watch(mainScaffoldKeyProvider);
    final body = IndexedStack(index: _currentIndex, children: _pages);
    final navigationBar = ReviewNavigationBar(
      selectedIndex: _currentIndex,
      onSelected: _onNavigationItemSelected,
      hasBottomInset: MediaQuery.paddingOf(context).bottom > 0,
    );
    return Scaffold(
      key: scaffoldKey,
      drawer: const AppDrawer(),
      extendBody: useFloating,
      body: body,
      bottomNavigationBar: navigationBar,
    );
  }
}
