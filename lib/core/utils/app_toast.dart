import 'dart:async';
import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// 全局顶层固定位移 Toast HUD
/// 固定吸附在悬浮胶囊底栏正上方（bottom: 84dp），纯原地淡现淡隐，绝不随页面路由位移或飘动
class AppToast {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;
  static GlobalKey<_ToastWidgetState>? _currentKey;

  static void show(
    BuildContext? context,
    String message, {
    Duration duration = const Duration(milliseconds: 2600),
    IconData? icon,
  }) {
    _dismissTimer?.cancel();
    if (_currentEntry != null) {
      try {
        _currentEntry?.remove();
      } catch (_) {}
      _currentEntry = null;
      _currentKey = null;
    }

    final overlayState = context != null
        ? (Navigator.maybeOf(context)?.overlay ?? Overlay.maybeOf(context) ?? rootNavigatorKey.currentState?.overlay)
        : rootNavigatorKey.currentState?.overlay;

    if (overlayState == null) return;

    final isDark = (context != null ? Theme.of(context).brightness : Brightness.light) == Brightness.dark;

    final key = GlobalKey<_ToastWidgetState>();
    _currentKey = key;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _ToastWidget(
        key: key,
        message: message,
        icon: icon,
        isDark: isDark,
      ),
    );

    _currentEntry = entry;
    overlayState.insert(entry);

    _dismissTimer = Timer(duration, () async {
      if (_currentEntry == entry) {
        if (_currentKey == key && key.currentState != null) {
          await key.currentState!.hide();
        }
        if (_currentEntry == entry) {
          try {
            entry.remove();
          } catch (_) {}
          _currentEntry = null;
          _currentKey = null;
        }
      }
    });
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final IconData? icon;
  final bool isDark;

  const _ToastWidget({
    super.key,
    required this.message,
    this.icon,
    required this.isDark,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  Future<void> hide() async {
    if (mounted) {
      await _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 24,
      right: 24,
      bottom: 84, // 固定在悬浮底栏上方，位置绝对静止稳定
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: FadeTransition(
            opacity: _opacity,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              constraints: const BoxConstraints(maxWidth: 340),
              decoration: BoxDecoration(
                color: widget.isDark
                    ? const Color(0xFF2C2D35).withValues(alpha: 0.96)
                    : const Color(0xFF1E1E24).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
