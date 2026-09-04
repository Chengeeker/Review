import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/app_dialog.dart';
import '../../../core/utils/app_toast.dart';
import 'feed_controller.dart';

/// Group Management Page (全量分组管理 - 个人/默认/热门分组支持自由增删排序与实时生效)
class GroupManagementPage extends ConsumerStatefulWidget {
  const GroupManagementPage({super.key});

  @override
  ConsumerState<GroupManagementPage> createState() => _GroupManagementPageState();
}

class _GroupManagementPageState extends ConsumerState<GroupManagementPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Master candidate lists
  static const List<Map<String, String>> allDefaultCandidateGroups = [
    {'id': 'all_follow', 'name': '全部关注'},
    {'id': 'friends', 'name': '最新微博'},
    {'id': '4152890832681124', 'name': '特别关注'},
    {'id': 'friends_circle', 'name': '好友圈'},
    {'id': 'original', 'name': '原创'},
    {'id': 'video', 'name': '视频'},
    {'id': 'chaohua', 'name': '超话社区'},
    {'id': 'v_plus', 'name': 'V+微博'},
    {'id': 'group_wb', 'name': '群微博'},
  ];

  static const List<Map<String, String>> allHotCandidateGroups = [
    {'id': '102803', 'name': '热门'},
    {'id': '102803_ctg1_-_ctg1_city', 'name': '同城'},
    {'id': '102803_ctg1_-_ctg1_realtime', 'name': '实时'},
    {'id': '102803_ctg1_-_ctg1_rank', 'name': '榜单'},
    {'id': '102803_ctg1_-_ctg1_game', 'name': '游戏'},
    {'id': '102803_ctg1_-_ctg1_society', 'name': '社会'},
    {'id': '102803_ctg1_-_ctg1_digital', 'name': '数码'},
    {'id': '102803_ctg1_-_ctg1_shortdrama', 'name': '短剧'},
    {'id': '102803_ctg1_-_ctg1_impression', 'name': '印象'},
    {'id': '102803_ctg1_-_ctg1_movie', 'name': '电影'},
    {'id': '102803_ctg1_-_ctg1_weekend', 'name': '周末'},
    {'id': '102803_ctg1_-_ctg1_funny', 'name': '搞笑'},
    {'id': '102803_ctg1_-_ctg1_selected', 'name': '精选'},
    {'id': '102803_ctg1_-_ctg1_star', 'name': '明星'},
    {'id': '102803_ctg1_-_ctg1_beauty', 'name': '美妆'},
    {'id': '102803_ctg1_-_ctg1_sports', 'name': '体育'},
    {'id': '102803_ctg1_-_ctg1_tech', 'name': '科技'},
    {'id': '102803_ctg1_-_ctg1_campus', 'name': '校园'},
    {'id': '102803_ctg1_-_ctg1_video', 'name': '视频'},
    {'id': '102803_ctg1_-_ctg1_emotion', 'name': '情感'},
    {'id': '102803_ctg1_-_ctg1_tv', 'name': '电视剧'},
    {'id': '102803_ctg1_-_ctg1_food', 'name': '美食'},
    {'id': '102803_ctg1_-_ctg1_intl', 'name': '国际'},
    {'id': '102803_ctg1_-_ctg1_depth', 'name': '深度'},
    {'id': '102803_ctg1_-_ctg1_finance', 'name': '财经'},
    {'id': '102803_ctg1_-_ctg1_reading', 'name': '读书'},
    {'id': '102803_ctg1_-_ctg1_photo', 'name': '摄影'},
    {'id': '102803_ctg1_-_ctg1_car', 'name': '汽车'},
    {'id': '102803_ctg1_-_ctg1_appearance', 'name': '颜值'},
    {'id': '102803_ctg1_-_ctg1_variety', 'name': '综艺'},
    {'id': '102803_ctg1_-_ctg1_fashion', 'name': '时尚'},
    {'id': '102803_ctg1_-_ctg1_astro', 'name': '星座'},
    {'id': '102803_ctg1_-_ctg1_military', 'name': '军事'},
    {'id': '102803_ctg1_-_ctg1_stock', 'name': '股市'},
    {'id': '102803_ctg1_-_ctg1_house', 'name': '房产'},
    {'id': '102803_ctg1_-_ctg1_home', 'name': '家居'},
    {'id': '102803_ctg1_-_ctg1_pet', 'name': '萌宠'},
    {'id': '102803_ctg1_-_ctg1_science', 'name': '科普'},
    {'id': '102803_ctg1_-_ctg1_anime', 'name': '动漫'},
    {'id': '102803_ctg1_-_ctg1_fitness', 'name': '运动健身'},
    {'id': '102803_ctg1_-_ctg1_travel', 'name': '旅游'},
    {'id': '102803_ctg1_-_ctg1_slim', 'name': '瘦身'},
    {'id': '102803_ctg1_-_ctg1_good', 'name': '好物'},
    {'id': '102803_ctg1_-_ctg1_history', 'name': '历史'},
    {'id': '102803_ctg1_-_ctg1_art', 'name': '艺术'},
    {'id': '102803_ctg1_-_ctg1_law', 'name': '法律'},
    {'id': '102803_ctg1_-_ctg1_design', 'name': '设计'},
    {'id': '102803_ctg1_-_ctg1_health', 'name': '健康'},
    {'id': '102803_ctg1_-_ctg1_music', 'name': '音乐'},
    {'id': '102803_ctg1_-_ctg1_newera', 'name': '新时代'},
    {'id': '102803_ctg1_-_ctg1_collect', 'name': '收藏'},
    {'id': '102803_ctg1_-_ctg1_gov', 'name': '政务'},
    {'id': '102803_ctg1_-_ctg1_parenting', 'name': '育儿'},
    {'id': '102803_ctg1_-_ctg1_edu', 'name': '教育'},
    {'id': '102803_ctg1_-_ctg1_marriage', 'name': '婚恋'},
    {'id': '102803_ctg1_-_ctg1_dance', 'name': '舞蹈'},
    {'id': '102803_ctg1_-_ctg1_rumor', 'name': '辟谣'},
    {'id': '102803_ctg1_-_ctg1_welfare', 'name': '公益'},
    {'id': '102803_ctg1_-_ctg1_rural', 'name': '三农'},
  ];

  // Tab 0: Personal groups
  List<Map<String, String>> _myPersonalGroups = [];

  // Tab 1: Default groups
  List<Map<String, String>> _myDefaultGroups = [];
  List<Map<String, String>> _recommendedDefaultGroups = [];

  // Tab 2: Hot groups
  List<Map<String, String>> _myHotGroups = [];
  List<Map<String, String>> _recommendedHotGroups = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    final feedState = ref.read(feedControllerProvider);
    _myPersonalGroups = List<Map<String, String>>.from(feedState.customPersonalGroups);
    if (_myPersonalGroups.isEmpty) {
      _myPersonalGroups = List<Map<String, String>>.from(FeedController.defaultInitialPersonalGroups);
    }
    _myDefaultGroups = List<Map<String, String>>.from(feedState.customDefaultGroups);
    if (_myDefaultGroups.isEmpty) {
      _myDefaultGroups = List<Map<String, String>>.from(FeedController.defaultInitialGroups);
    }
    _myHotGroups = List<Map<String, String>>.from(feedState.customHotGroups);

    final myDefIds = _myDefaultGroups.map((e) => e['id']).toSet();
    _recommendedDefaultGroups =
        allDefaultCandidateGroups.where((e) => !myDefIds.contains(e['id'])).toList();

    final myHotIds = _myHotGroups.map((e) => e['id']).toSet();
    _recommendedHotGroups =
        allHotCandidateGroups.where((e) => !myHotIds.contains(e['id'])).toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _savePreferences() async {
    await ref.read(feedControllerProvider.notifier).updateGroupPreferences(
          defaultGroups: _myDefaultGroups,
          personalGroups: _myPersonalGroups,
          hotGroups: _myHotGroups,
        );

    if (mounted) {
      AppToast.show(context, '🎉 分组配置已保存并即时生效');
      Navigator.pop(context);
    }
  }

  void _showCreateGroupDialog() {
    final controller = TextEditingController();
    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建个人分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入分组名称（最多8个字）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                setState(() {
                  _myPersonalGroups.add({
                    'id': 'custom_${DateTime.now().millisecondsSinceEpoch}',
                    'name': name,
                  });
                });
                AppToast.show(context, '已添加分组: $name（点击右上角保存生效）');
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('分组管理'),
        actions: [
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              if (_tabController.index == 0) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: _showCreateGroupDialog,
                      child: const Text('新建', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: _savePreferences,
                      child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                );
              }
              return TextButton(
                onPressed: _savePreferences,
                child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold)),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: colorScheme.primary,
          labelColor: colorScheme.onSurface,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          tabs: const [
            Tab(text: '个人分组'),
            Tab(text: '默认分组'),
            Tab(text: '热门分组'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 0: Personal User Groups (对齐截图 3)
          _buildPersonalGroupsTab(colorScheme, textTheme),

          // Tab 1: Default Groups (对齐截图 2)
          _buildDefaultGroupsTab(colorScheme, textTheme),

          // Tab 2: Hot Groups (对齐截图 4)
          _buildHotGroupsTab(colorScheme, textTheme),
        ],
      ),
    );
  }

  /// 个人分组 Tab
  Widget _buildPersonalGroupsTab(ColorScheme colorScheme, TextTheme textTheme) {
    if (_myPersonalGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_rounded, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('暂无个人分组（点击右上角“新建”添加）', style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _myPersonalGroups.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
      itemBuilder: (context, index) {
        final g = _myPersonalGroups[index];
        return ListTile(
          title: Text(
            g['name']!,
            style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: '重命名',
                onPressed: () {
                  final editController = TextEditingController(text: g['name']);
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('重命名分组'),
                      content: TextField(controller: editController, autofocus: true),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                        FilledButton(
                          onPressed: () {
                            final newName = editController.text.trim();
                            if (newName.isNotEmpty) {
                              Navigator.pop(ctx);
                              setState(() {
                                g['name'] = newName;
                              });
                            }
                          },
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                tooltip: '删除',
                onPressed: () {
                  setState(() {
                    _myPersonalGroups.removeAt(index);
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 默认分组 Tab (对齐截图 2)
  Widget _buildDefaultGroupsTab(ColorScheme colorScheme, TextTheme textTheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '我的分类 (点击每项删除对应分类)',
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_myDefaultGroups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('已清空全部默认分类（可从下方推荐分类点击添加）',
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _myDefaultGroups.map((item) {
                return ActionChip(
                  label: Text(item['name']!),
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide.none,
                  ),
                  onPressed: () {
                    setState(() {
                      _myDefaultGroups.remove(item);
                      if (!_recommendedDefaultGroups.any((e) => e['id'] == item['id'])) {
                        _recommendedDefaultGroups.add(item);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          const SizedBox(height: 28),
          Text(
            '推荐分类 (点击添加到我的分类)',
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_recommendedDefaultGroups.isEmpty)
            Text(
              '已添加全部默认分类',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _recommendedDefaultGroups.map((item) {
                return ActionChip(
                  label: Text(item['name']!),
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide.none,
                  ),
                  onPressed: () {
                    setState(() {
                      _recommendedDefaultGroups.remove(item);
                      _myDefaultGroups.add(item);
                    });
                  },
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  /// 热门分组 Tab (对齐截图 4)
  Widget _buildHotGroupsTab(ColorScheme colorScheme, TextTheme textTheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '我的分类 (点击每项删除对应分类, 长按拖动排序)',
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_myHotGroups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('暂未添加任何热门频道（可从下方推荐分类点击添加）',
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _myHotGroups.map((item) {
                return ActionChip(
                  label: Text(item['name']!),
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide.none,
                  ),
                  onPressed: () {
                    setState(() {
                      _myHotGroups.remove(item);
                      if (!_recommendedHotGroups.any((e) => e['id'] == item['id'])) {
                        _recommendedHotGroups.insert(0, item);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          const SizedBox(height: 28),
          Text(
            '推荐分类 (点击添加到我的分类)',
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _recommendedHotGroups.map((item) {
              return ActionChip(
                label: Text(item['name']!),
                backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide.none,
                ),
                onPressed: () {
                  setState(() {
                    _recommendedHotGroups.remove(item);
                    _myHotGroups.add(item);
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
