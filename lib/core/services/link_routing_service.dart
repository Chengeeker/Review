import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../features/detail/presentation/status_detail_page.dart';
import '../../features/detail/presentation/weibo_article_page.dart';
import '../../features/drawer_features/presentation/chaohua_detail_page.dart';
import '../../features/profile/presentation/user_profile_page.dart';
import '../../features/feed/presentation/widgets/weibo_video_link_page.dart';
import '../../features/feed/presentation/widgets/weibo_video_player_page.dart';
import '../utils/haptic_feedback_util.dart';
import '../widgets/in_app_browser_page.dart';

/// 统一链接路由与深层跳转分发中枢
class LinkRoutingService {
  static const MethodChannel _channel = MethodChannel('com.sharelite/cookies');
  static bool _hasInitializedListener = false;

  /// Weibo still emits HTTP smart-card links for some official pages, such as
  /// long-form articles. Android blocks cleartext WebView requests before the
  /// server can issue its HTTPS redirect, so normalize only official Weibo
  /// hosts while leaving ordinary external links untouched.
  static String normalizeOfficialUrl(String rawUrl) {
    final clean = rawUrl.trim();
    if (clean.isEmpty) return clean;

    final uri = Uri.tryParse(clean);
    if (uri == null || uri.scheme.toLowerCase() != 'http') return clean;

    final host = uri.host.toLowerCase();
    final isWeiboHost = host == 'weibo.com' ||
        host.endsWith('.weibo.com') ||
        host == 'weibo.cn' ||
        host.endsWith('.weibo.cn');
    return isWeiboHost ? uri.replace(scheme: 'https').toString() : clean;
  }

