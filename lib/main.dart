import 'package:dynamic_color/dynamic_color.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/services/link_routing_service.dart';
import 'core/storage/storage_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/utils/app_toast.dart';
import 'core/utils/haptic_feedback_util.dart';
import 'features/home/presentation/main_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Storage Service (SharedPreferences)
  final storageService = await StorageService.init();

  // Initialize Global Deep Link & App Links Router
  LinkRoutingService.initDeepLinkListener(rootNavigatorKey);

  // Global EasyRefresh localization (Pure Chinese Strings)
  EasyRefresh.defaultHeaderBuilder = () => const ClassicHeader(
    dragText: '下拉刷新',
    armedText: '释放立即刷新',
    readyText: '正在刷新...',
    processingText: '正在刷新...',
    processedText: '刷新成功',
    noMoreText: '没有更多了',
    failedText: '刷新失败',
    messageText: '最后更新于 %T',
    showMessage: true,
  );

  EasyRefresh.defaultFooterBuilder = () => const ClassicFooter(
    dragText: '上拉加载',
    armedText: '释放立即加载',
    readyText: '正在加载...',
    processingText: '正在加载...',
    processedText: '加载完成',
    noMoreText: '没有更多了',
    failedText: '加载失败',
    messageText: '最后更新于 %T',
    showMessage: true,
  );

  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
      ],
      child: const WBTestApp(),
    ),
  );
}

class WBTestApp extends ConsumerWidget {
  const WBTestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    HapticFeedbackUtil.isEnabled = themeState.enableHaptics;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final lightTheme = AppTheme.lightTheme(
          dynamicColorScheme: themeState.useDynamicColor ? lightDynamic : null,
          colorIndex: themeState.themeColorIndex,
          fontWeightAdjustment: themeState.effectiveFontWeightAdjustment,
        );
        final darkTheme = AppTheme.darkTheme(
          dynamicColorScheme: themeState.useDynamicColor ? darkDynamic : null,
          colorIndex: themeState.themeColorIndex,
          isPureBlack: themeState.isPureBlackDark,
          fontWeightAdjustment: themeState.effectiveFontWeightAdjustment,
        );

        return MaterialApp(
          navigatorKey: rootNavigatorKey,
          title: 'Review',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeState.themeMode,
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh', 'CN'),
          ],
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final currentTheme = isDark ? darkTheme : lightTheme;
            return DefaultTextStyle(
              style: currentTheme.textTheme.bodyMedium ?? const TextStyle(),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const MainScaffold(),
        );
      },
    );
  }
}
