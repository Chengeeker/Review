import 'package:flutter/material.dart';
import '../utils/haptic_feedback_util.dart';

/// Material Design 3 Palette and OLED Pure Black Definition
class AppTheme {
  AppTheme._();

  // Preset Theme Color Palettes
  static const List<Map<String, dynamic>> themeColors = [
    {'name': '经典红', 'color': Color(0xFFFA2F3A)},
    {'name': '活力橙', 'color': Color(0xFFFF8200)},
    {'name': '极光蓝', 'color': Color(0xFF1976D2)},
    {'name': '翡翠绿', 'color': Color(0xFF2E7D32)},
    {'name': '优雅紫', 'color': Color(0xFF7B1FA2)},
    {'name': '樱花粉', 'color': Color(0xFFE91E63)},
    {'name': '青碧色', 'color': Color(0xFF00897B)},
    {'name': '经典黑灰', 'color': Color(0xFF455A64)},
  ];

  static Color getSeedColor(int index) {
    if (index >= 0 && index < themeColors.length) {
      return themeColors[index]['color'] as Color;
    }
    return const Color(0xFFFA2F3A);
  }

  static FontWeight adjustFontWeight(FontWeight base, int adjustment) {
    if (adjustment == 0) return base;
    final step = (adjustment / 100).round();
    final currentIndex = (base.value ~/ 100) - 1;
    final targetIndex = (currentIndex + step).clamp(0, FontWeight.values.length - 1);
    return FontWeight.values[targetIndex];
  }

  static TextTheme _adjustTextThemeFontWeights(TextTheme theme, int adjustment) {
    TextStyle? adj(TextStyle? style) {
      if (style == null) return null;
      final currentWeight = style.fontWeight ?? FontWeight.w400;
      return style.copyWith(
        fontWeight: adjustFontWeight(currentWeight, adjustment),
        letterSpacing: 0.0,
      );
    }

    return theme.copyWith(
      displayLarge: adj(theme.displayLarge),
      displayMedium: adj(theme.displayMedium),
      displaySmall: adj(theme.displaySmall),
      headlineLarge: adj(theme.headlineLarge),
      headlineMedium: adj(theme.headlineMedium),
      headlineSmall: adj(theme.headlineSmall),
      titleLarge: adj(theme.titleLarge),
      titleMedium: adj(theme.titleMedium),
      titleSmall: adj(theme.titleSmall),
      bodyLarge: adj(theme.bodyLarge),
      bodyMedium: adj(theme.bodyMedium),
      bodySmall: adj(theme.bodySmall),
      labelLarge: adj(theme.labelLarge),
      labelMedium: adj(theme.labelMedium),
      labelSmall: adj(theme.labelSmall),
    );
  }