  /// Returns the official long-form article id from a Weibo article URL.
  ///
  /// The id is intentionally kept as a String: current article ids can be
  /// longer than the safe integer range on Android/Dart.
  static String? articleIdFromUrl(String rawUrl) {
    final clean = normalizeOfficialUrl(rawUrl);
    final uri = Uri.tryParse(clean);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    final isWeiboHost = host == 'weibo.com' ||
        host.endsWith('.weibo.com') ||
        host == 'weibo.cn' ||
        host.endsWith('.weibo.cn');
    if (!isWeiboHost) return null;

    final path = uri.path.replaceFirst(RegExp(r'/+$'), '').toLowerCase();
    if (path != '/ttarticle/p/show') return null;

    final id = uri.queryParameters['id']?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  /// Returns the full Weibo video object id (`1034:...`) from a video
  /// component link. The H5 and desktop variants point to the same official
  /// component API and should therefore share one native playback route.
  static String? videoObjectIdFromUrl(String rawUrl) {
    final clean = normalizeOfficialUrl(rawUrl);
    final uri = Uri.tryParse(clean);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    final isVideoHost = host == 'h5.video.weibo.com' ||
        host == 'video.weibo.com' ||
        host == 'h5.video.weibo.cn' ||
        host == 'video.weibo.cn' ||
        host == 'weibo.com' ||
        host == 'www.weibo.com' ||
        host == 'm.weibo.cn';
    if (!isVideoHost) return null;

    String? firstQueryValue(List<String> names) {
      for (final name in names) {
        final value = uri.queryParameters[name]?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    final queryObjectId = firstQueryValue(
      const ['fid', 'object_id', 'objectId', 'oid'],
    );
    final pathMatch = RegExp(r'/(?:show|tv/show|s/video/show)/([^/?#]+)',
            caseSensitive: false)
        .firstMatch(uri.path);
    final rawId = queryObjectId ?? pathMatch?.group(1);
    if (rawId == null || rawId.isEmpty) return null;

    late final String objectId;
    try {
      objectId = Uri.decodeComponent(rawId).trim();
    } catch (_) {
      return null;
    }
    return RegExp(r'^\d+:[^/?#]+$').hasMatch(objectId) ? objectId : null;
  }

  /// Returns true for a real Weibo CDN media URL. These URLs are returned by
  /// `url_objects` for some newer video cards when the H5 component endpoint
  /// has no component data yet. They can be passed directly to video_player.
  static bool isDirectVideoMediaUrl(String rawUrl) {
    final clean = normalizeOfficialUrl(rawUrl);
    final uri = Uri.tryParse(clean);
    if (uri == null) return false;

    final host = uri.host.toLowerCase();
    if (!host.endsWith('.weibocdn.com')) return false;

    final pathAndQuery = '${uri.path}?${uri.query}'.toLowerCase();
    return RegExp(r'\.(?:mp4|m3u8|m3u|webm|mov|flv)(?:$|[?#])')
        .hasMatch(pathAndQuery);
  }

  /// 判断该链接是否可以直接在原生界面内打开 (无需启动浏览器)
  static bool canHandleNatively(String rawUrl) {
    final clean = normalizeOfficialUrl(rawUrl).trim();
    if (clean.isEmpty) return false;

    if (articleIdFromUrl(clean) != null) return true;

    if (videoObjectIdFromUrl(clean) != null) return true;

    if (isDirectVideoMediaUrl(clean)) return true;

    // 1. 微博正文/详情页匹配
    if (RegExp(r'https?://(?:m\.)?weibo\.cn/status/([0-9a-zA-Z]+)',
            caseSensitive: false)
        .hasMatch(clean)) return true;
    if (RegExp(r'https?://(?:m\.)?weibo\.cn/detail/([0-9a-zA-Z]+)',
            caseSensitive: false)
        .hasMatch(clean)) return true;
    if (RegExp(r'https?://(?:m\.)?weibo\.cn/([0-9]+)/([0-9a-zA-Z]+)',
            caseSensitive: false)
        .hasMatch(clean)) return true;
    if (RegExp(r'https?://(?:www\.)?weibo\.com/([0-9]+)/([0-9a-zA-Z]+)',
            caseSensitive: false)
        .hasMatch(clean)) return true;
    if (RegExp(r'https?://(?:www\.)?weibo\.com/detail/([0-9a-zA-Z]+)',
            caseSensitive: false)
        .hasMatch(clean)) return true;

    // 2. 个人主页匹配
    if (RegExp(r'https?://(?:m\.)?weibo\.cn/u/([0-9]+)', caseSensitive: false)
        .hasMatch(clean)) return true;
    if (RegExp(r'https?://(?:www\.)?weibo\.com/u/([0-9]+)',
            caseSensitive: false)
        .hasMatch(clean)) return true;
    if (RegExp(r'https?://(?:m\.)?weibo\.cn/profile/([0-9]+)',
            caseSensitive: false)
        .hasMatch(clean)) return true;
    if (RegExp(r'https?://(?:m\.|www\.)?weibo\.(?:cn|com)/n/([^/?#]+)',
            caseSensitive: false)
        .hasMatch(clean)) return true;

    // 3. 超话匹配
    if (RegExp(r'https?://(?:m\.)?weibo\.cn/p/(100808[0-9a-zA-Z_]+)',
            caseSensitive: false)
        .hasMatch(clean)) return true;

    return false;
  }

  /// 解析并打开任意链接 (原生详情/主页/超话 或 内置浏览器)
  static void openUrl(
    BuildContext context,
    String rawUrl, {
    String? title,
    bool replaceCurrent = false,
  }) {
    final clean = normalizeOfficialUrl(rawUrl);
    if (clean.isEmpty) return;
    HapticFeedbackUtil.light();

    // 0. 微博长文：使用 Flutter 原生文章页，不退回 WebView。
    final articleId = articleIdFromUrl(clean);
    if (articleId != null) {
      _navigate(
        context,
        WeiboArticlePage(articleId: articleId, title: title),
        replace: replaceCurrent,
      );
      return;
    }

    // Standalone Weibo video cards point to an H5 HTML shell. Resolve the
    // official component metadata first, then hand the signed URL to the
    // native player instead of opening that shell in a WebView.
    final videoObjectId = videoObjectIdFromUrl(clean);
    if (videoObjectId != null) {
      _navigate(
        context,
        WeiboVideoLinkPage(videoObjectId: videoObjectId, title: title),
        replace: replaceCurrent,
      );
      return;
    }

    if (isDirectVideoMediaUrl(clean)) {
      _navigate(
        context,
        WeiboVideoPlayerPage(videoUrl: clean, title: title),
        replace: replaceCurrent,
      );
      return;
    }

    // 1. 微博正文匹配
    // 规则 A: m.weibo.cn/status/{id} 或 m.weibo.cn/detail/{id}
    var match = RegExp(
            r'https?://(?:m\.)?weibo\.cn/(?:status|detail)/([0-9a-zA-Z]+)',
            caseSensitive: false)
        .firstMatch(clean);
    if (match != null) {
      final statusId = match.group(1)!;
      _navigate(context, StatusDetailPage(statusId: statusId),
          replace: replaceCurrent);
      return;
    }

    // 规则 B: weibo.com/detail/{id}
    match = RegExp(r'https?://(?:www\.)?weibo\.com/detail/([0-9a-zA-Z]+)',
            caseSensitive: false)
        .firstMatch(clean);
    if (match != null) {
      final statusId = match.group(1)!;
      _navigate(context, StatusDetailPage(statusId: statusId),
          replace: replaceCurrent);
      return;
    }

    // 规则 C: m.weibo.cn/{uid}/{statusId}
    match = RegExp(r'https?://(?:m\.)?weibo\.cn/([0-9]+)/([0-9a-zA-Z]+)',
            caseSensitive: false)
        .firstMatch(clean);
    if (match != null) {
      final statusId = match.group(2)!;
      _navigate(context, StatusDetailPage(statusId: statusId),
          replace: replaceCurrent);
      return;
    }

    // 规则 D: weibo.com/{uid}/{mblogid}
    match = RegExp(r'https?://(?:www\.)?weibo\.com/([0-9]+)/([0-9a-zA-Z]+)',
            caseSensitive: false)
        .firstMatch(clean);
    if (match != null) {
      final statusId = match.group(2)!;
      _navigate(context, StatusDetailPage(statusId: statusId),
          replace: replaceCurrent);
      return;
    }

    // 2. 个人主页匹配
    // m.weibo.cn/u/{uid} 或 weibo.com/u/{uid} 或 m.weibo.cn/profile/{uid}
    match = RegExp(
            r'https?://(?:m\.|www\.)?weibo\.(?:cn|com)/(?:u|profile)/([0-9]+)',
            caseSensitive: false)
        .firstMatch(clean);
    if (match != null) {
      final uid = match.group(1)!;
      _navigate(context, UserProfilePage(uid: uid), replace: replaceCurrent);
      return;
    }

    // weibo.com/n/{screenName} 或 m.weibo.cn/n/{screenName}
    match = RegExp(r'https?://(?:m\.|www\.)?weibo\.(?:cn|com)/n/([^/?#]+)',
            caseSensitive: false)
        .firstMatch(clean);
    if (match != null) {
      final screenName = Uri.decodeComponent(match.group(1)!);
      _navigate(context, UserProfilePage(screenName: screenName),
          replace: replaceCurrent);
      return;
    }

    // 3. 超话匹配
    match = RegExp(r'https?://(?:m\.)?weibo\.cn/p/(100808[0-9a-zA-Z_]+)',
            caseSensitive: false)
        .firstMatch(clean);
    if (match != null) {
      final containerId = match.group(1)!;
      _navigate(context,
          ChaohuaDetailPage(containerid: containerId, title: title ?? '超话社区'),
          replace: replaceCurrent);
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

  static void _navigate(BuildContext context, Widget targetPage,
      {bool replace = false}) {
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
