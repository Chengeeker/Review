import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../feed/data/models/weibo_status_model.dart';
import '../../feed/presentation/widgets/tweet_card.dart';

/// 浏览记录 / 浏览足迹大厅
class BrowsingHistoryPage extends ConsumerStatefulWidget {
  const BrowsingHistoryPage({super.key});

  @override
  ConsumerState<BrowsingHistoryPage> createState() => _BrowsingHistoryPageState();
}

class _BrowsingHistoryPageState extends ConsumerState<BrowsingHistoryPage> {
  final List<WeiboStatusModel> _statuses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    setState(() => _isLoading = true);
    final storage = ref.read(storageServiceProvider);
    final jsonList = storage.getBrowsingHistoryStatusJsons();
    final list = <WeiboStatusModel>[];

    for (final raw in jsonList) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        list.add(WeiboStatusModel.fromJson(map));
      } catch (_) {}
    }

    setState(() {
      _statuses.clear();
      _statuses.addAll(list);
      _isLoading = false;
    });
  }

  Future<void> _clearHistory() async {
    HapticFeedbackUtil.light();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空浏览足迹'),
        content: const Text('确定要清空所有已浏览的微博历史记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final storage = ref.read(storageServiceProvider);
      await storage.clearBrowsingHistory();
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('浏览记录', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_statuses.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: '清空浏览记录',
              onPressed: _clearHistory,
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : _statuses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 56, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35)),
                      const SizedBox(height: 12),
                      Text(
                        '暂无浏览记录',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '您在时间线或搜索中点开查看的微博将自动记录在此',
                        style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _statuses.length,
                  itemBuilder: (context, index) {
                    return TweetCard(
                      status: _statuses[index],
                      isDetail: false,
                    );
                  },
                ),
    );
  }
}
