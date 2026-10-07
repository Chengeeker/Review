import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/components/review_choice_tile.dart';
import '../../../core/design_system/components/review_page_scaffold.dart';
import '../../../core/design_system/components/review_switch_tile.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/custom_app_icon_provider.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils/app_dialog.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/widgets/app_section_card.dart';
import 'custom_app_icon_page.dart';
import 'screen_refresh_rate_page.dart';

/// 个性化设置页面。
class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  void _showFontWeightDialog(
    BuildContext context,
    WidgetRef ref,
    ThemeState themeState,
  ) {
    HapticFeedbackUtil.light();
    final colorScheme = Theme.of(context).colorScheme;

    const options = [
      {'label': '偏细', 'delta': -100, 'desc': '轻盈精炼视觉，适合大字号阅读'},
      {'label': '默认', 'delta': 0, 'desc': '官方标准字重，最佳均衡排版'},
      {'label': '中等', 'delta': 100, 'desc': '适度加深笔触，更清晰明朗'},
      {'label': '偏粗', 'delta': 200, 'desc': '粗体质感，信息层级更醒目'},
      {'label': '加粗', 'delta': 300, 'desc': '极致浓郁，强视觉冲击力'},
    ];

    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择字体粗细'),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: RadioGroup<int>(
          groupValue: themeState.customFontWeightDelta,
          onChanged: (val) {
            if (val == null) return;
            HapticFeedbackUtil.light();
            ref.read(themeProvider.notifier).setUseCustomFontWeight(true);
            ref.read(themeProvider.notifier).setCustomFontWeightDelta(val);
            Navigator.pop(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final label = opt['label'] as String;
              final delta = opt['delta'] as int;
              final desc = opt['desc'] as String;
              final isSelected = themeState.customFontWeightDelta == delta;

              return RadioListTile<int>(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 2,
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: context.adjustWeight(
                      isSelected ? FontWeight.bold : FontWeight.w600,
                    ),
                    color: isSelected ? colorScheme.primary : null,
                  ),
                ),
                subtitle: Text(
                  desc,
                  style: TextStyle(
                    fontSize: 14,
                    color: isSelected
                        ? colorScheme.primary.withValues(alpha: 0.8)
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                value: delta,
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final iconState = ref.watch(customAppIconProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return ReviewPageScaffold(
      title: '个性化',
      bodyBuilder: (context, contentInsets) => ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ).add(contentInsets),
        children: [
          // 1. 明暗模式 (Theme Mode)
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Text(
                    '明暗模式',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: context.adjustWeight(FontWeight.bold),
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.0,
                    ),
                  ),
                ),
                ReviewChoiceTile<ThemeMode>(
                  title: '跟随系统',
                  summary: '自动匹配系统深色/浅色设置',
                  value: ThemeMode.system,
                  groupValue: themeState.themeMode,
                  onSelected: () => ref
                      .read(themeProvider.notifier)
                      .setThemeMode(ThemeMode.system),
                ),
                const Divider(height: 1, indent: 72),
                ReviewChoiceTile<ThemeMode>(
                  title: '浅色模式',
                  value: ThemeMode.light,
                  groupValue: themeState.themeMode,
                  onSelected: () => ref
                      .read(themeProvider.notifier)
                      .setThemeMode(ThemeMode.light),
                ),
                const Divider(height: 1, indent: 72),
                ReviewChoiceTile<ThemeMode>(
                  title: '深色模式',
                  value: ThemeMode.dark,
                  groupValue: themeState.themeMode,
                  onSelected: () => ref
                      .read(themeProvider.notifier)
                      .setThemeMode(ThemeMode.dark),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ReviewSwitchTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 3,
                  ),
                  leading: Icon(
                    Icons.contrast_rounded,
                    color: colorScheme.primary,
                  ),
                  title: '纯黑深色模式',
                  value: themeState.isPureBlackDark,
                  onChanged: (val) {
                    HapticFeedbackUtil.light();
                    ref.read(themeProvider.notifier).setPureBlackDark(val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 色彩方案 (Color Palette)
          AppSectionCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                    child: Text(
                      '色彩方案',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: context.adjustWeight(FontWeight.bold),
                        color: colorScheme.onSurfaceVariant,
                        letterSpacing: 0.0,
                      ),
                    ),
                  ),
                  ReviewSwitchTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 3,
                    ),
                    leading: Icon(
                      Icons.auto_awesome_outlined,
                      color: colorScheme.primary,
                    ),
                    title: 'Material You (Monet) 动态取色',
                    summary: '从 Android 12+ 壁纸自动提取主色调',
                    value: themeState.useDynamicColor,
                    onChanged: (val) {
                      HapticFeedbackUtil.light();
                      ref.read(themeProvider.notifier).setUseDynamicColor(val);
                    },
                  ),
                  if (!themeState.useDynamicColor) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        top: 14,
                        bottom: 10,
                      ),
                      child: Text(
                        'Material 3 预置主题色',
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurfaceVariant,
                          height: 1.35,
                          letterSpacing: 0.0,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: List.generate(AppTheme.themeColors.length, (
                          idx,
                        ) {
                          final item = AppTheme.themeColors[idx];
                          final name = item['name'] as String;
                          final color = item['color'] as Color;
                          final isSelected = themeState.themeColorIndex == idx;

                          return ChoiceChip(
                            avatar: CircleAvatar(
                              backgroundColor: color,
                              radius: 10,
                            ),
                            label: Text(name),
                            selected: isSelected,
                            onSelected: (_) {
                              HapticFeedbackUtil.light();
                              ref
                                  .read(themeProvider.notifier)
                                  .setThemeColorIndex(idx);
                            },
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3. 字体粗细 (Font Weight - 弹窗选择 5 档：偏细、默认、中等、偏粗、加粗)
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    '字体粗细',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: context.adjustWeight(FontWeight.bold),
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.0,
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 3,
                  ),
                  leading: Icon(
                    Icons.format_bold_rounded,
                    color: colorScheme.primary,
                  ),
                  title: Text(
                    '自定义应用字体粗细',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: context.adjustWeight(FontWeight.w600),
                      height: 1.35,
                      letterSpacing: 0.0,
                    ),
                  ),
                  subtitle: Text(
                    '当前：${_getFontWeightLabel(themeState.customFontWeightDelta)}',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      letterSpacing: 0.0,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showFontWeightDialog(context, ref, themeState),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '效果预览 (${_getFontWeightLabel(themeState.customFontWeightDelta)})',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: context.adjustWeight(FontWeight.w600),
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Review 极简现代体验：这是一段用于预览字体粗细的示例文本。@开发者 #超话#',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: context.adjustWeight(FontWeight.normal),
                          letterSpacing: 0.0,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 底部导航
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    '底部导航',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: context.adjustWeight(FontWeight.bold),
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.0,
                    ),
                  ),
                ),
                ReviewSwitchTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 3,
                  ),
                  leading: Icon(Icons.dock_rounded, color: colorScheme.primary),
                  title: '使用悬浮底栏',
                  summary: '居中显示悬浮式导航栏',
                  value: themeState.useFloatingNavBar,
                  onChanged: (val) {
                    HapticFeedbackUtil.light();
                    ref.read(themeProvider.notifier).setUseFloatingNavBar(val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5. 自定义应用图标 (Custom App Icon)
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    '应用图标',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: context.adjustWeight(FontWeight.bold),
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.0,
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 3,
                  ),
                  leading: Icon(
                    Icons.app_shortcut_rounded,
                    color: colorScheme.primary,
                  ),
                  title: Text(
                    '自定义应用图标',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: context.adjustWeight(FontWeight.w600),
                      height: 1.35,
                      letterSpacing: 0.0,
                    ),
                  ),
                  subtitle: Text(
                    iconState.currentDisplayName,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      letterSpacing: 0.0,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CustomAppIconPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 6. 屏幕帧率设置 (Screen Refresh Rate)
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    '屏幕显示',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: context.adjustWeight(FontWeight.bold),
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.0,
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 3,
                  ),
                  leading: Icon(
                    Icons.speed_rounded,
                    color: colorScheme.primary,
                  ),
                  title: Text(
                    '屏幕帧率设置',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: context.adjustWeight(FontWeight.w600),
                      height: 1.35,
                      letterSpacing: 0.0,
                    ),
                  ),
                  subtitle: Text(
                    _getRefreshRateLabel(themeState.screenRefreshRateMode),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      letterSpacing: 0.0,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ScreenRefreshRatePage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 7. 触感与震动 (Haptic Feedback)
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    '触感与震动',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: context.adjustWeight(FontWeight.bold),
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.0,
                    ),
                  ),
                ),
                ReviewSwitchTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 3,
                  ),
                  leading: Icon(
                    Icons.vibration_rounded,
                    color: colorScheme.primary,
                  ),
                  title: '触感与震动反馈',
                  summary: '按键、卡片点击、手势滑动与底栏切换的触感反馈',
                  value: themeState.enableHaptics,
                  onChanged: (val) {
                    ref.read(themeProvider.notifier).setEnableHaptics(val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _getRefreshRateLabel(int mode) {
    switch (mode) {
      case 1:
        return '原生分辨率 120Hz';
      case 2:
        return '原生分辨率 90Hz';
      case 3:
        return '原生分辨率 72Hz';
      case 4:
        return '原生分辨率 60Hz';
      case 5:
        return '1080P 120Hz';
      case 6:
        return '1080P 90Hz';
      case 7:
        return '1080P 72Hz';
      case 8:
        return '1080P 60Hz';
      case 0:
      default:
        return '自动';
    }
  }

  static String _getFontWeightLabel(int delta) {
    switch (delta) {
      case -100:
        return '偏细';
      case 100:
        return '中等';
      case 200:
        return '偏粗';
      case 300:
        return '加粗';
      case 0:
      default:
        return '默认';
    }
  }
}
