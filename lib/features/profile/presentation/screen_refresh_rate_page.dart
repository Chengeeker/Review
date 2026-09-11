import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/haptic_feedback_util.dart';

/// 屏幕帧率与分辨率设置页面 (支持 9 档精细化独立配置与实时模式探测)
class ScreenRefreshRatePage extends ConsumerStatefulWidget {
  const ScreenRefreshRatePage({super.key});

  @override
  ConsumerState<ScreenRefreshRatePage> createState() => _ScreenRefreshRatePageState();
}

class _ScreenRefreshRatePageState extends ConsumerState<ScreenRefreshRatePage> {
  static const MethodChannel _channel = MethodChannel('com.sharelite/cookies');
  int _nativeWidth = 0;
  int _nativeHeight = 0;

  @override
  void initState() {
    super.initState();
    _fetchNativeDisplayResolution();
  }

  Future<void> _fetchNativeDisplayResolution() async {
    try {
      final List<dynamic>? modes = await _channel.invokeMethod('getSupportedDisplayModes');
      if (modes != null && modes.isNotEmpty) {
        int maxW = 0;
        int maxH = 0;
        for (final m in modes) {
          if (m is Map) {
            final w = (m['width'] as num?)?.toInt() ?? 0;
            final h = (m['height'] as num?)?.toInt() ?? 0;
            if (w > maxW) {
              maxW = w;
              maxH = h;
            }
          }
        }
        if (maxW > 0 && mounted) {
          setState(() {
            _nativeWidth = maxW;
            _nativeHeight = maxH;
          });
        }
      }
    } catch (_) {}
  }

  String _getNativeResString() {
    if (_nativeWidth > 0 && _nativeHeight > 0) {
      return '${_nativeWidth}x$_nativeHeight';
    }
    return '1260x2800';
  }

  String _get1080pResString() {
    if (_nativeHeight > 0 && _nativeWidth > 0) {
      final scaledH = (_nativeHeight * 1080 / _nativeWidth).round();
      return '1080x$scaledH';
    }
    return '1080x2400';
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final currentMode = themeState.screenRefreshRateMode;
    final colorScheme = Theme.of(context).colorScheme;
    final nativeRes = _getNativeResString();
    final fhdRes = _get1080pResString();

    final List<Map<String, dynamic>> options = [
      {
        'mode': 0,
        'title': '自动',
        'isAuto': true,
      },
      {
        'mode': 1,
        'title': '#1 $nativeRes @ 120Hz',
        'subtitle': '原生分辨率 120Hz',
      },
      {
        'mode': 2,
        'title': '#2 $nativeRes @ 90Hz',
        'subtitle': '原生分辨率 90Hz',
      },
      {
        'mode': 3,
        'title': '#3 $nativeRes @ 72Hz',
        'subtitle': '原生分辨率 72Hz',
      },
      {
        'mode': 4,
        'title': '#4 $nativeRes @ 60Hz',
        'subtitle': '原生分辨率 60Hz',
      },
      {
        'mode': 5,
        'title': '#5 $fhdRes @ 120Hz',
        'subtitle': '1080P 120Hz',
      },
      {
        'mode': 6,
        'title': '#6 $fhdRes @ 90Hz',
        'subtitle': '1080P 90Hz',
      },
      {
        'mode': 7,
        'title': '#7 $fhdRes @ 72Hz',
        'subtitle': '1080P 72Hz',
      },
      {
        'mode': 8,
        'title': '#8 $fhdRes @ 60Hz',
        'subtitle': '1080P 60Hz',
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('屏幕帧率设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 顶部提示标语
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12, top: 4),
            child: Text(
              '没有生效？重启app试试',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.primary.withValues(alpha: 0.85),
                fontWeight: context.adjustWeight(FontWeight.w500),
                letterSpacing: 0.0,
              ),
            ),
          ),

          // 主选项卡片
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                width: 0.8,
              ),
            ),
            child: Column(
              children: [
                for (int i = 0; i < options.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildOptionItem(
                    context: context,
                    option: options[i],
                    isSelected: currentMode == options[i]['mode'],
                    colorScheme: colorScheme,
                    onTap: () {
                      final mode = options[i]['mode'] as int;
                      final title = options[i]['title'] as String;
                      HapticFeedbackUtil.light();
                      ref.read(themeProvider.notifier).setScreenRefreshRateMode(mode);
                      AppToast.show(context, '已应用: $title');
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildOptionItem({
    required BuildContext context,
    required Map<String, dynamic> option,
    required bool isSelected,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    final title = option['title'] as String;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected
                      ? context.adjustWeight(FontWeight.bold)
                      : context.adjustWeight(FontWeight.w500),
                  color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                  letterSpacing: 0.0,
                ),
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
