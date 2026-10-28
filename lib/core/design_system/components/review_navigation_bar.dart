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
    this.isTransitioning = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool hasBottomInset;
  final bool isTransitioning;

  static LiquidGlassSettings liquidGlassSettingsFor(
    BuildContext context, [
    LiquidGlassSettings? settings,
  ]) {
    final base = settings ?? liquidGlassSettings;
    return Theme.of(context).brightness == Brightness.light
        ? base.copyWith(glassColor: const Color(0xF0FFFFFF), rimLight: 1)
        : base;
  }

  static const liquidGlassSettings = LiquidGlassSettings(
    glassColor: Color(0x66000000),
    bodyMode: GlassBodyMode.clear,
    thickness: 10,
    blur: 2.0,
    lightIntensity: 0.25,
    ambientStrength: 0,
    refractiveIndex: 1.19,
    chromaticAberration: 0.008,
    shadowElevation: 0,
  );
  static const liquidGlassQuality = GlassQuality.premium;

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
        hasBottomInset: hasBottomInset,
        isTransitioning: isTransitioning,
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
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: itemWidth,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          offset: Offset(selectedIndex.toDouble(), 0),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(28),
                            ),
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
    required this.hasBottomInset,
    this.isTransitioning = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool hasBottomInset;
  final bool isTransitioning;

  @override
  State<_LiquidGlassNavigationBar> createState() =>
      _LiquidGlassNavigationBarState();
}

class _LiquidGlassNavigationBarState extends State<_LiquidGlassNavigationBar> {
  static const _longPressThreshold = Duration(milliseconds: 220);
  static const _flickVelocityThreshold = 1000.0;

  int? _activePointer;
  VelocityTracker? _velocityTracker;
  Duration? _pointerDownAt;
  Offset? _pointerDownPosition;
  Timer? _longPressTimer;
  bool _isJellyDragging = false;
  bool _longPressTriggered = false;
  int _selectedIndexAtPointerDown = 0;
  int? _pendingIndex;
  bool _movedBeyondSlop = false;
  bool _draggedHorizontally = false;
  bool _cancelled = false;
  int _gestureId = 0;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _velocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _pointerDownAt = event.timeStamp;
    _pointerDownPosition = event.position;
    _longPressTriggered = false;
    _selectedIndexAtPointerDown = widget.selectedIndex;
    _pendingIndex = null;
    _movedBeyondSlop = false;
    _draggedHorizontally = false;
    _cancelled = false;
    _gestureId++;

    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressThreshold, () {
      if (!mounted || _activePointer != event.pointer) return;
      _longPressTriggered = true;
      setState(() {
        _isJellyDragging = true;
      });
      HapticFeedbackUtil.light();
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _velocityTracker?.addPosition(event.timeStamp, event.position);
    final delta = event.position - _pointerDownPosition!;
    if (delta.distance > kTouchSlop) {
      _movedBeyondSlop = true;
      if (delta.dx.abs() > delta.dy.abs()) {
        _draggedHorizontally = true;
        if (!_isJellyDragging) {
          _longPressTimer?.cancel();
          setState(() {
            _isJellyDragging = true;
          });
        }
      }
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
    _longPressTimer?.cancel();
    _cancelled |= cancelled;
    final gestureId = _gestureId;
    final wasJelly = _isJellyDragging;
    final longPressTriggered = _longPressTriggered;

    scheduleMicrotask(() {
      if (!mounted || gestureId != _gestureId) return;

      final target = _pendingIndex;
      final wasLongPress =
          longPressTriggered ||
          releasedAt - _pointerDownAt! >= _longPressThreshold;
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

      if (wasJelly) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) {
            setState(() => _isJellyDragging = false);
          }
        });
      }

      if (wasCancelled || movedVertically || target == null) return;

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
      _select(index);
    }
  }

  void _select(int index) {
    HapticFeedbackUtil.light();
    widget.onSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLightMode = theme.brightness == Brightness.light;
    final glassSettings = ReviewNavigationBar.liquidGlassSettingsFor(context)
        .copyWith(shadowElevation: isLightMode ? 0.55 : 0);
    final selectedContentColor = isLightMode
        ? theme.colorScheme.primary
        : Colors.white;
    final unselectedContentColor = isLightMode
        ? theme.colorScheme.onSurfaceVariant
        : Colors.white;

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.hasBottomInset ? 6 : 14),
          child: RepaintBoundary(
            child: SizedBox(
              width: ReviewNavigationBar._floatingBarWidth(context),
              height: 56,
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: Stack(
                  children: [
                    GlassTabBar.bottom(
                      tabs: [
                        for (final destination
                            in ReviewNavigationBar._destinations)
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
                      settings: glassSettings,
                      indicatorSettings: LiquidGlassSettings(
                        glassColor: isLightMode
                            ? const Color(0x18000000)
                            : const Color(0x00FFFFFF),
                        bodyMode: isLightMode
                            ? GlassBodyMode.clear
                            : GlassBodyMode.adaptive,
                        refractiveIndex: 1.18,
                        chromaticAberration: 0.025,
                        rimShade: isLightMode ? 0.12 : 0,
                        rimLight: isLightMode ? 0.35 : 0,
                      ),
                      quality: GlassQuality.premium,
                      backgroundQuality: GlassQuality.premium,
                      maskingQuality: MaskingQuality.high,
                      enableBlend: true,
                      indicatorColor: isLightMode
                          ? const Color(0x26000000)
                          : const Color(0x66000000),
                      interactionGlowColor: const Color(0x20FFFFFF),
                      indicatorPinchStrength: _isJellyDragging ? 0.7 : 0.0,
                      indicatorExpansion: _isJellyDragging
                          ? const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            )
                          : EdgeInsets.zero,
                      innerBlur: 6,
                      pressScale: 1.06,
                      selectedIconColor: selectedContentColor,
                      selectedLabelColor: selectedContentColor,
                      unselectedIconColor: unselectedContentColor,
                      unselectedLabelColor: unselectedContentColor,
                    ),
                    if (isLightMode)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            key: const ValueKey('liquid-glass-light-rim'),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9999),
                              border: Border.all(
                                color: const Color(0xF5FFFFFF),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
