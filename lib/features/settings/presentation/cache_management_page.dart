import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/components/review_page_scaffold.dart';
import '../../../core/design_system/components/review_preference_tile.dart';
import '../../../core/services/image_cache_maintenance.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils/app_dialog.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/widgets/app_section_card.dart';

class CacheManagementPage extends ConsumerStatefulWidget {
  const CacheManagementPage({super.key});

  @override
  ConsumerState<CacheManagementPage> createState() =>
      _CacheManagementPageState();
}

class _CacheManagementPageState extends ConsumerState<CacheManagementPage> {
  int _cacheBytes = 0;
  bool _loading = true;
  bool _clearing = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final bytes = await ImageCacheMaintenance.getDiskCacheSize();
      if (!mounted) return;
      setState(() {
        _cacheBytes = bytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = '暂时无法读取图片缓存';
        _loading = false;
      });
    }
  }

  Future<void> _clearCache() async {
    if (_clearing || _loading) return;
    HapticFeedbackUtil.light();
    if (_cacheBytes == 0) {
      AppToast.show(context, '当前没有可清理的图片缓存');
      return;
    }

    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理图片缓存？'),
        content: Text(
          '将清理 ${ImageCacheMaintenance.formatBytes(_cacheBytes)} 的可再生成图片磁盘缓存。正在写入的文件会保留；已保存到相册的图片、视频和账号数据不会受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('立即清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);
    HapticFeedbackUtil.medium();
    try {
      final clearedBytes = await ImageCacheMaintenance.clearDiskCache();
      await _loadCacheSize();
      if (!mounted) return;
      AppToast.show(
        context,
        clearedBytes > 0
            ? '已清理 ${ImageCacheMaintenance.formatBytes(clearedBytes)} 图片缓存'
            : '没有可清理的缓存文件，正在写入的文件已保留',
      );
    } catch (_) {
      if (mounted) AppToast.show(context, '清理失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  void _selectThreshold(BuildContext dialogContext, int value) {
    final notifier = ref.read(themeProvider.notifier);
    unawaited(notifier.setAutoClearImageCacheThresholdMb(value));
    Navigator.pop(dialogContext);
    AppToast.show(
      context,
      value == 0 ? '已关闭自动清理' : '已设置自动清理阈值：${_formatThreshold(value)}',
    );
  }

  void _showThresholdSelector(int currentValue) {
    HapticFeedbackUtil.light();
    showAppDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自动清理阈值'),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: RadioGroup<int>(
          groupValue: currentValue,
          onChanged: (selected) {
            if (selected == null) return;
            HapticFeedbackUtil.light();
            _selectThreshold(ctx, selected);
          },
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final value
                    in ImageCacheMaintenance.autoClearThresholdOptions)
                  RadioListTile<int>(
                    value: value,
                    title: Text(_formatThreshold(value)),
                    dense: true,
                  ),
              ],
            ),
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

  String _formatThreshold(int value) {
    if (value == 0) return '不限制（关闭自动清理）';
    if (value >= 1024) {
      final gb = value / 1024;
      return '${gb.toStringAsFixed(gb == gb.roundToDouble() ? 0 : 1)} GB';
    }
    return '$value MB';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final threshold = ref.watch(
      themeProvider.select((state) => state.autoClearImageCacheThresholdMb),
    );

    return ReviewPageScaffold(
      title: '缓存管理',
      bodyBuilder: (context, contentInsets) => ListView(
        padding: contentInsets + const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          AppSectionCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.cleaning_services_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  else
                    Text(
                      _loadError ??
                          ImageCacheMaintenance.formatBytes(_cacheBytes),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _loadError == null
                                ? colorScheme.onSurface
                                : colorScheme.error,
                          ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '可管理的图片磁盘缓存',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '只统计临时 cacheimage 目录中的图片缓存文件',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: (_loading || _clearing || _loadError != null)
                    ? null
                    : _clearCache,
                icon: _clearing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_sweep_rounded),
                label: Text(_clearing ? '正在清理...' : '清理图片缓存'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '自动清理规则',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          AppSectionCard(
            child: ReviewPreferenceTile(
              leading: Icon(
                Icons.auto_delete_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
              title: '自动清理缓存阈值',
              subtitle: '达到阈值时在启动阶段自动清理；更改后也会立即检查一次',
              trailing: Text(
                _formatThreshold(threshold),
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => _showThresholdSelector(threshold),
            ),
          ),
          const SizedBox(height: 24),
          AppSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '清理仅针对 Review 图片加载生成的 MD5 磁盘缓存；最近 1 分钟内写入的文件会暂时保留。已保存到相册的图片和视频、账号资料及其他临时文件不会被删除。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: _loading || _clearing ? null : _loadCacheSize,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新缓存占用'),
            ),
          ),
        ],
      ),
    );
  }
}
