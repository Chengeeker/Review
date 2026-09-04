import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
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

  @override
  void dispose() {
    _timelineSingleTapTimer?.cancel();
    super.dispose();
  }

  final List<Widget> _pages = const [
    FeedView(),
    HotTrendsView(),
    SettingsView(),
  ];

  void _onNavigationItemSelected(int index) {
    if (index != _currentIndex) {
      _timelineSingleTapTimer?.cancel();
      _lastTimelineTapTime = null;
      setState(() => _currentIndex = index);
      return;
    }

    // 用户在当前“时间线”页面上再次点击时间线底栏
    if (index == 0) {
      final now = DateTime.now();
      if (_lastTimelineTapTime != null &&
          now.difference(_lastTimelineTapTime!) < const Duration(milliseconds: 300)) {
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final themeState = ref.watch(themeProvider);
    final useFloating = themeState.useFloatingNavBar;
    final scaffoldKey = ref.watch(mainScaffoldKeyProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final standardNavBar = NavigationBar(
      selectedIndex: _currentIndex,
      elevation: 0,
      height: 68,
      backgroundColor: colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: isDark
          ? colorScheme.secondaryContainer
          : colorScheme.primaryContainer,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: _onNavigationItemSelected,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dynamic_feed_outlined),
          selectedIcon: Icon(Icons.dynamic_feed_rounded),
          label: '时间线',
        ),
        NavigationDestination(
          icon: Icon(Icons.local_fire_department_outlined),
          selectedIcon: Icon(Icons.local_fire_department_rounded),
          label: '热搜',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: '设置',
        ),
      ],
    );

    final floatingCapsuleBar = Container(
      width: 280,
      height: 64,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222328) : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildCapsuleItem(
            index: 0,
            icon: Icons.dynamic_feed_outlined,
            selectedIcon: Icons.dynamic_feed_rounded,
            label: '时间线',
            isDark: isDark,
            colorScheme: colorScheme,
          ),
          _buildCapsuleItem(
            index: 1,
            icon: Icons.local_fire_department_outlined,
            selectedIcon: Icons.local_fire_department_rounded,
            label: '热搜',
            isDark: isDark,
            colorScheme: colorScheme,
          ),
          _buildCapsuleItem(
            index: 2,
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
            label: '设置',
            isDark: isDark,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );

    return Scaffold(
      key: scaffoldKey,
      drawer: const AppDrawer(),
      extendBody: useFloating,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: useFloating
          ? SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomPadding > 0 ? 6 : 14),
                  child: floatingCapsuleBar,
                ),
              ),
            )
          : standardNavBar,
    );
  }

  Widget _buildCapsuleItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool isDark,
    required ColorScheme colorScheme,
  }) {
    final isSelected = _currentIndex == index;
    final activeBgColor = isDark
        ? const Color(0xFF383A40)
        : colorScheme.secondaryContainer;
    final activeContentColor = isDark
        ? Colors.white
        : colorScheme.onSecondaryContainer;
    final inactiveContentColor = isDark
        ? const Color(0xFFB0B2B8)
        : colorScheme.onSurfaceVariant;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          onTap: () => _onNavigationItemSelected(index),
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              // 胶囊背景：选中的项平滑淡入出现，未选中的项立刻消失，彻底杜绝中间态色彩闪烁
              if (isSelected)
                TweenAnimationBuilder<double>(
                  key: ValueKey(index),
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Container(
                        decoration: BoxDecoration(
                          color: activeBgColor,
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                    );
                  },
                ),
              // 图标与文字内容
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isSelected ? selectedIcon : icon,
                    size: 22,
                    color: isSelected ? activeContentColor : inactiveContentColor,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected
                          ? context.adjustWeight(FontWeight.w600)
                          : context.adjustWeight(FontWeight.w400),
                      color: isSelected ? activeContentColor : inactiveContentColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
