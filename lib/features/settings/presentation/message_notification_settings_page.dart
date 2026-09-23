import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_service.dart';
import '../../../core/utils/app_toast.dart';

class MessageNotificationSettingsPage extends ConsumerStatefulWidget {
  const MessageNotificationSettingsPage({super.key});

  @override
  ConsumerState<MessageNotificationSettingsPage> createState() =>
      _MessageNotificationSettingsPageState();
}

class _MessageNotificationSettingsPageState
    extends ConsumerState<MessageNotificationSettingsPage> {
  static const _channel = MethodChannel('com.review/message_notifications');

  bool _enabled = false;
  bool _mentions = true;
  bool _likes = true;
  bool _comments = true;
  bool _directMessages = true;
  bool _permissionGranted = false;
  bool _loading = true;
  bool _requestingPermission = false;

  @override
  void initState() {
    super.initState();
    _loadAndRequestPermission();
  }

  Future<void> _loadAndRequestPermission() async {
    final storage = ref.read(storageServiceProvider);
    final wasEnabled =
        storage.getBool(StorageService.keyMessageNotificationsEnabled);
    if (mounted) {
      setState(() {
        _enabled =
            storage.getBool(StorageService.keyMessageNotificationsEnabled);
        _mentions = storage.getBool(
          StorageService.keyMessageNotificationMentions,
          defaultValue: true,
        );
        _likes = storage.getBool(
          StorageService.keyMessageNotificationLikes,
          defaultValue: true,
        );
        _comments = storage.getBool(
          StorageService.keyMessageNotificationComments,
          defaultValue: true,
        );
        _directMessages = storage.getBool(
          StorageService.keyMessageNotificationDirectMessages,
          defaultValue: true,
        );
        _loading = false;
        _requestingPermission = true;
      });
    }
    final granted = await _requestPermission();
    if (!mounted) return;
    setState(() {
      _permissionGranted = granted;
      _requestingPermission = false;
      if (!granted) _enabled = false;
    });
    if (!granted && wasEnabled) {
      await storage.setBool(
          StorageService.keyMessageNotificationsEnabled, false);
      await _syncBackgroundWorker();
    } else if (_enabled) {
      await _syncBackgroundWorker();
    }
  }

  Future<bool> _requestPermission() async {
    try {
      return await _channel
              .invokeMethod<bool>('requestNotificationPermission') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _syncBackgroundWorker() async {
    try {
      await _channel.invokeMethod<bool>('syncBackgroundNotifications');
    } on PlatformException {
      // Keep the preference; the next app launch will retry scheduling.
    } on MissingPluginException {
      // Non-Android platforms do not provide the Android periodic worker.
    }
  }

  Future<void> _setEnabled(bool value) async {
    if (value && !_permissionGranted) {
      final granted = await _requestPermission();
      if (!mounted) return;
      setState(() => _permissionGranted = granted);
      if (!granted) {
        AppToast.show(context, '未授予通知权限，无法开启消息提醒');
        return;
      }
    }
    final storage = ref.read(storageServiceProvider);
    if (_enabled != value) {
      await storage.setBool(
        StorageService.keyMessageNotificationInitialized,
        false,
      );
    }
    await storage.setBool(StorageService.keyMessageNotificationsEnabled, value);
    if (!mounted) return;
    setState(() => _enabled = value);
    await _syncBackgroundWorker();
  }

  Future<void> _setCategory(String key, bool value) async {
    await ref.read(storageServiceProvider).setBool(key, value);
    if (!mounted) return;
    setState(() {
      if (key == StorageService.keyMessageNotificationMentions) {
        _mentions = value;
      } else if (key == StorageService.keyMessageNotificationLikes) {
        _likes = value;
      } else if (key == StorageService.keyMessageNotificationComments) {
        _comments = value;
      } else if (key == StorageService.keyMessageNotificationDirectMessages) {
        _directMessages = value;
      }
    });
    await _syncBackgroundWorker();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('订阅消息提醒')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('订阅消息提醒', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.notifications_active_outlined,
                      color: colors.primary),
                  title: const Text('订阅消息提醒',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _permissionGranted
                        ? '允许后台定期检查微博未读消息'
                        : _requestingPermission
                            ? '正在请求系统通知权限…'
                            : '未授予系统通知权限',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: _enabled && _permissionGranted,
                  onChanged: _requestingPermission ? null : _setEnabled,
                ),
                const Divider(height: 1, indent: 56),
                _categoryTile(
                  icon: Icons.alternate_email_rounded,
                  title: '@通知',
                  subtitle: '有人在微博或评论中提及我',
                  value: _mentions,
                  onChanged: (value) => _setCategory(
                    StorageService.keyMessageNotificationMentions,
                    value,
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _categoryTile(
                  icon: Icons.favorite_border_rounded,
                  title: '点赞通知',
                  subtitle: '收到新的赞',
                  value: _likes,
                  onChanged: (value) => _setCategory(
                    StorageService.keyMessageNotificationLikes,
                    value,
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _categoryTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: '回复通知',
                  subtitle: '收到新的评论或回复',
                  value: _comments,
                  onChanged: (value) => _setCategory(
                    StorageService.keyMessageNotificationComments,
                    value,
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _categoryTile(
                  icon: Icons.forum_outlined,
                  title: '私信通知',
                  subtitle: '私信及未设置免打扰的群聊',
                  value: _directMessages,
                  onChanged: (value) => _setCategory(
                    StorageService.keyMessageNotificationDirectMessages,
                    value,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '后台提醒采用 Android 周期任务轮询，系统通常至少间隔 15 分钟执行一次；省电策略、网络状态可能造成更长延迟。提醒只在本机读取未读计数，不在通知中展示微博正文。',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: _enabled && _permissionGranted ? onChanged : null,
    );
  }
}