  static TextTheme _buildAdjustedTextTheme({
    required bool isDark,
    required ColorScheme scheme,
    required int fontWeightAdjustment,
  }) {
    final baseTypography = Typography.material2021(platform: TargetPlatform.android);
    final rawTextTheme = isDark ? baseTypography.white : baseTypography.black;
    final textTheme = _adjustTextThemeFontWeights(rawTextTheme, fontWeightAdjustment);

    return textTheme.copyWith(
      bodyLarge: textTheme.bodyLarge?.copyWith(color: scheme.onSurface, letterSpacing: 0.0),
      bodyMedium: textTheme.bodyMedium?.copyWith(color: scheme.onSurface, letterSpacing: 0.0),
      bodySmall: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.0),
      titleLarge: textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: adjustFontWeight(FontWeight.bold, fontWeightAdjustment),
        letterSpacing: 0.0,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(
        color: scheme.onSurface,
        fontWeight: adjustFontWeight(FontWeight.w600, fontWeightAdjustment),
        letterSpacing: 0.0,
      ),
      titleSmall: textTheme.titleSmall?.copyWith(
        color: scheme.onSurfaceVariant,
        fontWeight: adjustFontWeight(FontWeight.w600, fontWeightAdjustment),
        letterSpacing: 0.0,
      ),
      labelLarge: textTheme.labelLarge?.copyWith(
        fontWeight: adjustFontWeight(FontWeight.w600, fontWeightAdjustment),
        letterSpacing: 0.0,
      ),
      labelMedium: textTheme.labelMedium?.copyWith(
        fontWeight: adjustFontWeight(FontWeight.w500, fontWeightAdjustment),
        letterSpacing: 0.0,
      ),
    );
  }

  static ThemeData lightTheme({
    ColorScheme? dynamicColorScheme,
    int colorIndex = 0,
    int fontWeightAdjustment = 0,
  }) {
    final seed = getSeedColor(colorIndex);
    final scheme = dynamicColorScheme ??
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        );

    final textTheme = _buildAdjustedTextTheme(
      isDark: false,
      scheme: scheme,
      fontWeightAdjustment: fontWeightAdjustment,
    );

    return ThemeData(
      useMaterial3: true,
      splashFactory: const HapticSplashFactory(),
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: adjustFontWeight(FontWeight.bold, fontWeightAdjustment),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.25),
            width: 0.8,
          ),
        ),
        color: scheme.surfaceContainerLowest,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        minVerticalPadding: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: TextStyle(
          fontWeight: adjustFontWeight(FontWeight.w600, fontWeightAdjustment),
          color: scheme.onSurface,
          fontSize: 15,
          height: 1.35,
          letterSpacing: 0.0,
        ),
        subtitleTextStyle: TextStyle(
          fontWeight: adjustFontWeight(FontWeight.normal, fontWeightAdjustment),
          color: scheme.onSurfaceVariant,
          fontSize: 12.5,
          height: 1.4,
          letterSpacing: 0.0,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: TextStyle(
          fontWeight: adjustFontWeight(FontWeight.bold, fontWeightAdjustment),
          fontSize: 15,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: adjustFontWeight(FontWeight.normal, fontWeightAdjustment),
          fontSize: 15,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: adjustFontWeight(FontWeight.bold, fontWeightAdjustment),
          color: scheme.onSurface,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: adjustFontWeight(FontWeight.normal, fontWeightAdjustment),
          color: scheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
        dragHandleSize: const Size(38, 4.5),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 1.5,
        highlightElevation: 3,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      ),
      searchBarTheme: SearchBarThemeData(
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: scheme.onPrimaryContainer);
          }
          return IconThemeData(color: scheme.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: adjustFontWeight(FontWeight.bold, fontWeightAdjustment),
              color: scheme.primary,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: adjustFontWeight(FontWeight.w500, fontWeightAdjustment),
            color: scheme.onSurfaceVariant,
          );
        }),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.3),
        thickness: 0.5,
      ),
    );
  }

  static ThemeData darkTheme({
    ColorScheme? dynamicColorScheme,
    int colorIndex = 0,
    bool isPureBlack = false,
    int fontWeightAdjustment = 0,
  }) {
    final seed = getSeedColor(colorIndex);
    final scheme = dynamicColorScheme ??
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        );

    final bgColor = isPureBlack ? Colors.black : const Color(0xFF111215);
    final cardColor = isPureBlack ? const Color(0xFF121212) : const Color(0xFF1B1C20);
    final appBarColor = isPureBlack ? Colors.black : const Color(0xFF111215);
    final navBgColor = isPureBlack ? Colors.black : const Color(0xFF16171B);

    final effectiveScheme = isPureBlack
        ? scheme.copyWith(
            surface: Colors.black,
            surfaceContainer: const Color(0xFF121212),
            surfaceContainerHigh: const Color(0xFF181818),
            surfaceContainerHighest: const Color(0xFF222222),
          )
        : scheme;

    final textTheme = _buildAdjustedTextTheme(
      isDark: true,
      scheme: effectiveScheme,
      fontWeightAdjustment: fontWeightAdjustment,
    );

    return ThemeData(
      useMaterial3: true,
      splashFactory: const HapticSplashFactory(),
      colorScheme: effectiveScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: bgColor,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: effectiveScheme.onSurface,
          fontSize: 18,
          fontWeight: adjustFontWeight(FontWeight.bold, fontWeightAdjustment),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: isPureBlack
                ? Colors.white.withValues(alpha: 0.12)
                : effectiveScheme.outlineVariant.withValues(alpha: 0.2),
            width: 0.8,
          ),
        ),
        color: cardColor,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        minVerticalPadding: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: TextStyle(
          fontWeight: adjustFontWeight(FontWeight.w600, fontWeightAdjustment),
          color: effectiveScheme.onSurface,
          fontSize: 15,
          height: 1.35,
          letterSpacing: 0.0,
        ),
        subtitleTextStyle: TextStyle(
          fontWeight: adjustFontWeight(FontWeight.normal, fontWeightAdjustment),
          color: effectiveScheme.onSurfaceVariant,
          fontSize: 12.5,
          height: 1.4,
          letterSpacing: 0.0,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: TextStyle(
          fontWeight: adjustFontWeight(FontWeight.bold, fontWeightAdjustment),
          fontSize: 15,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: adjustFontWeight(FontWeight.normal, fontWeightAdjustment),
          fontSize: 15,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: adjustFontWeight(FontWeight.bold, fontWeightAdjustment),
          color: effectiveScheme.onSurface,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: adjustFontWeight(FontWeight.normal, fontWeightAdjustment),
          color: effectiveScheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isPureBlack ? const Color(0xFF141414) : effectiveScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: effectiveScheme.onSurfaceVariant.withValues(alpha: 0.4),
        dragHandleSize: const Size(38, 4.5),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 1.5,
        highlightElevation: 3,
        backgroundColor: effectiveScheme.primaryContainer,
        foregroundColor: effectiveScheme.onPrimaryContainer,
      ),
      searchBarTheme: SearchBarThemeData(
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(isPureBlack ? const Color(0xFF1C1C1E) : effectiveScheme.surfaceContainerHigh),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: navBgColor,
        surfaceTintColor: Colors.transparent,
        indicatorColor: effectiveScheme.primaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: effectiveScheme.onPrimaryContainer);
          }
          return IconThemeData(color: effectiveScheme.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: adjustFontWeight(FontWeight.bold, fontWeightAdjustment),
              color: effectiveScheme.primary,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: adjustFontWeight(FontWeight.w500, fontWeightAdjustment),
            color: effectiveScheme.onSurfaceVariant,
          );
        }),
      ),
      dividerTheme: DividerThemeData(
        color: isPureBlack
            ? Colors.white.withValues(alpha: 0.1)
            : effectiveScheme.outlineVariant.withValues(alpha: 0.2),
        thickness: 0.5,
      ),
    );
  }
}

extension FontAdjustmentExtension on BuildContext {
  /// 智能根据系统全局字体粗细动态调整给定的基准 FontWeight
  FontWeight adjustWeight(FontWeight base) {
    final theme = Theme.of(this);
    final baseBodyWeight = theme.textTheme.bodyMedium?.fontWeight ?? FontWeight.w400;
    final delta = (baseBodyWeight.value - FontWeight.w400.value);
    return AppTheme.adjustFontWeight(base, delta);
  }
}
