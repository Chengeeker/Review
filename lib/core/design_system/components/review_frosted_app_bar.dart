import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const reviewFrostedMaterialAlpha = 0.45;

/// Shared tinted blur layer for standard and custom top bars.
class ReviewFrostedBackdrop extends StatelessWidget {
  const ReviewFrostedBackdrop({
    super.key,
    required this.color,
    required this.borderColor,
    this.child,
    this.showBottomBorder = true,
  });

  final Color color;
  final Color borderColor;
  final Widget? child;
  final bool showBottomBorder;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (child != null) child!,
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: 0.95),
                    color.withValues(alpha: 0),
                  ],
                ),
                border: showBottomBorder
                    ? Border(
                        bottom: BorderSide(
                          color: borderColor.withValues(alpha: 0.24),
                          width: 0.5,
                        ),
                      )
                    : null,
              ),
              child: const SizedBox.expand(),
            ),
          ],
        ),
      ),
    );
  }
}

/// App bar using the timeline's material background and localized blur.
///
/// The translucent color must be painted by the AppBar's Material itself;
/// placing it only in [flexibleSpace] can leave the actual bar transparent.
class ReviewFrostedAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const ReviewFrostedAppBar({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.automaticallyImplyActions = true,
    this.flexibleSpace,
    this.bottom,
    this.showBottomBorder = true,
    this.elevation,
    this.scrolledUnderElevation,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.shadowColor,
    this.shape,
    this.backgroundColor,
    this.foregroundColor,
    this.iconTheme,
    this.actionsIconTheme,
    this.primary = true,
    this.centerTitle,
    this.excludeHeaderSemantics = false,
    this.titleSpacing,
    this.toolbarOpacity = 1,
    this.bottomOpacity = 1,
    this.toolbarHeight,
    this.leadingWidth,
    this.toolbarTextStyle,
    this.titleTextStyle,
    this.systemOverlayStyle,
    this.useDefaultSemanticsOrder = true,
    this.clipBehavior,
    this.actionsPadding,
    this.animateColor = false,
  });

  final Widget? leading;
  final bool automaticallyImplyLeading;
  final Widget? title;
  final List<Widget>? actions;
  final bool automaticallyImplyActions;
  final Widget? flexibleSpace;
  final PreferredSizeWidget? bottom;
  final bool showBottomBorder;
  final double? elevation;
  final double? scrolledUnderElevation;
  final ScrollNotificationPredicate notificationPredicate;
  final Color? shadowColor;
  final ShapeBorder? shape;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final IconThemeData? iconTheme;
  final IconThemeData? actionsIconTheme;
  final bool primary;
  final bool? centerTitle;
  final bool excludeHeaderSemantics;
  final double? titleSpacing;
  final double toolbarOpacity;
  final double bottomOpacity;
  final double? toolbarHeight;
  final double? leadingWidth;
  final TextStyle? toolbarTextStyle;
  final TextStyle? titleTextStyle;
  final SystemUiOverlayStyle? systemOverlayStyle;
  final bool useDefaultSemanticsOrder;
  final Clip? clipBehavior;
  final EdgeInsetsGeometry? actionsPadding;
  final bool animateColor;

  @override
  Size get preferredSize =>
      AppBar(toolbarHeight: toolbarHeight, bottom: bottom).preferredSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor =
        backgroundColor ??
        theme.appBarTheme.backgroundColor ??
        theme.scaffoldBackgroundColor;

    return AppBar(
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      title: title,
      actions: actions,
      automaticallyImplyActions: automaticallyImplyActions,
      flexibleSpace: ReviewFrostedBackdrop(
        color: baseColor,
        borderColor: theme.colorScheme.outlineVariant,
        showBottomBorder: showBottomBorder,
        child: flexibleSpace,
      ),
      bottom: bottom,
      forceMaterialTransparency: false,
      elevation: elevation ?? 0,
      scrolledUnderElevation: scrolledUnderElevation ?? 0,
      notificationPredicate: notificationPredicate,
      shadowColor: shadowColor,
      shape: shape,
      backgroundColor: baseColor.withValues(alpha: reviewFrostedMaterialAlpha),
      surfaceTintColor: Colors.transparent,
      foregroundColor: foregroundColor,
      iconTheme: iconTheme,
      actionsIconTheme: actionsIconTheme,
      primary: primary,
      centerTitle: centerTitle,
      excludeHeaderSemantics: excludeHeaderSemantics,
      titleSpacing: titleSpacing,
      toolbarOpacity: toolbarOpacity,
      bottomOpacity: bottomOpacity,
      toolbarHeight: toolbarHeight,
      leadingWidth: leadingWidth,
      toolbarTextStyle: toolbarTextStyle,
      titleTextStyle: titleTextStyle,
      systemOverlayStyle: systemOverlayStyle,
      useDefaultSemanticsOrder: useDefaultSemanticsOrder,
      clipBehavior: clipBehavior,
      actionsPadding: actionsPadding,
      animateColor: animateColor,
    );
  }
}
