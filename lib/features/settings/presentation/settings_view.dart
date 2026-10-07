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
import 'message_notification_settings_page.dart';
import '../../../core/theme/custom_app_icon_provider.dart';
import '../../../core/design_system/components/review_preference_tile.dart';

/// 纯粹的系统设置大厅 (底栏第 3 个 Tab)
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final storageService = ref.watch(storageServiceProvider);
    final themeState = ref.watch(themeProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isLoggedIn = authState.isLoggedIn;

    // 当开启悬浮胶囊底栏时，预留适度紧凑的底部边距，防止遮挡退出登录与底部设置项
    final bottomNavPadding = themeState.useFloatingNavBar ? 72.0 : 16.0;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(context).top + 20,
          16,
          bottomNavPadding,
        ),
        children: [
          _buildSectionTitle(context, '偏好与功能'),
          const SizedBox(height: 12),
          // 个性化与样式管理
          _SettingsSectionCard(
            child: Column(
              children: [
                // 个性化 (明暗、颜色、导航、触感)
                ReviewPreferenceTile(
                  leading: Icon(
                    Icons.palette_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: '个性化',
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => const ThemeSettingsPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),

                // 微博样式 (卡片排版、时间显示、IP属地、点赞过滤)
                ReviewPreferenceTile(
                  leading: Icon(
                    Icons.style_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: '微博样式',
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => const WeiboStyleSettingsPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),
                ReviewPreferenceTile(
                  leading: Icon(
                    Icons.notifications_active_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: '订阅消息提醒',
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) =>
                            const MessageNotificationSettingsPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _buildSectionTitle(context, '存储与备份'),
          const SizedBox(height: 12),

          // 2. 存储设置与 WebDAV 备份
          _SettingsSectionCard(
            child: Column(
              children: [
                // 存储设置 (图片与视频存储路径)
                ReviewPreferenceTile(
                  leading: Icon(
                    Icons.folder_open_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: '存储设置',
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => const StorageSettingsPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),

                // WebDAV 备份
                ReviewPreferenceTile(
                  leading: Icon(
                    Icons.cloud_sync_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: 'WebDAV备份',
                  subtitle: '仅备份应用设置，不包含微博登录凭据或 WebDAV 密码',
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => const WebDavBackupPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _buildSectionTitle(context, '账号设置'),
          const SizedBox(height: 12),
          // 账号管理
          _SettingsSectionCard(
            child: Column(
              children: [
                if (!isLoggedIn)
                  ReviewPreferenceTile(
                    leading: Icon(
                      Icons.login_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    title: '登录账号',
                    onTap: () {
                      HapticFeedbackUtil.light();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (ctx) => const LoginPage()),
                      );
                    },
                  ),
                if (isLoggedIn) ...[
                  ReviewPreferenceTile(
                    leading: Icon(
                      authState.isCookieExpired
                          ? Icons.warning_amber_rounded
                          : Icons.verified_user_outlined,
                      color: authState.isCookieExpired
                          ? Colors.amber
                          : colorScheme.primary,
                    ),
                    title: '检测账号凭据有效性',
                    subtitle: authState.isCookieExpired
                        ? '凭据已失效，点击检查'
                        : '${authState.nickname ?? "已登录用户"} · UID ${authState.uid ?? "未知"}',
                    trailing: authState.isValidating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: () async {
                      HapticFeedbackUtil.light();
                      AppToast.show(context, '正在检测账号凭据有效性...');
                      final isValid = await ref
                          .read(authProvider.notifier)
                          .checkCookieValidity(silent: false);
                      if (context.mounted) {
                        final currentAuth = ref.read(authProvider);
                        if (isValid) {
                          showAppDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              icon: const Icon(
                                Icons.check_circle_outline_rounded,
                                color: Colors.green,
                                size: 36,
                              ),
                              title: const Text('凭据状态正常'),
                              content: Text(
                                '当前账号凭据有效，登录会话正常。\n\n账号：@${currentAuth.nickname ?? "已登录用户"}\nUID：${currentAuth.uid ?? ""}',
                              ),
                              actions: [
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('确定'),
                                ),
                              ],
                            ),
                          );
                        } else if (currentAuth.cookieValidationStatus ==
                            CookieValidationStatus.needsDesktopSync) {
                          showAppDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              icon: const Icon(
                                Icons.sync_problem_rounded,
                                color: Colors.amber,
                                size: 36,
                              ),
                              title: const Text('桌面会话待同步'),
                              content: const Text(
                                '当前账号的移动端凭据仍然有效，但微博桌面时间线会话尚未恢复。应用已经保留登录凭据并尝试自动修复，请返回时间线后下拉刷新；如果仍无法加载，再重新登录一次。',
                              ),
                              actions: [
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('知道了'),
                                ),
                              ],
                            ),
                          );
                        } else if (!currentAuth.isCookieExpired) {
                          showAppDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              icon: const Icon(
                                Icons.sync_problem_rounded,
                                color: Colors.amber,
                                size: 36,
                              ),
                              title: const Text('暂时无法验证'),
                              content: const Text(
                                '微博官方接口暂时没有返回明确的登录状态，可能是网络波动或接口响应变化。当前不会清除登录凭据，请稍后重试。',
                              ),
                              actions: [
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('知道了'),
                                ),
                              ],
                            ),
                          );
                        } else {
                          showAppDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              icon: const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.amber,
                                size: 36,
                              ),
                              title: const Text('登录凭据已失效'),
                              content: const Text(
                                '检测到当前账号登录凭据（Cookie / SUB）已过期失效，请重新登录以保障关注流和各项互动功能正常使用。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('稍后'),
                                ),
                                FilledButton.icon(
                                  icon: const Icon(
                                    Icons.login_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('重新登录'),
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    // An expired session can still remain in
                                    // WebView's CookieManager. Clear both
                                    // stores before opening the login page so
                                    // its automatic cookie probe cannot revive
                                    // the same invalid session.
                                    await ref
                                        .read(authProvider.notifier)
                                        .logout();
                                    if (!context.mounted) return;
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (ctx) => const LoginPage(),
                                      ),
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
                  ReviewPreferenceTile(
                    leading: Icon(
                      Icons.key_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    title: '导出账号凭据 / Cookie',
                    onTap: () => _showExportCookieDialog(
                      context,
                      authState,
                      storageService,
                    ),
                  ),
                ],
                if (isLoggedIn) ...[
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    minLeadingWidth: 24,
                    horizontalTitleGap: 16,
                    minVerticalPadding: 8,
                    leading: const Icon(
                      Icons.logout_rounded,
                      color: Colors.redAccent,
                    ),
                    title: const Text(
                      '退出登录',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () async {
                      HapticFeedbackUtil.light();
                      final confirmed = await showAppDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('确认退出登录？'),
                          content: const Text(
                            '退出登录后将彻底清理本地所有微博 Cookie、会话凭据及 WebView 状态。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                              ),
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
          const SizedBox(height: 32),
          _buildSectionTitle(context, '关于与支持'),
          const SizedBox(height: 12),
          _SettingsSectionCard(
            child: ReviewPreferenceTile(
              leading: Icon(
                Icons.info_outline_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
              title: '关于 Review',
              subtitle: '版本 ${ApiConstants.appVersion}',
              onTap: () => _showAboutDialog(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: colorScheme.onSurfaceVariant),
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
      showDragHandle: true,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      '导出账号凭据 / Cookie',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '当前账号: $nickname (UID: $uid)',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),

                // 1. SUB 凭据快速复制
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'SUB 核心令牌 (用于轻量鉴权)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
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
                        subCookie.length > 60
                            ? '${subCookie.substring(0, 60)}...'
                            : subCookie,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2. 完整 Full Cookie 复制
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '完整 Cookie 字符串 (Full Session)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.copy_all_rounded, size: 14),
                            label: const Text('复制全部'),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: fullCookie),
                              );
                              HapticFeedbackUtil.light();
                              Navigator.pop(ctx);
                              AppToast.show(context, '已复制完整 Cookie 字符串到剪贴板');
                            },
                          ),
                        ],
                      ),
                      Text(
                        fullCookie.length > 80
                            ? '${fullCookie.substring(0, 80)}...'
                            : fullCookie,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2.5,
                  ),
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
                _buildAboutItem(
                  Icons.palette_outlined,
                  '100% 纯原生 Flutter 与 MD3 动态主题配色',
                  colorScheme,
                ),
                const SizedBox(height: 8),
                _buildAboutItem(
                  Icons.sync_rounded,
                  '自动同步关注流、超话与云端自定义分组',
                  colorScheme,
                ),
                const SizedBox(height: 8),
                _buildAboutItem(
                  Icons.photo_library_outlined,
                  '自适应九宫格、长图标记与高清画廊浏览',
                  colorScheme,
                ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.chevron_left_slash_chevron_right,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'GitHub 开源地址',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'github.com/Chengeeker/Review',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
            style: TextStyle(
              fontSize: 12.5,
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  final Widget child;

  const _SettingsSectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      color: colorScheme.surface == Colors.black
          ? colorScheme.surfaceContainer
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide.none,
      ),
      child: child,
    );
  }
}
