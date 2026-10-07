import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';

const ClassicHeader reviewDefaultRefreshHeader = ClassicHeader(
  dragText: '下拉刷新',
  armedText: '释放立即刷新',
  readyText: '正在刷新...',
  processingText: '正在刷新...',
  processedText: '刷新成功',
  noMoreText: '没有更多了',
  failedText: '刷新失败',
  messageText: '最后更新于 %T',
  showMessage: true,
);

Widget _buildFrostedAppBarRefreshIndicator(
  BuildContext context,
  IndicatorState state,
) {
  return Padding(
    key: const ValueKey('review-frosted-refresh-indicator-inset'),
    padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
    child: const ClassicHeader(
      triggerOffset: 70,
      safeArea: false,
      dragText: '下拉刷新',
      armedText: '释放立即刷新',
      readyText: '正在刷新...',
      processingText: '正在刷新...',
      processedText: '刷新成功',
      noMoreText: '没有更多了',
      failedText: '刷新失败',
      messageText: '最后更新于 %T',
      showMessage: true,
    ).build(context, state),
  );
}

/// Keeps the refresh indicator below an overlay app bar without adding its
/// full height to EasyRefresh's 70dp pull-to-refresh threshold.
const Header reviewFrostedAppBarRefreshHeader = BuilderHeader(
  builder: _buildFrostedAppBarRefreshIndicator,
  triggerOffset: 70,
  clamping: false,
  safeArea: false,
  position: IndicatorPosition.above,
);
