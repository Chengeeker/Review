import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/services/webdav_service.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/theme/weibo_style_provider.dart';
import '../../../core/utils/app_dialog.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/haptic_feedback_util.dart';

/// WebDAV Cloud Backup and Restore Page
class WebDavBackupPage extends ConsumerStatefulWidget {
  const WebDavBackupPage({super.key});

  @override
  ConsumerState<WebDavBackupPage> createState() => _WebDavBackupPageState();
}

class _WebDavBackupPageState extends ConsumerState<WebDavBackupPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _dirController;

  final WebDavService _webDavService = WebDavService();
  bool _isTesting = false;
  bool _isBackingUp = false;
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    final storage = ref.read(storageServiceProvider);
    _urlController = TextEditingController(text: storage.getWebDavUrl());
    _usernameController = TextEditingController(text: storage.getWebDavUsername());
    _passwordController = TextEditingController(text: storage.getWebDavPassword());
    _dirController = TextEditingController(
      text: storage.getWebDavDirectory().isEmpty ? 'Review' : storage.getWebDavDirectory(),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _dirController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    final storage = ref.read(storageServiceProvider);
    await storage.setWebDavUrl(_urlController.text.trim());
    await storage.setWebDavUsername(_usernameController.text.trim());
    await storage.setWebDavPassword(_passwordController.text.trim());
    await storage.setWebDavDirectory(
      _dirController.text.trim().isEmpty ? 'Review' : _dirController.text.trim(),
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedbackUtil.light();
    await _saveConfig();
    if (!mounted) return;

    setState(() => _isTesting = true);

    final success = await _webDavService.testConnection(
      serverUrl: _urlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isTesting = false);

    HapticFeedbackUtil.medium();
    AppToast.show(
      context,
      success ? '🎉 WebDAV 服务器连接成功！' : '❌ 连接失败，请检查服务器地址、账号与授权密码',
    );
  }

  Future<void> _performBackup() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedbackUtil.light();
    await _saveConfig();
    if (!mounted) return;

    setState(() => _isBackingUp = true);
    final storage = ref.read(storageServiceProvider);

    final backupData = storage.exportAllData();
    final dirName = _dirController.text.trim().isEmpty ? 'Review' : _dirController.text.trim();

    final success = await _webDavService.uploadBackup(
      serverUrl: _urlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
      directoryName: dirName,
      data: backupData,
    );

    if (!mounted) return;
    setState(() => _isBackingUp = false);

    HapticFeedbackUtil.medium();
    AppToast.show(
      context,
      success ? '🎉 已成功将全部设置与账号 Cookie 打包备份到 WebDAV 云盘！' : '❌ 备份上传失败，请检查连接状态',
    );
  }

  Future<void> _performRestore() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedbackUtil.light();
    await _saveConfig();
    if (!mounted) return;

    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从 WebDAV 恢复备份？'),
        content: const Text('恢复备份将使用云端数据覆盖当前的所有个性化设置与账号登录状态。是否继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定恢复')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isRestoring = true);
    final storage = ref.read(storageServiceProvider);
    final dirName = _dirController.text.trim().isEmpty ? 'Review' : _dirController.text.trim();

    final backupData = await _webDavService.downloadLatestBackup(
      serverUrl: _urlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
      directoryName: dirName,
    );

    if (!mounted) return;
    setState(() => _isRestoring = false);

    if (backupData != null) {
      await storage.restoreAllData(backupData);

      if (!mounted) return;

      // Refresh providers
      ref.read(themeProvider.notifier).reload();
      ref.read(weiboStyleProvider.notifier).reload();
      final fullCookie = storage.getFullCookie();
      if (fullCookie != null && fullCookie.isNotEmpty) {
        ref.read(authProvider.notifier).setAndVerifyCookie(fullCookie);
      }

      HapticFeedbackUtil.medium();
      AppToast.show(context, '🎉 备份已成功恢复！应用已同步最新云端配置与登录凭据');
    } else {
      if (!mounted) return;
      AppToast.show(context, '❌ 未找到可用云端备份文件或下载失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV 云端备份与恢复', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            // 1. Info Banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.cloud_sync_rounded, color: colorScheme.primary, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '全量安全备份 (Review)',
                          style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '使用 WebDAV 协议将当前应用的所有外观主题、微博样式、卡片显示规则、媒体存储路径以及账号 Cookie/Token 打包加密传输至坚果云、Nextcloud、群晖或自建 WebDAV 服务器。',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 2. Configuration Card
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1), width: 0.8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('WebDAV 服务器配置', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: '服务器 URL',
                        hintText: '例如: https://dav.jianguoyun.com/dav/',
                        prefixIcon: Icon(Icons.link_rounded),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return '请输入 WebDAV 服务器地址';
                        final lower = v.trim().toLowerCase();
                        if (lower.startsWith('http://') &&
                            !lower.startsWith('http://127.0.0.1') &&
                            !lower.startsWith('http://localhost')) {
                          return '为了安全，WebDAV 请使用加密的 https:// 协议';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: '账号 / 邮箱',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? '请输入账号' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '应用密码 / Token',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? '请输入密码或授权 Token' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _dirController,
                      decoration: const InputDecoration(
                        labelText: '备份文件夹名称',
                        hintText: '默认: Review',
                        prefixIcon: Icon(Icons.folder_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: _isTesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.wifi_tethering_rounded, size: 18),
                        label: Text(_isTesting ? '正在测试连接...' : '测试服务器连接'),
                        onPressed: _isTesting ? null : _testConnection,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Actions Section
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1), width: 0.8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('云端备份与还原操作', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                            icon: _isBackingUp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.cloud_upload_rounded),
                            label: Text(_isBackingUp ? '正在上传...' : '立即备份到云端'),
                            onPressed: (_isBackingUp || _isRestoring) ? null : _performBackup,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                            icon: _isRestoring
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.cloud_download_rounded),
                            label: Text(_isRestoring ? '正在拉取...' : '从云端恢复备份'),
                            onPressed: (_isBackingUp || _isRestoring) ? null : _performRestore,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
