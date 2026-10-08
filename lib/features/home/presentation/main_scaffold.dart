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

class _MainScaffoldState extends ConsumerState<MainScaffold>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  int _previousIndex = 0;
  DateTime? _lastTimelineTapTime;
  Timer? _timelineSingleTapTimer;
  DateTime? _lastHotSearchTapTime;
  Timer? _hotSearchSingleTapTimer;
  final GlobalKey<HotTrendsViewState> _hotTrendsKey =
      GlobalKey<HotTrendsViewState>();
  late final AnimationController _tabTransitionController;
  late final CurvedAnimation _tabTransitionCurve;
  late Animation<Offset> _tabIncomingTransition;
  late Animation<Offset> _tabOutgoingTransition;
  bool _isTabTransitioning = false;

  late final List<Widget> _pages = [
    const FeedView(),
    HotTrendsView(key: _hotTrendsKey),
    const SettingsView(),
  ];

  @override
  void initState() {
    super.initState();
    _tabTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1,
    );
    _tabTransitionCurve = CurvedAnimation(
      parent: _tabTransitionController,
      curve: Curves.easeOutCubic,
    );
    _tabIncomingTransition = const AlwaysStoppedAnimation(Offset.zero);
    _tabOutgoingTransition = const AlwaysStoppedAnimation(Offset.zero);
    _tabTransitionController.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          _isTabTransitioning &&
          mounted) {
        setState(() => _isTabTransitioning = false);
      }
    });
  }

  @override
  void dispose() {
    _timelineSingleTapTimer?.cancel();
    _hotSearchSingleTapTimer?.cancel();
    _tabTransitionCurve.dispose();
    _tabTransitionController.dispose();
    super.dispose();
  }

  void _onNavigationItemSelected(int index) {
    if (index != _currentIndex) {
      _timelineSingleTapTimer?.cancel();
      _lastTimelineTapTime = null;
      _hotSearchSingleTapTimer?.cancel();
      _lastHotSearchTapTime = null;
      if (MediaQuery.disableAnimationsOf(context)) {
        _tabTransitionController.stop();
        setState(() {
          _previousIndex = index;
          _currentIndex = index;
          _isTabTransitioning = false;
          _tabIncomingTransition = const AlwaysStoppedAnimation(Offset.zero);
          _tabOutgoingTransition = const AlwaysStoppedAnimation(Offset.zero);
        });
        _tabTransitionController.value = 1;
        return;
      }

      final currentOffset = _isTabTransitioning
          ? _tabIncomingTransition.value
          : Offset.zero;
      var direction = index > _currentIndex ? 1.0 : -1.0;
      if (Directionality.of(context) == TextDirection.rtl) direction *= -1;
      setState(() {
        _previousIndex = _currentIndex;
        _currentIndex = index;
        _isTabTransitioning = true;
        _tabIncomingTransition = Tween<Offset>(
          begin: Offset(direction, 0),
          end: Offset.zero,
        ).animate(_tabTransitionCurve);
        _tabOutgoingTransition = Tween<Offset>(
          begin: currentOffset,
          end: Offset(-direction, 0),
        ).animate(_tabTransitionCurve);
      });
      _tabTransitionController.forward(from: 0);
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

  Widget _buildTabContent() {
    final pageOrder = List<int>.generate(_pages.length, (index) => index)
      ..sort((a, b) => _tabPageLayer(a).compareTo(_tabPageLayer(b)));

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        for (final index in pageOrder)
          Positioned.fill(
            key: ValueKey(index),
            child: Offstage(
              offstage:
                  index != _currentIndex &&
                  (!_isTabTransitioning || index != _previousIndex),
              child: TickerMode(
                enabled:
                    index == _currentIndex ||
                    (_isTabTransitioning && index == _previousIndex),
                child: IgnorePointer(
                  ignoring: index != _currentIndex,
                  child: SlideTransition(
                    position: index == _currentIndex
                        ? _tabIncomingTransition
                        : index == _previousIndex && _isTabTransitioning
                        ? _tabOutgoingTransition
                        : const AlwaysStoppedAnimation(Offset.zero),
                    child: _pages[index],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  int _tabPageLayer(int index) {
    if (_isTabTransitioning && index == _previousIndex) return 1;
    if (index == _currentIndex) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final useFloating = themeState.useFloatingNavBar;
    final scaffoldKey = ref.watch(mainScaffoldKeyProvider);
    final navigationBar = ReviewNavigationBar(
      selectedIndex: _currentIndex,
      onSelected: _onNavigationItemSelected,
      hasBottomInset: MediaQuery.paddingOf(context).bottom > 0,
    );
    return Scaffold(
      key: scaffoldKey,
      drawer: const AppDrawer(),
      extendBody: useFloating,
      body: _buildTabContent(),
      bottomNavigationBar: navigationBar,
    );
  }
}
