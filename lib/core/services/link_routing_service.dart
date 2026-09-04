import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../features/detail/presentation/status_detail_page.dart';
import '../../features/drawer_features/presentation/chaohua_detail_page.dart';
import '../../features/profile/presentation/user_profile_page.dart';
import '../utils/haptic_feedback_util.dart';
import '../widgets/in_app_browser_page.dart';

/// 统一链接路由与深层跳转分发中枢
class LinkRoutingService {
  static const MethodChannel _channel = MethodChannel('com.sharelite/cookies');
  static bool _hasInitializedListener = false;

  /// 判断该链接是否可以直接在原生界面内打开 (无需启动浏览器)
  static bool canHandleNatively(String rawUrl) {
    final clean = rawUrl.trim();
    if (clean.isEmpty) return false;

    // 1. 微博正文/详情页匹配
    if (RegExp(r'https?://(?:m\.)?weibo\.cn/status/([0-9a-zA-Z]+)', caseSensitive: false).hasMatch(clean)) return true;
    if (RegExp(r'https?://(?:m\.)?weibo\.cn/detail/([0-9a-zA-Z]+)', caseSensitive: false).hasMatch(clean)) return true;
    if (RegExp(r'https?://(?:m\.)?weibo\.cn/([0-9]+)/([0-9a-zA-Z]+)', caseSensitive: false).hasMatch(clean)) return true;
    if (RegExp(r'https?://(?:www\.)?weibo\.com/([0-9]+)/([0-9a-zA-Z]+)', caseSensitive: false).hasMatch(clean)) return true;
    if (RegExp(r'https?://(?:www\.)?weibo\.com/detail/([0-9a-zA-Z]+)', caseSensitive: false).hasMatch(clean)) return true;

    // 2. 个人主页匹配
    if (RegExp(r'https?://(?:m\.)?weibo\.cn/u/([0-9]+)', caseSensitive: false).hasMatch(clean)) return true;
    if (RegExp(r'https?://(?:www\.)?weibo\.com/u/([0-9]+)', caseSensitive: false).hasMatch(clean)) return true;
    if (RegExp(r'https?://(?:m\.)?weibo\.cn/profile/([0-9]+)', caseSensitive: false).hasMatch(clean)) return true;

    // 3. 超话匹配
    if (RegExp(r'https?://(?:m\.)?weibo\.cn/p/(100808[0-9a-zA-Z_]+)', caseSensitive: false).hasMatch(clean)) return true;

    return false;
  }

  /// 解析并打开任意链接 (原生详情/主页/超话 或 内置浏览器)
  static void openUrl(
    BuildContext context,
    String rawUrl, {
    String? title,
    bool replaceCurrent = false,
  }) {
    final clean = rawUrl.trim();
    if (clean.isEmpty) return;
    HapticFeedbackUtil.light();

    // 1. 微博正文匹配
    // 规则 A: m.weibo.cn/status/{id} 或 m.weibo.cn/detail/{id}
    var match = RegExp(r'https?://(?:m\.)?weibo\.cn/(?:status|detail)/([0-9a-zA-Z]+)', caseSensitive: false).firstMatch(clean);
    if (match != null) {
      final statusId = match.group(1)!;
      _navigate(context, StatusDetailPage(statusId: statusId), replace: replaceCurrent);
      return;
    }

    // 规则 B: weibo.com/detail/{id}
    match = RegExp(r'https?://(?:www\.)?weibo\.com/detail/([0-9a-zA-Z]+)', caseSensitive: false).firstMatch(clean);
    if (match != null) {
      final statusId = match.group(1)!;
      _navigate(context, StatusDetailPage(statusId: statusId), replace: replaceCurrent);
      return;
    }

    // 规则 C: m.weibo.cn/{uid}/{statusId}
    match = RegExp(r'https?://(?:m\.)?weibo\.cn/([0-9]+)/([0-9a-zA-Z]+)', caseSensitive: false).firstMatch(clean);
    if (match != null) {
      final statusId = match.group(2)!;
      _navigate(context, StatusDetailPage(statusId: statusId), replace: replaceCurrent);
      return;
    }

    // 规则 D: weibo.com/{uid}/{mblogid}
    match = RegExp(r'https?://(?:www\.)?weibo\.com/([0-9]+)/([0-9a-zA-Z]+)', caseSensitive: false).firstMatch(clean);
    if (match != null) {
      final statusId = match.group(2)!;
      _navigate(context, StatusDetailPage(statusId: statusId), replace: replaceCurrent);
      return;
    }

    // 2. 个人主页匹配
    // m.weibo.cn/u/{uid} 或 weibo.com/u/{uid} 或 m.weibo.cn/profile/{uid}
    match = RegExp(r'https?://(?:m\.|www\.)?weibo\.(?:cn|com)/(?:u|profile)/([0-9]+)', caseSensitive: false).firstMatch(clean);
    if (match != null) {
      final uid = match.group(1)!;
      _navigate(context, UserProfilePage(uid: uid), replace: replaceCurrent);
      return;
    }

    // 3. 超话匹配
    match = RegExp(r'https?://(?:m\.)?weibo\.cn/p/(100808[0-9a-zA-Z_]+)', caseSensitive: false).firstMatch(clean);
    if (match != null) {
      final containerId = match.group(1)!;
      _navigate(context, ChaohuaDetailPage(containerid: containerId, title: title ?? '超话社区'), replace: replaceCurrent);
      return;
    }

    // 4. 其他通用网页 (包括 t.cn 短链接与外部网页) -> 在内置全功能浏览器中打开
    _navigate(
      context,
      InAppBrowserPage(
        url: clean,
        title: title,
      ),
      replace: replaceCurrent,
    );
  }

  static void _navigate(BuildContext context, Widget targetPage, {bool replace = false}) {
    if (!context.mounted) return;
    if (replace) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => targetPage),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => targetPage),
      );
    }
  }

  /// 全局监听外部 App Links / Intent 唤醒与冷启动
  static void initDeepLinkListener(GlobalKey<NavigatorState> navigatorKey) {
    if (_hasInitializedListener) return;
    _hasInitializedListener = true;

    // 1. 冷启动获取初始 Intent URL
    _channel.invokeMethod<String>('getInitialUrl').then((initialUrl) {
      if (initialUrl != null && initialUrl.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final navContext = navigatorKey.currentContext;
          if (navContext != null) {
            openUrl(navContext, initialUrl);
          }
        });
      }
    }).catchError((_) {});

    // 2. 运行时监听 onDeepLinkOpened 广播
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLinkOpened') {
        final url = call.arguments?.toString();
        if (url != null && url.isNotEmpty) {
          final navContext = navigatorKey.currentContext;
          if (navContext != null) {
            openUrl(navContext, url);
          }
        }
      }
    });
  }
}
