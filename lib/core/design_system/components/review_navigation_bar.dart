import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop, VelocityTracker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_provider.dart';
import '../../utils/haptic_feedback_util.dart';

/// Material 3 navigation shared by the app shell.
class ReviewNavigationBar extends ConsumerWidget {
  const ReviewNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.hasBottomInset,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool hasBottomInset;

  static const _destinations = <_NavigationDestination>[
    _NavigationDestination(
      icon: Icons.dynamic_feed_outlined,
      selectedIcon: Icons.dynamic_feed_rounded,
      label: '时间线',
    ),
    _NavigationDestination(
      icon: Icons.local_fire_department_outlined,
      selectedIcon: Icons.local_fire_department_rounded,
      label: '热搜',
    ),
    _NavigationDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      label: '设置',
    ),
  ];

  static double _floatingBarWidth(BuildContext context) =>
      math.min(440.0, MediaQuery.sizeOf(context).width - 40.0).toDouble() *
      2 /
      3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useFloating = ref.watch(
      themeProvider.select((state) => state.useFloatingNavBar),
    );
    final useLiquidGlass = ref.watch(
      themeProvider.select((state) => state.useLiquidGlass),
    );
    final colorScheme = Theme.of(context).colorScheme;

    if (!useFloating) {
      return NavigationBar(
        selectedIndex: selectedIndex,
        elevation: 0,
        height: 68,
        onDestinationSelected: onSelected,
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      );
    }

    if (useLiquidGlass) {
      return _LiquidGlassNavigationBar(
        selectedIndex: selectedIndex,
        onSelected: onSelected,
      );
    }

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: hasBottomInset ? 6 : 14),
          child: Container(
            width: _floatingBarWidth(context),
            height: 56,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.35
                        : 0.12,
                  ),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / _destinations.length;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        left: itemWidth * selectedIndex,
                        top: 0,
                        bottom: 0,
                        width: itemWidth,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                      ),
                      Row(
                        children: List.generate(
                          _destinations.length,
                          (index) => Expanded(
                            child: _buildFloatingItem(
                              context,
                              index,
                              colorScheme,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingItem(
    BuildContext context,
    int index,
    ColorScheme colorScheme,
  ) {
    final selected = selectedIndex == index;
    final destination = _destinations[index];
    final activeContent = colorScheme.onSecondaryContainer;
    final inactiveContent = colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        onTap: () => onSelected(index),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    key: ValueKey(selected),
                    size: 22,
                    color: selected ? activeContent : inactiveContent,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: context.adjustWeight(
                      selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    color: selected ? activeContent : inactiveContent,
                  ),
                  child: Text(destination.label),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationDestination {
  const _NavigationDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _LiquidGlassNavigationBar extends StatefulWidget {
  const _LiquidGlassNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<_LiquidGlassNavigationBar> createState() =>
      _LiquidGlassNavigationBarState();
}

class _LiquidGlassNavigationBarState extends State<_LiquidGlassNavigationBar> {
  static const _longPressThreshold = Duration(milliseconds: 500);
  static const _flickVelocityThreshold = 1000.0;

  int? _activePointer;
  VelocityTracker? _velocityTracker;
  Duration? _pointerDownAt;
  Offset? _pointerDownPosition;
  int _selectedIndexAtPointerDown = 0;
  int? _pendingIndex;
  bool _movedBeyondSlop = false;
  bool _draggedHorizontally = false;
  bool _cancelled = false;
  int _gestureId = 0;

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _velocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _pointerDownAt = event.timeStamp;
    _pointerDownPosition = event.position;
    _selectedIndexAtPointerDown = widget.selectedIndex;
    _pendingIndex = null;
    _movedBeyondSlop = false;
    _draggedHorizontally = false;
    _cancelled = false;
    _gestureId++;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _velocityTracker?.addPosition(event.timeStamp, event.position);
    final delta = event.position - _pointerDownPosition!;
    if (delta.distance > kTouchSlop) {
      _movedBeyondSlop = true;
      if (delta.dx.abs() > delta.dy.abs()) _draggedHorizontally = true;
    }
  }

  void _onPointerUp(PointerUpEvent event) => _finishPointer(
    event.pointer,
    event.timeStamp,
    horizontalVelocity: _velocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0,
  );

  void _onPointerCancel(PointerCancelEvent event) =>
      _finishPointer(event.pointer, event.timeStamp, cancelled: true);

  void _finishPointer(
    int pointer,
    Duration releasedAt, {
    bool cancelled = false,
    double horizontalVelocity = 0,
  }) {
    if (pointer != _activePointer) return;
    _cancelled |= cancelled;
    final gestureId = _gestureId;
    scheduleMicrotask(() {
      if (!mounted || gestureId != _gestureId) return;

      final target = _pendingIndex;
      final wasLongPress = releasedAt - _pointerDownAt! >= _longPressThreshold;
      final wasDrag = _draggedHorizontally;
      final movedVertically = _movedBeyondSlop && !wasDrag;
      final wasCancelled = _cancelled;
      final startingIndex = _selectedIndexAtPointerDown;

      _activePointer = null;
      _velocityTracker = null;
      _pointerDownAt = null;
      _pointerDownPosition = null;
      _pendingIndex = null;
      _movedBeyondSlop = false;
      _draggedHorizontally = false;
      _cancelled = false;

      if (wasCancelled || movedVertically || target == null) return;

      // Only a fast release is capped; a deliberate drag follows its final tab.
      final isFastFlick =
          wasDrag && horizontalVelocity.abs() >= _flickVelocityThreshold;
      final selectedTarget = isFastFlick
          ? target.clamp(startingIndex - 1, startingIndex + 1).toInt()
          : target;
      if ((wasDrag || wasLongPress) && selectedTarget == startingIndex) return;
      _select(selectedTarget);
    });
  }

  void _onTabSelected(int index) {
    if (_activePointer != null) {
      _pendingIndex = index;
    } else {
      // Keep keyboard and screen-reader activation immediate.
      _select(index);
    }
  }

  void _select(int index) {
    HapticFeedbackUtil.light();
    widget.onSelected(index);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    minimum: const EdgeInsets.only(bottom: 21),
    child: Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: ReviewNavigationBar._floatingBarWidth(context),
        height: 56,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: GlassTabBar.bottom(
            tabs: [
              for (final destination in ReviewNavigationBar._destinations)
                GlassTab(
                  icon: Icon(destination.icon),
                  activeIcon: Icon(destination.selectedIcon),
                  label: destination.label,
                ),
            ],
            selectedIndex: widget.selectedIndex,
            onTabSelected: _onTabSelected,
            barHeight: 56,
            horizontalPadding: 0,
            verticalPadding: 0,
            barBorderRadius: 9999,
            indicatorBorderRadius: 9999,
            settings: const LiquidGlassSettings(
              glassColor: Color(0x66000000),
              bodyMode: GlassBodyMode.clear,
              thickness: 10,
              blur: 2.0,
              lightIntensity: 0.25,
              ambientStrength: 0,
              refractiveIndex: 1.19,
              chromaticAberration: 0.008,
              shadowElevation: 0,
            ),
            indicatorSettings: const LiquidGlassSettings(
              refractiveIndex: 1.18,
              chromaticAberration: 0.025,
            ),
            quality: GlassQuality.premium,
            backgroundQuality: GlassQuality.premium,
            indicatorColor: const Color(0x66000000),
            interactionGlowColor: const Color(0x20FFFFFF),
            indicatorPinchStrength: 0.7,
            innerBlur: 6,
            pressScale: 1.06,
            selectedIconColor: Colors.white,
            selectedLabelColor: Colors.white,
            unselectedIconColor: Colors.white,
            unselectedLabelColor: Colors.white,
          ),
        ),
      ),
    ),
  );
}
