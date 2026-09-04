import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/card_display_provider.dart';
import '../../../core/theme/weibo_style_provider.dart';
import '../../../core/utils/app_dialog.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/widgets/app_avatar.dart';

/// 微博样式个性化设置页面
/// 1. 顶部固定区域：真实头像与 3 张精美照片九宫格无缝实时预览；
/// 2. 底部滑动区域：提供 MD3 Expressive 风格的开关与精细化样式调节项。
class WeiboStyleSettingsPage extends ConsumerWidget {
  const WeiboStyleSettingsPage({super.key});

  static String getCardLayoutTitle(String layout) {
    switch (layout) {
      case 'normal':
        return '普通布局';
      case 'floating_rect':
        return '浮动直角卡片布局';
      case 'floating_rounded':
        return '浮动圆角卡片布局';
      case 'normal_thin_divider':
        return '普通布局（微博间距细小分割线）';
      case 'card_rounded':
      default:
        return '卡片圆角布局';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final style = ref.watch(weiboStyleProvider);
    final notifier = ref.read(weiboStyleProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('微博样式'),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedbackUtil.light();
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. 上方固定区域：真实头像与 3 张照片九宫格实时动态预览
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141416) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            child: _buildLivePreviewCard(context, style, colorScheme, isDark, theme),
          ),

          // 2. 下方滑动区域：MD3 Expressive 开关与设置项
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // ==================== 1. 卡片与时间配置 ====================
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                  child: Text(
                    '卡片与时间显示',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: context.adjustWeight(FontWeight.bold),
                      color: colorScheme.primary,
                      letterSpacing: 0.0,
                    ),
                  ),
                ),
                Card(
                  elevation: 0,
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.1),
                      width: 0.8,
                    ),
                  ),
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    leading: Icon(Icons.schedule_rounded, color: colorScheme.primary),
                    title: Text('时间显示模式', style: TextStyle(fontSize: 15, fontWeight: context.adjustWeight(FontWeight.w600), height: 1.35, letterSpacing: 0.0)),
                    subtitle: Text(
                      ref.watch(cardDisplayProvider).timeDisplayMode == 'relative' ? '智能相对时间 (如3分钟前)' : '绝对具体时间 (如2026-08-29)',
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5, height: 1.4, letterSpacing: 0.0),
                    ),
                    children: [
                      const Divider(height: 1, indent: 56),
                      RadioListTile<String>(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        title: Text('智能相对时间', style: TextStyle(fontSize: 15, fontWeight: context.adjustWeight(FontWeight.w600), height: 1.35, letterSpacing: 0.0)),
                        subtitle: Text('显示“刚刚”、“3分钟前”、“昨天 15:30”等易读时间', style: TextStyle(fontSize: 12.5, height: 1.4, letterSpacing: 0.0, color: colorScheme.onSurfaceVariant)),
                        value: 'relative',
                        groupValue: ref.watch(cardDisplayProvider).timeDisplayMode,
                        onChanged: (val) {
                          HapticFeedbackUtil.light();
                          if (val != null) ref.read(cardDisplayProvider.notifier).setTimeDisplayMode(val);
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      RadioListTile<String>(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        title: Text('绝对具体时间', style: TextStyle(fontSize: 15, fontWeight: context.adjustWeight(FontWeight.w600), height: 1.35, letterSpacing: 0.0)),
                        subtitle: Text('显示“2026-08-29 10:30”等具体年月日时间', style: TextStyle(fontSize: 12.5, height: 1.4, letterSpacing: 0.0, color: colorScheme.onSurfaceVariant)),
                        value: 'absolute',
                        groupValue: ref.watch(cardDisplayProvider).timeDisplayMode,
                        onChanged: (val) {
                          HapticFeedbackUtil.light();
                          if (val != null) ref.read(cardDisplayProvider.notifier).setTimeDisplayMode(val);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        title: Text('显示星期几 (如周五 / Friday)', style: TextStyle(fontSize: 14.5, fontWeight: context.adjustWeight(FontWeight.w500), height: 1.35, letterSpacing: 0.0)),
                        value: ref.watch(cardDisplayProvider).showWeekday,
                        onChanged: (val) {
                          HapticFeedbackUtil.light();
                          ref.read(cardDisplayProvider.notifier).setShowWeekday(val);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        title: Text('显示具体年份 (跨年/强制显示)', style: TextStyle(fontSize: 14.5, fontWeight: context.adjustWeight(FontWeight.w500), height: 1.35, letterSpacing: 0.0)),
                        value: ref.watch(cardDisplayProvider).showYear,
                        onChanged: (val) {
                          HapticFeedbackUtil.light();
                          ref.read(cardDisplayProvider.notifier).setShowYear(val);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        title: Text('显示时区标识 (+0800)', style: TextStyle(fontSize: 14.5, fontWeight: context.adjustWeight(FontWeight.w500), height: 1.35, letterSpacing: 0.0)),
                        value: ref.watch(cardDisplayProvider).showTimezone,
                        onChanged: (val) {
                          HapticFeedbackUtil.light();
                          ref.read(cardDisplayProvider.notifier).setShowTimezone(val);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        title: Text('显示秒数 (HH:mm:ss)', style: TextStyle(fontSize: 14.5, fontWeight: context.adjustWeight(FontWeight.w500), height: 1.35, letterSpacing: 0.0)),
                        value: ref.watch(cardDisplayProvider).showSeconds,
                        onChanged: (val) {
                          HapticFeedbackUtil.light();
                          ref.read(cardDisplayProvider.notifier).setShowSeconds(val);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        title: Text('显示发布设备 / 来自...', style: TextStyle(fontSize: 14.5, fontWeight: context.adjustWeight(FontWeight.w500), height: 1.35, letterSpacing: 0.0)),
                        value: ref.watch(cardDisplayProvider).showSource,
                        onChanged: (val) {
                          HapticFeedbackUtil.light();
                          ref.read(cardDisplayProvider.notifier).setShowSource(val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ==================== 2. 排版与视觉布局 ====================
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                  child: Text(
                    '排版与视觉布局',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: context.adjustWeight(FontWeight.bold),
                      color: colorScheme.primary,
                      letterSpacing: 0.0,
                    ),
                  ),
                ),
                Card(
                  elevation: 0,
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.1),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.dashboard_customize_outlined, color: colorScheme.primary),
                        title: Text('微博背景布局', style: TextStyle(fontSize: 15, fontWeight: context.adjustWeight(FontWeight.w600), height: 1.35, letterSpacing: 0.0)),
                        subtitle: Text(
                          getCardLayoutTitle(style.cardBackgroundLayout),
                          style: TextStyle(color: colorScheme.primary, fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.4, letterSpacing: 0.0),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _showCardLayoutDialog(context, ref, style.cardBackgroundLayout),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: Icon(Icons.format_size_rounded, color: colorScheme.primary),
                        title: Text('正文字体大小', style: TextStyle(fontSize: 15, fontWeight: context.adjustWeight(FontWeight.w600), height: 1.35, letterSpacing: 0.0)),
                        subtitle: Text('${style.fontSize.toInt()} pt', style: TextStyle(color: colorScheme.primary, fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.4, letterSpacing: 0.0)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _showFontSizeDialog(context, ref, style.fontSize),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: Icon(Icons.format_line_spacing_rounded, color: colorScheme.primary),
                        title: Text('正文字体行间距倍数', style: TextStyle(fontSize: 15, fontWeight: context.adjustWeight(FontWeight.w600), height: 1.35, letterSpacing: 0.0)),
                        subtitle: Text('${style.fontLineHeight.toStringAsFixed(1)}x', style: TextStyle(color: colorScheme.primary, fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.4, letterSpacing: 0.0)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _showFontLineHeightDialog(context, ref, style.fontLineHeight),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: Icon(Icons.location_on_outlined, color: colorScheme.primary),
                        title: Text('显示微博发送的 IP 属地', style: TextStyle(fontSize: 15, fontWeight: context.adjustWeight(FontWeight.w600), height: 1.35, letterSpacing: 0.0)),
                        subtitle: Text(
                          style.showIpLocationMode == 'all'
                              ? '列表和详情都显示'
                              : (style.showIpLocationMode == 'detail_only' ? '仅详情显示' : '不显示'),
                          style: TextStyle(color: colorScheme.primary, fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.4, letterSpacing: 0.0),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _showIpLocationDialog(context, ref, style.showIpLocationMode),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ==================== 3. 功能开关与视觉控制 ====================
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                  child: Text(
                    '功能开关与视觉控制',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: context.adjustWeight(FontWeight.bold),
                      color: colorScheme.primary,
                      letterSpacing: 0.0,
                    ),
                  ),
                ),
                Card(
                  elevation: 0,
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.1),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildMD3eSwitch(
                        context: context,
                        title: '链接颜色跟随主题',
                        subtitle: '使用当前个性化主题强调色作为超链接颜色',
                        value: style.linkColorFollowTheme,
                        onChanged: (val) => notifier.setLinkColorFollowTheme(val),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildMD3eSwitch(
                        context: context,
                        title: '同时显示备注和名字',
                        subtitle: '如果存在好友备注，在名称旁标注备注',
                        value: style.showRemarkAndName,
                        onChanged: (val) => notifier.setShowRemarkAndName(val),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildMD3eSwitch(
                        context: context,
                        title: '显示个人主页背景图',
                        subtitle: '在个人主页顶部渲染博主自定义背景封面',
                        value: style.showBackgroundImage,
                        onChanged: (val) => notifier.setShowBackgroundImage(val),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildMD3eSwitch(
                        context: context,
                        title: '显示微博用户活动图标',
                        subtitle: '在博主名称右侧展示认证徽章与活动标识',
                        value: style.showUserActivityIcon,
                        onChanged: (val) => notifier.setShowUserActivityIcon(val),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildMD3eSwitch(
                        context: context,
                        title: '大图片九宫格模式',
                        subtitle: '以大画幅高清展现九宫格图片',
                        value: style.largeImageMode,
                        onChanged: (val) => notifier.setLargeImageMode(val),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildMD3eSwitch(
                        context: context,
                        title: '微博内图片圆角显示',
                        subtitle: '为正文中的九宫格图片与单图添加精致圆角',
                        value: style.roundedImageCorners,
                        onChanged: (val) => notifier.setRoundedImageCorners(val),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildMD3eSwitch(
                        context: context,
                        title: '菜单键显示在底部',
                        subtitle: '将卡片操作菜单（复制/收藏/屏蔽）置于底栏',
                        value: style.showMenuAtBottom,
                        onChanged: (val) => notifier.setShowMenuAtBottom(val),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildMD3eSwitch(
                        context: context,
                        title: '主页显示赞过的微博',
                        subtitle: '在个人中心标签页展示点赞历史记录',
                        value: style.showProfileLikedTweets,
                        onChanged: (val) => notifier.setShowProfileLikedTweets(val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// MD3 Expressive 风格的 SwitchListTile
  Widget _buildMD3eSwitch({
    required BuildContext context,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: context.adjustWeight(FontWeight.w600),
          height: 1.35,
          letterSpacing: 0.0,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
                letterSpacing: 0.0,
              ),
            )
          : null,
      value: value,
      thumbIcon: WidgetStateProperty.resolveWith<Icon?>((Set<WidgetState> states) {
        if (states.contains(WidgetState.selected)) {
          return const Icon(Icons.check, size: 14);
        }
        return const Icon(Icons.close, size: 12);
      }),
      onChanged: (val) {
        HapticFeedbackUtil.light();
        onChanged(val);
      },
    );
  }

  /// 实时动态预览卡片 (支持真实头像、3 张照片真实九宫格与 5 种背景布局)
  Widget _buildLivePreviewCard(
    BuildContext context,
    WeiboStyleSettings style,
    ColorScheme colorScheme,
    bool isDark,
    ThemeData theme,
  ) {
    final linkColor = style.linkColorFollowTheme ? colorScheme.primary : const Color(0xFF3366CC);
    final layout = style.cardBackgroundLayout;
    final isRounded = layout == 'card_rounded' || layout == 'floating_rounded';
    final isFloating = layout == 'floating_rect' || layout == 'floating_rounded';
    final hasThinDivider = layout == 'normal_thin_divider';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: isFloating
              ? const EdgeInsets.symmetric(horizontal: 4, vertical: 4)
              : (layout == 'card_rounded' ? const EdgeInsets.symmetric(horizontal: 2, vertical: 2) : EdgeInsets.zero),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E22) : Colors.white,
            borderRadius: BorderRadius.circular(isRounded ? 16 : 0),
            boxShadow: isFloating
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : (layout == 'card_rounded'
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null),
            border: layout == 'normal'
                ? Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3), width: 0.8))
                : null,
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 头部：真实头像 + 昵称 + 徽章 + 时间/IP/小尾巴 + (右上角菜单)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const AppAvatar(
                    url: 'https://tvax1.sinaimg.cn/crop.0.0.1080.1080.180/006ZdyPily8h1r6z14w3zj30u00u0dhm.jpg',
                    size: 38,
                    name: 'Caij',
                    verified: true,
                    verifiedType: 0,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Caij',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            if (style.showRemarkAndName) ...[
                              const SizedBox(width: 4),
                              Text(
                                '(小蔡)',
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                              ),
                            ],
                            if (style.showUserActivityIcon) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.verified, size: 14, color: colorScheme.primary),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '刚刚'
                          '${style.showIpLocationMode != 'none' ? ' · 北京' : ''}',
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (!style.showMenuAtBottom)
                    IconButton(
                      icon: const Icon(Icons.more_horiz_rounded, size: 20),
                      onPressed: () {},
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // 微博正文与超链接
              Text(
                '微博内容 哈哈哈哈哈哈哈哈哈哈哈哈哈哈 ✨',
                style: TextStyle(
                  fontSize: style.fontSize,
                  height: style.fontLineHeight,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.link_rounded, size: 14, color: linkColor),
                  const SizedBox(width: 2),
                  Text(
                    '网页链接 https://weibo.com',
                    style: TextStyle(
                      fontSize: style.fontSize - 1,
                      color: linkColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 3 张真实照片九宫格网格预览 (1大2小组合)
              ClipRRect(
                borderRadius: BorderRadius.circular(style.roundedImageCorners ? 8 : 0),
                child: SizedBox(
                  height: style.largeImageMode ? 140 : 100,
                  child: Row(
                    children: [
                      // 左侧主图
                      Expanded(
                        flex: 5,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(style.roundedImageCorners ? 6 : 0),
                          child: ExtendedImage.network(
                            'https://picsum.photos/id/1015/600/400',
                            fit: BoxFit.cover,
                            height: double.infinity,
                            width: double.infinity,
                            loadStateChanged: (state) {
                              if (state.extendedImageLoadState != LoadState.completed) {
                                return Container(
                                  color: isDark ? const Color(0xFF2C2D35) : colorScheme.surfaceContainerHigh,
                                  child: Center(
                                    child: Icon(Icons.image_outlined, color: colorScheme.primary, size: 28),
                                  ),
                                );
                              }
                              return null;
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 右侧双图纵向堆叠
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(style.roundedImageCorners ? 6 : 0),
                                child: ExtendedImage.network(
                                  'https://picsum.photos/id/1018/400/300',
                                  fit: BoxFit.cover,
                                  height: double.infinity,
                                  width: double.infinity,
                                  loadStateChanged: (state) {
                                    if (state.extendedImageLoadState != LoadState.completed) {
                                      return Container(
                                        color: isDark ? const Color(0xFF2C2D35) : colorScheme.surfaceContainerHigh,
                                        child: Center(
                                          child: Icon(Icons.image_outlined, color: colorScheme.secondary, size: 20),
                                        ),
                                      );
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(style.roundedImageCorners ? 6 : 0),
                                child: ExtendedImage.network(
                                  'https://picsum.photos/id/1025/400/300',
                                  fit: BoxFit.cover,
                                  height: double.infinity,
                                  width: double.infinity,
                                  loadStateChanged: (state) {
                                    if (state.extendedImageLoadState != LoadState.completed) {
                                      return Container(
                                        color: isDark ? const Color(0xFF2C2D35) : colorScheme.surfaceContainerHigh,
                                        child: Center(
                                          child: Icon(Icons.image_outlined, color: colorScheme.tertiary, size: 20),
                                        ),
                                      );
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // 底部操作栏 (转发 / 评论 / 点赞 / 收藏 / 更多)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Icon(Icons.repeat_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                  Icon(Icons.chat_bubble_outline_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                  Icon(Icons.favorite_border_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                  Icon(Icons.star_border_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                  if (style.showMenuAtBottom)
                    Icon(Icons.more_horiz_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
        if (hasThinDivider)
          Container(
            height: 8,
            width: double.infinity,
            margin: const EdgeInsets.only(top: 4),
            color: isDark ? const Color(0xFF0F0F12) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          ),
      ],
    );
  }

  // 对话框：微博背景布局 (5 种选项)
  void _showCardLayoutDialog(BuildContext context, WidgetRef ref, String current) {
    final options = [
      {'key': 'normal', 'title': '普通布局'},
      {'key': 'floating_rect', 'title': '浮动直角卡片布局'},
      {'key': 'floating_rounded', 'title': '浮动圆角卡片布局'},
      {'key': 'normal_thin_divider', 'title': '普通布局（微博间距细小分割线）'},
      {'key': 'card_rounded', 'title': '卡片圆角布局'},
    ];

    showAppDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择微博背景布局'),
        children: options.map((opt) {
          final isSelected = opt['key'] == current;
          return SimpleDialogOption(
            onPressed: () {
              HapticFeedbackUtil.light();
              ref.read(weiboStyleProvider.notifier).setCardBackgroundLayout(opt['key']!);
              Navigator.pop(ctx);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      opt['title']!,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Theme.of(context).colorScheme.primary : null,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary, size: 18),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // 对话框：字体大小调节
  void _showFontSizeDialog(BuildContext context, WidgetRef ref, double current) {
    final sizes = [13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0];
    showAppDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择正文字体大小'),
        children: sizes.map((s) {
          return SimpleDialogOption(
            onPressed: () {
              HapticFeedbackUtil.light();
              ref.read(weiboStyleProvider.notifier).setWeiboFontSize(s);
              Navigator.pop(ctx);
            },
            child: Text('${s.toInt()} pt', style: TextStyle(fontWeight: s == current ? FontWeight.bold : FontWeight.normal)),
          );
        }).toList(),
      ),
    );
  }

  // 对话框：字体间距(倍数)
  void _showFontLineHeightDialog(BuildContext context, WidgetRef ref, double current) {
    final heights = [1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7];
    showAppDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择字体间距(倍数)'),
        children: heights.map((h) {
          return SimpleDialogOption(
            onPressed: () {
              HapticFeedbackUtil.light();
              ref.read(weiboStyleProvider.notifier).setWeiboFontLineHeight(h);
              Navigator.pop(ctx);
            },
            child: Text('${h.toStringAsFixed(1)} 倍', style: TextStyle(fontWeight: (h - current).abs() < 0.05 ? FontWeight.bold : FontWeight.normal)),
          );
        }).toList(),
      ),
    );
  }

  // 对话框：IP 位置显示模式
  void _showIpLocationDialog(BuildContext context, WidgetRef ref, String current) {
    showAppDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('显示微博发送的 IP 位置'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              HapticFeedbackUtil.light();
              ref.read(weiboStyleProvider.notifier).setShowIpLocationMode('all');
              Navigator.pop(ctx);
            },
            child: Text('列表和详情都显示', style: TextStyle(fontWeight: current == 'all' ? FontWeight.bold : FontWeight.normal)),
          ),
          SimpleDialogOption(
            onPressed: () {
              HapticFeedbackUtil.light();
              ref.read(weiboStyleProvider.notifier).setShowIpLocationMode('detail_only');
              Navigator.pop(ctx);
            },
            child: Text('仅详情显示', style: TextStyle(fontWeight: current == 'detail_only' ? FontWeight.bold : FontWeight.normal)),
          ),
          SimpleDialogOption(
            onPressed: () {
              HapticFeedbackUtil.light();
              ref.read(weiboStyleProvider.notifier).setShowIpLocationMode('none');
              Navigator.pop(ctx);
            },
            child: Text('不显示', style: TextStyle(fontWeight: current == 'none' ? FontWeight.bold : FontWeight.normal)),
          ),
        ],
      ),
    );
  }
}
