import 'package:flutter/material.dart';

/// 全局无位移原地弹窗函数 (禁止任何从上往下/从下往上的飘动或位移动画)
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color barrierColor = const Color(0x80000000),
  bool useSafeArea = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor,
    transitionDuration: const Duration(milliseconds: 60),
    pageBuilder: (ctx, anim, secAnim) {
      final child = Builder(builder: builder);
      return useSafeArea ? SafeArea(child: child) : child;
    },
    transitionBuilder: (ctx, anim, secAnim, child) {
      // 纯原地微淡入，无任何 Scale/Slide 偏移位移，彻底杜绝从上往下或上下飘动
      return FadeTransition(
        opacity: anim,
        child: child,
      );
    },
  );
}
