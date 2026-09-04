import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/haptic_feedback_util.dart';
import '../../../../core/utils/weibo_text_parser.dart';
import '../../../../core/utils/weibo_time_formatter.dart';
import '../../../feed/data/models/weibo_status_model.dart';
import '../../data/detail_repository.dart';
import '../../data/models/weibo_edit_history_model.dart';
import 'image_gallery_page.dart';

/// Material 3 Expressive Bottom Sheet for Viewing Weibo Edit History Revisions
class EditHistoryBottomSheet extends ConsumerStatefulWidget {
  final String statusId;
  final String? mid;
  final String authorName;

  const EditHistoryBottomSheet({
    super.key,
    required this.statusId,
    this.mid,
    this.authorName = '',
  });

  static Future<void> show(
    BuildContext context, {
    required String statusId,
    String? mid,
    String authorName = '',
  }) {
    HapticFeedbackUtil.light();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditHistoryBottomSheet(
        statusId: statusId,
        mid: mid,
        authorName: authorName,
      ),
    );
  }

  @override
  ConsumerState<EditHistoryBottomSheet> createState() => _EditHistoryBottomSheetState();
}

class _EditHistoryBottomSheetState extends ConsumerState<EditHistoryBottomSheet> {
  bool _isLoading = true;
  String? _errorMessage;
  WeiboEditHistoryModel? _editHistory;

  @override
  void initState() {
    super.initState();
    _fetchEditHistory();
  }

  Future<void> _fetchEditHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final targetMid = (widget.mid != null && widget.mid!.isNotEmpty) ? widget.mid! : widget.statusId;
    final repo = ref.read(detailRepositoryProvider);
    final result = await repo.getEditHistory(targetMid);

    if (!mounted) return;

    if (result != null && result.statuses.isNotEmpty) {
      setState(() {
        _editHistory = result;
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = '未获取到编辑记录或该微博无需编辑历史';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(
        maxHeight: screenHeight * 0.86,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.25), width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // M3e Tactile Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(32),
              ),
            ),
          ),

          // Header Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.history_rounded, size: 22, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '微博编辑记录',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: context.adjustWeight(FontWeight.bold),
                          fontSize: 17,
                        ),
                      ),
                      if (_editHistory != null)
                        Text(
                          '共 ${_editHistory!.total} 个修订版本',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        )
                      else if (widget.authorName.isNotEmpty)
                        Text(
                          '@${widget.authorName} 的博文修订历史',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 0.5),

          // Content Area
          Flexible(
            child: _buildBody(context, colorScheme, theme),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme colorScheme, ThemeData theme) {
    if (_isLoading) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '正在加载编辑记录...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Container(
        height: 220,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline_rounded, size: 40, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _fetchEditHistory,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final statuses = _editHistory?.statuses ?? [];
    if (statuses.isEmpty) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        child: Text(
          '暂无编辑历史',
          style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: statuses.length,
      itemBuilder: (context, index) {
        final item = statuses[index];
        final isLatest = index == 0;
        final isInitial = index == statuses.length - 1;
        final versionNumber = statuses.length - index;

        return _buildRevisionCard(
          context: context,
          revision: item,
          isLatest: isLatest,
          isInitial: isInitial,
          versionNumber: versionNumber,
          colorScheme: colorScheme,
          theme: theme,
        );
      },
    );
  }

  Widget _buildRevisionCard({
    required BuildContext context,
    required WeiboStatusModel revision,
    required bool isLatest,
    required bool isInitial,
    required int versionNumber,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    final parsedTime = WeiboTimeFormatter.parseWeiboDate(revision.createdAt);
    final timeStr = parsedTime != null
        ? WeiboTimeFormatter.format(rawDate: revision.createdAt)
        : revision.createdAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLatest
              ? colorScheme.primary.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.25),
          width: isLatest ? 1.2 : 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Revision Header: Badge + Time + IP
            Row(
              children: [
                // Version Pill Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isLatest
                        ? colorScheme.primaryContainer
                        : (isInitial
                            ? colorScheme.secondaryContainer
                            : colorScheme.surfaceContainerHighest),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isLatest
                        ? '🔥 最新版本 (当前)'
                        : (isInitial ? '🌱 首次发布' : '第 $versionNumber 版'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: context.adjustWeight(FontWeight.bold),
                      color: isLatest
                          ? colorScheme.onPrimaryContainer
                          : (isInitial
                              ? colorScheme.onSecondaryContainer
                              : colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
                const Spacer(),
                // Timestamp
                Text(
                  timeStr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Revision Rich Text
            SelectableText.rich(
              TextSpan(
                children: WeiboTextParser.parse(
                  rawText: revision.effectiveText,
                  context: context,
                ),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                height: 1.5,
                color: colorScheme.onSurface,
              ),
            ),

            // Revision Pictures (if any)
            if (revision.pics.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildPicsGrid(context, revision.pics, revision.id, revision.user.screenName),
            ],

            // Footer (Region / Source)
            if (revision.regionName != null && revision.regionName!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  Text(
                    revision.regionName!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPicsGrid(BuildContext context, List<WeiboPicModel> pics, String statusId, String authorName) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(pics.length, (i) {
        final pic = pics[i];
        return GestureDetector(
          onTap: () {
            HapticFeedbackUtil.light();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ImageGalleryPage(
                  pics: pics,
                  initialIndex: i,
                  statusId: statusId,
                  authorName: authorName,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              pic.previewUrl,
              headers: ApiConstants.imageHeaders,
              width: 84,
              height: 84,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 84,
                height: 84,
                color: Colors.grey.withValues(alpha: 0.2),
                child: const Icon(Icons.broken_image_rounded, size: 24),
              ),
            ),
          ),
        );
      }),
    );
  }
}
