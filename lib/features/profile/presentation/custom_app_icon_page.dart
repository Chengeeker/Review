import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/custom_app_icon_provider.dart';
import '../../../core/utils/app_dialog.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/haptic_feedback_util.dart';

/// 自定义应用图标选择页面 (预设官方图标自由切换)
class CustomAppIconPage extends ConsumerStatefulWidget {
  const CustomAppIconPage({super.key});

  @override
  ConsumerState<CustomAppIconPage> createState() => _CustomAppIconPageState();
}

class _CustomAppIconPageState extends ConsumerState<CustomAppIconPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customAppIconProvider.notifier).syncWithSystem();
    });
  }

  Future<void> _confirmSwitchIcon(
    PresetAppIconModel item,
  ) async {
    HapticFeedbackUtil.light();
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('应用“${item.name}”'),
        content: Text(
          '确定切换为“${item.name}”吗？\n\n'
          '⚠️ 提示：应用新图标需要结束应用进程以使手机桌面刷新图标。点击确认后将退出应用，请返回桌面查看全新图标。',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('应用并退出'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      HapticFeedbackUtil.medium();
      AppToast.show(context, '正在应用“${item.name}”并同步桌面与抽屉...');
      await Future.delayed(const Duration(milliseconds: 300));
      await ref.read(customAppIconProvider.notifier).switchIcon(item.id, killProcessAfter: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconState = ref.watch(customAppIconProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeIcon = iconState.currentIcon;

    return Scaffold(
      appBar: AppBar(
        title: const Text('自定义应用图标'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. 当前生效图标预览卡片
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        activeIcon.assetPath,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Review',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                activeIcon.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          activeIcon.description,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. 预设图标列表
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '可选预设图标',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ),
          ...kPresetAppIcons.map((item) {
            final isSelected = iconState.currentId == item.id;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSelected
                        ? colorScheme.primary.withValues(alpha: 0.5)
                        : theme.dividerColor.withValues(alpha: 0.1),
                    width: isSelected ? 1.5 : 0.8,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        item.assetPath,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  title: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  subtitle: Text(
                    item.description,
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: isSelected
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_rounded, size: 14, color: colorScheme.primary),
                              const SizedBox(width: 4),
                              Text(
                                '使用中',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : FilledButton.tonal(
                          onPressed: () => _confirmSwitchIcon(item),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            minimumSize: const Size(60, 32),
                          ),
                          child: const Text('应用', style: TextStyle(fontSize: 13)),
                        ),
                  onTap: isSelected ? null : () => _confirmSwitchIcon(item),
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '💡 提示：内置官方预设图标不可删除，随时支持自由切换。切换后应用将一并同步关于页面等各处的应用图标展示。',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
