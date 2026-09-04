import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils/app_dialog.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../auth/presentation/login_page.dart';
import '../../profile/presentation/theme_settings_page.dart';
import '../../profile/presentation/weibo_style_settings_page.dart';
import 'storage_settings_page.dart';
import 'webdav_backup_page.dart';
import '../../../core/theme/custom_app_icon_provider.dart';

/// 纯粹的系统设置大厅 (底栏第 3 个 Tab)
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final storageService = ref.watch(storageServiceProvider);
    final themeState = ref.watch(themeProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLoggedIn = authState.isLoggedIn;

    // 当开启悬浮胶囊底栏时，预留适度紧凑的底部边距，防止遮挡退出登录与底部设置项
    final bottomNavPadding = themeState.useFloatingNavBar ? 72.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomNavPadding),
        children: [
          // 1. 个性化与样式管理
          Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
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
                // 个性化 (明暗、颜色、导航、触感)
                ListTile(
                  leading: Icon(Icons.palette_outlined, color: colorScheme.primary),
                  title: const Text('个性化', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('明暗模式、色彩方案、悬浮胶囊底栏与触感反馈', style: TextStyle(fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (ctx) => const ThemeSettingsPage()),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),

                // 微博样式 (卡片排版、时间显示、IP属地、点赞过滤)
                ListTile(
                  leading: Icon(Icons.style_outlined, color: colorScheme.primary),
                  title: const Text('微博样式', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('卡片排版、时间格式、IP属地与点赞博文过滤', style: TextStyle(fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (ctx) => const WeiboStyleSettingsPage()),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. 存储设置与 WebDAV 备份
          Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
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
                // 存储设置 (图片与视频存储路径、自动与手动缓存清理)
                ListTile(
                  leading: Icon(Icons.folder_open_outlined, color: colorScheme.primary),
                  title: const Text('存储设置', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('图片/视频存储路径与缓存自动清理', style: TextStyle(fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (ctx) => const StorageSettingsPage()),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),

                // WebDAV 备份
                ListTile(
                  leading: Icon(Icons.cloud_sync_outlined, color: colorScheme.primary),
                  title: const Text('WebDAV备份', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('使用 WebDAV 打包备份全部个性化设置与账号 Cookie', style: TextStyle(fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (ctx) => const WebDavBackupPage()),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3. 账号管理与关于
          Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
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
                if (!isLoggedIn)
                  ListTile(
                    leading: Icon(Icons.login_rounded, color: colorScheme.primary),
                    title: const Text('登录账号', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('短信验证码、扫码或导入账号凭据', style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      HapticFeedbackUtil.light();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (ctx) => const LoginPage()),
                      );
                    },
                  ),
                if (isLoggedIn) ...[
                  ListTile(
                    leading: Icon(
                      authState.isCookieExpired
                          ? Icons.warning_amber_rounded
                          : Icons.verified_user_outlined,
                      color: authState.isCookieExpired ? Colors.amber : colorScheme.primary,
                    ),
                    title: const Text('检测账号凭据有效性', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      authState.isCookieExpired
                          ? '⚠️ 凭据已失效，点击重新登录'
                          : '验证当前 Cookie 与访问令牌是否过期有效',
                      style: TextStyle(
                        fontSize: 12,
                        color: authState.isCookieExpired ? colorScheme.error : null,
                      ),
                    ),
                    trailing: authState.isValidating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      HapticFeedbackUtil.light();
                      AppToast.show(context, '正在检测账号凭据有效性...');
                      final isValid = await ref.read(authProvider.notifier).checkCookieValidity(silent: false);
                      if (context.mounted) {
                        final currentAuth = ref.read(authProvider);
                        if (isValid) {
                          showAppDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 36),
                              title: const Text('凭据状态正常'),
                              content: Text('当前账号凭据有效，登录会话正常。\n\n账号：@${currentAuth.nickname ?? "已登录用户"}\nUID：${currentAuth.uid ?? ""}'),
                              actions: [
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('确定'),
                                ),
                              ],
                            ),
                          );
                        } else {
                          showAppDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              icon: const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 36),
                              title: const Text('登录凭据已失效'),
                              content: const Text('检测到当前账号登录凭据（Cookie / SUB）已过期失效，请重新登录以保障关注流和各项互动功能正常使用。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('稍后'),
                                ),
                                FilledButton.icon(
                                  icon: const Icon(Icons.login_rounded, size: 18),
                                  label: const Text('重新登录'),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (ctx) => const LoginPage()),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        }
                      }
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: Icon(Icons.key_rounded, color: colorScheme.primary),
                    title: const Text('导出账号凭据 / Cookie', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('查看并复制当前账号完整 Cookie 或 SUB 凭据', style: TextStyle(fontSize: 12.5)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showExportCookieDialog(context, authState, storageService),
                  ),
                ],
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(Icons.info_outline_rounded, color: colorScheme.primary),
                  title: const Text('关于 Review', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('版本 ${ApiConstants.appVersion}', style: TextStyle(fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showAboutDialog(context, ref),
                ),
                if (isLoggedIn) ...[
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                    title: const Text('退出登录', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    onTap: () async {
                      HapticFeedbackUtil.light();
                      final confirmed = await showAppDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('确认退出登录？'),
                          content: const Text('退出登录后将彻底清理本地所有微博 Cookie、会话凭据及 WebView 状态。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('退出'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        await ref.read(authProvider.notifier).logout();
                        if (context.mounted) {
                          AppToast.show(context, '已退出登录并彻底清理会话凭据');
                        }
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showExportCookieDialog(
    BuildContext context,
    AuthState authState,
    StorageService storageService,
  ) async {
    HapticFeedbackUtil.light();
    final fullCookie = storageService.getFullCookie() ?? '未检测到完整 Cookie';
    final subCookie = storageService.getSubCookie() ?? '未检测到 SUB 凭据';
    final uid = authState.uid ?? '未知 UID';
    final nickname = authState.nickname ?? '未命名';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('导出账号凭据 / Cookie', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '当前账号: $nickname (UID: $uid)',
                  style: TextStyle(fontSize: 13, color: colorScheme.primary, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),

                // 1. SUB 凭据快速复制
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('SUB 核心令牌 (用于轻量鉴权)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          TextButton.icon(
                            icon: const Icon(Icons.copy_rounded, size: 14),
                            label: const Text('复制 SUB'),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: subCookie));
                              HapticFeedbackUtil.light();
                              Navigator.pop(ctx);
                              AppToast.show(context, '已复制 SUB 凭据到剪贴板');
                            },
                          ),
                        ],
                      ),
                      Text(
                        subCookie.length > 60 ? '${subCookie.substring(0, 60)}...' : subCookie,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2. 完整 Full Cookie 复制
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('完整 Cookie 字符串 (Full Session)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          TextButton.icon(
                            icon: const Icon(Icons.copy_all_rounded, size: 14),
                            label: const Text('复制全部'),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: fullCookie));
                              HapticFeedbackUtil.light();
                              Navigator.pop(ctx);
                              AppToast.show(context, '已复制完整 Cookie 字符串到剪贴板');
                            },
                          ),
                        ],
                      ),
                      Text(
                        fullCookie.length > 80 ? '${fullCookie.substring(0, 80)}...' : fullCookie,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAboutDialog(BuildContext context, WidgetRef ref) async {
    HapticFeedbackUtil.light();
    final colorScheme = Theme.of(context).colorScheme;
    final iconState = ref.read(customAppIconProvider);

    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  iconState.currentAssetPath,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 2. Centered Title & Version Tag
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Review',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'v${ApiConstants.appVersion}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '纯原生 Material You 极简客户端',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // 3. Feature Highlights
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAboutItem(Icons.palette_outlined, '100% 纯原生 Flutter 与 MD3 动态主题配色', colorScheme),
                const SizedBox(height: 8),
                _buildAboutItem(Icons.sync_rounded, '自动同步关注流、超话与云端自定义分组', colorScheme),
                const SizedBox(height: 8),
                _buildAboutItem(Icons.photo_library_outlined, '自适应九宫格、长图标记与高清画廊浏览', colorScheme),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // 4. GitHub Project Link
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final uri = Uri.parse('https://github.com/Chengeeker/Review');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.chevron_left_slash_chevron_right, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'GitHub 开源地址',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'github.com/Chengeeker/Review',
                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.open_in_new_rounded, size: 16, color: colorScheme.primary),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            child: const Text('我知道了'),
          ),
        ],
        actionsAlignment: MainAxisAlignment.center,
      ),
    );
  }

  Widget _buildAboutItem(IconData icon, String text, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant, height: 1.35),
          ),
        ),
      ],
    );
  }
}
