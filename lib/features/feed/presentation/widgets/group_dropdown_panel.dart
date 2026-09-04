import 'package:flutter/material.dart';
import '../../data/feed_repository.dart';
import '../feed_controller.dart';
import '../group_management_page.dart';

/// Top Group Dropdown Switcher Panel (支持紧凑高度自适应、展示默认与我的分组)
class GroupDropdownPanel extends StatelessWidget {
  final String currentCategoryId;
  final List<Map<String, String>> customDefaultGroups;
  final List<Map<String, String>> customPersonalGroups;
  final List<WeiboGroupModel>? userGroups;
  final List<Map<String, String>> customHotGroups;
  final Function(String id, String title) onSelectGroup;
  final VoidCallback onClose;

  const GroupDropdownPanel({
    super.key,
    required this.currentCategoryId,
    required this.customDefaultGroups,
    required this.customPersonalGroups,
    this.userGroups,
    required this.customHotGroups,
    required this.onSelectGroup,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final screenHeight = MediaQuery.of(context).size.height;

    // 获取实际个人分组列表 (三级多重保障，确保永远精准显示)
    List<Map<String, String>> effectivePersonal = List<Map<String, String>>.from(customPersonalGroups);
    if (effectivePersonal.isEmpty && userGroups != null && userGroups!.isNotEmpty) {
      effectivePersonal = userGroups!
          .where((g) => g.title != '特别关注')
          .map((g) => <String, String>{'id': g.gid, 'name': g.title})
          .toList();
    }
    if (effectivePersonal.isEmpty) {
      effectivePersonal = FeedController.defaultInitialPersonalGroups
          .where((g) => g['name'] != '特别关注')
          .toList();
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.25),
              width: 1.0,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.65),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Section 1: 默认分组 Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '默认分组',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        onClose();
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const GroupManagementPage()),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(
                          '编辑',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Section 1: 默认分组 Grid (4 columns)
                if (customDefaultGroups.isNotEmpty)
                  _buildGrid(
                    context: context,
                    items: customDefaultGroups,
                    currentId: currentCategoryId,
                    onTap: (id, name) {
                      String effectiveId = id;
                      if (id == 'all_follow' || id == 'friends') effectiveId = 'friends';
                      onSelectGroup(effectiveId, name);
                    },
                  ),

                // Section 2: 我的分组 (置于默认分组下方)
                if (effectivePersonal.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '我的分组',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildGrid(
                    context: context,
                    items: effectivePersonal,
                    currentId: currentCategoryId,
                    onTap: (id, name) {
                      onSelectGroup(id, name);
                    },
                  ),
                ],

                // Section 3: 热门频道 (仅在存在自定义热门分组时展示)
                if (customHotGroups.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '热门频道',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildGrid(
                    context: context,
                    items: customHotGroups,
                    currentId: currentCategoryId,
                    onTap: (id, name) {
                      onSelectGroup(id, name);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid({
    required BuildContext context,
    required List<Map<String, String>> items,
    required String currentId,
    required Function(String id, String name) onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = item['id'] == currentId ||
            (item['id'] == 'friends' && currentId == 'friends') ||
            (item['id'] == 'all_follow' && currentId == 'friends');

        return InkWell(
          onTap: () => onTap(item['id']!, item['name']!),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.25),
                width: isSelected ? 1.2 : 0.8,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              item['name']!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
              ),
            ),
          ),
        );
      },
    );
  }
}
