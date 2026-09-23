import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/utils/app_dialog.dart';
import '../../../core/utils/app_toast.dart';
import '../../feed/presentation/feed_controller.dart';

/// Only probe cookies after the WebView has left the passport login page.
/// The original implementation used substring matching, so the initial
/// passport URL matched its encoded `m.weibo.cn` return URL and repeatedly
/// verified the stale session before login had completed.
bool shouldProbeCookiesForUrl(String url) {
  final parsed = Uri.tryParse(url);
  final host = parsed?.host.toLowerCase() ?? '';
  return host == 'm.weibo.cn' ||
      host == 'weibo.cn' ||
      host == 'm.weibo.com' ||
      host == 'weibo.com';
}

/// Checks if the URL indicates a post-login credential exchange in progress
/// (e.g. Sina SSO ticket redirect or landing page).
bool isLoginSuccessTransitionUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('ticket=') ||
      lower.contains('crossdomain') ||
      shouldProbeCookiesForUrl(url);
}

const String weiboWebLoginUrl =
    'https://passport.weibo.com/sso/signin?entry=wapsso&source=wapssowb&url=https%3A%2F%2Fm.weibo.cn%2F';

String cookieNamesForDiagnostics(String? raw) {
  final names = <String>[];
  for (final segment in (raw ?? '').split(';')) {
    final separator = segment.indexOf('=');
    if (separator <= 0) continue;
    final name = segment.substring(0, separator).trim();
    if (name.isNotEmpty && !names.contains(name)) names.add(name);
  }
  return names.isEmpty ? '无' : names.join(',');
}

/// Official Weibo Login with Automatic Cookie/Token Extraction
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  static const MethodChannel _cookieChannel =
      MethodChannel('com.sharelite/cookies');
  late final WebViewController _controller;
  double _progress = 0.0;
  bool _isChecking = false;
  bool _manualCheckQueued = false;
  bool _hasSuccessfullyLogged = false;
  bool _isAutoLoggingIn = false;
  Timer? _cookieCheckTimer;
  Timer? _autoLoginPollingTimer;
  final Set<CancelToken> _activeVerificationTokens = {};

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
      )
      ..addJavaScriptChannel(
        'ReviewLoginBridge',
        onMessageReceived: (JavaScriptMessage message) {
          if (message.message == 'login_triggered') {
            _startAutoLoginFlow(immediateOverlay: false);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100.0);
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            // Prevent custom schemes (sinaweibo://, intent://, wbmain://)
            if (!url.startsWith('http://') && !url.startsWith('https://')) {
              return NavigationDecision.prevent;
            }
            if (isLoginSuccessTransitionUrl(url)) {
              _startAutoLoginFlow(immediateOverlay: true);
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            if (isLoginSuccessTransitionUrl(url)) {
              _startAutoLoginFlow(immediateOverlay: true);
            }
          },
          onUrlChange: (UrlChange change) {
            final url = change.url ?? '';
            if (isLoginSuccessTransitionUrl(url)) {
              _startAutoLoginFlow(immediateOverlay: true);
            }
          },
          onWebResourceError: (WebResourceError error) {
            final failedUrl = error.url ?? '';
            if (isLoginSuccessTransitionUrl(failedUrl)) {
              _startAutoLoginFlow(immediateOverlay: false);
            }
          },
          onPageFinished: (url) {
            if (isLoginSuccessTransitionUrl(url)) {
              _startAutoLoginFlow(immediateOverlay: true);
            }
            _injectLoginListener();
          },
        ),
      );
    _configureWebViewAndLoad();
  }

  Future<void> _configureWebViewAndLoad() async {
    try {
      final cookieManager = WebViewCookieManager().platform;
      final platformController = _controller.platform;
      if (cookieManager is AndroidWebViewCookieManager &&
          platformController is AndroidWebViewController) {
        // Weibo's passport -> login.sina.com.cn -> m.weibo.cn callback uses
        // a third-party SSO cookie. Android WebView defaults this to false.
        await cookieManager.setAcceptThirdPartyCookies(
          platformController,
          true,
        );
      }
    } catch (_) {
      // Other platforms and older WebView implementations do not expose the
      // Android-only setting; the normal cookie bridge remains available.
    }
    if (mounted && !_hasSuccessfullyLogged) {
      await _controller.loadRequest(Uri.parse(weiboWebLoginUrl));
    }
  }

  void _scheduleCookieCheck({
    Duration delay = const Duration(milliseconds: 700),
    bool silent = true,
  }) {
    if (_hasSuccessfullyLogged) return;
    _cookieCheckTimer?.cancel();
    _cookieCheckTimer = Timer(delay, () {
      _cookieCheckTimer = null;
      if (mounted && !_hasSuccessfullyLogged) {
        _checkAndSaveCookies(silent: silent);
      }
    });
  }

  Future<void> _checkAndSaveCookies({bool silent = false}) async {
    if (_hasSuccessfullyLogged) return;
    _cookieCheckTimer?.cancel();
    _cookieCheckTimer = null;
    if (_isChecking) {
      if (!silent && !_manualCheckQueued) {
        _manualCheckQueued = true;
        if (mounted) {
          setState(() {});
          AppToast.show(context, '当前检测尚未结束，已排队重新读取凭据');
        }
      }
      return;
    }
    // Any real check reads a fresh Cookie snapshot, so it can satisfy a
    // manually queued retry even if a navigation callback starts it first.
    _manualCheckQueued = false;
    _isChecking = true;
    if (mounted) setState(() => _isChecking = true);

    try {
      // 1. Primary: Extract directly from Android's Native CookieManager via Platform Channel
      String? nativeCookies;
      try {
        nativeCookies =
            await _cookieChannel.invokeMethod<String>('getNativeCookies');
      } catch (_) {}

      // Read host-scoped jars separately. The legacy combined bridge can
      // contain duplicate SUB values from different domains.
      String? desktopCookies;
      String? mobileCookies;
      String? ssoCookies;
      try {
        final scoped = await _cookieChannel.invokeMethod<dynamic>(
          'getNativeCookiesByDomain',
        );
        if (scoped is Map) {
          final value = scoped['desktop']?.toString() ?? '';
          if (value.isNotEmpty) desktopCookies = value;
          final mobileValue = scoped['mobile']?.toString() ?? '';
          if (mobileValue.isNotEmpty) mobileCookies = mobileValue;
          final ssoValue = scoped['sso']?.toString() ?? '';
          if (ssoValue.isNotEmpty) ssoCookies = ssoValue;
        }
      } catch (_) {}

      // 2. Secondary: JS extraction inside WebView
      String? jsCookies;
      try {
        final rawJs =
            await _controller.runJavaScriptReturningResult('document.cookie');
        var s = rawJs.toString();
        if (s.startsWith('"') && s.endsWith('"')) s = jsonDecode(s);
        jsCookies = s;
      } catch (_) {}

      final candidates = <String>[];
      void addCandidate(String? raw) {
        final value = raw?.trim() ?? '';
        if (value.isEmpty ||
            (!RegExp(r'(?:^|;\s*)SUB=', caseSensitive: false).hasMatch(value) &&
                !value.contains('_2A'))) {
          return;
        }
        if (!candidates.contains(value)) candidates.add(value);
      }

      // The WebView login flow lands on m.weibo.cn. Prioritize mobile and desktop
      // cookies, followed by SSO, JS, and combined native jars.
      addCandidate(mobileCookies);
      addCandidate(desktopCookies);
      addCandidate(ssoCookies);
      addCandidate(jsCookies);
      addCandidate(nativeCookies);

      final checkDeadline = DateTime.now().add(const Duration(seconds: 30));
      for (final effectiveCookie in candidates) {
        if (!mounted || _hasSuccessfullyLogged) break;
        final remaining = checkDeadline.difference(DateTime.now());
        if (remaining <= Duration.zero) break;
        final attemptTimeout = remaining < const Duration(seconds: 25)
            ? remaining
            : const Duration(seconds: 25);
        final cancelToken = CancelToken();
        _activeVerificationTokens.add(cancelToken);
        bool success;
        try {
          success = await ref.read(authProvider.notifier).setAndVerifyCookie(
                effectiveCookie,
                requireDesktopSession: false,
                cancelToken: cancelToken,
                verificationTimeout: attemptTimeout,
              );
        } finally {
          _activeVerificationTokens.remove(cancelToken);
        }
        if (success && mounted) {
          if (_hasSuccessfullyLogged) return;
          _hasSuccessfullyLogged = true;

          // Keep mobile login completion immediate, but wait for the desktop
          // cookie reconciliation before starting the account feed request.
          final authNotifier = ref.read(authProvider.notifier);
          final feedController = ref.read(feedControllerProvider.notifier);
          final loggedInUid = ref.read(authProvider).uid;
          unawaited(() async {
            try {
              await authNotifier.reconcileNativeSession();
            } catch (_) {}
            if (authNotifier.isLoggedInAs(loggedInUid)) {
              await feedController.setCategory('friends');
            }
          }());
          AppToast.show(context, '🎉 微博账号登录成功，正在加载关注流');
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
          }
          return;
        }
      }

      if (!silent && mounted) {
        final currentUrl = await _controller.currentUrl() ?? '未知页面';
        if (!mounted) return;
        final cookieSummary = <String>[
          '移动:${cookieNamesForDiagnostics(mobileCookies)}',
          '桌面:${cookieNamesForDiagnostics(desktopCookies)}',
          'SSO:${cookieNamesForDiagnostics(ssoCookies)}',
        ].join('；');
        final reason =
            candidates.isEmpty ? '微博域尚未写入登录 Cookie' : '已读取 Cookie，但微博接口未确认登录';
        AppToast.show(
          context,
          '$reason\n$cookieSummary\n页面:$currentUrl',
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        AppToast.show(context, '读取登录凭据异常: $e');
      }
    } finally {
      _isChecking = false;
      if (mounted) setState(() {});
      final retryManually = _manualCheckQueued;
      if (retryManually && mounted && !_hasSuccessfullyLogged) {
        _scheduleCookieCheck(
          delay: const Duration(milliseconds: 250),
          silent: false,
        );
      } else {
        _manualCheckQueued = false;
      }
    }
  }

  void _injectLoginListener() {
    const js = '''
(function() {
  if (window.__review_login_attached) return;
  window.__review_login_attached = true;
  function notify() {
    try {
      if (window.ReviewLoginBridge) {
        window.ReviewLoginBridge.postMessage('login_triggered');
      }
    } catch(e) {}
  }
  document.addEventListener('click', function(e) {
    var el = e.target;
    while (el && el !== document.body) {
      var text = (el.innerText || el.value || '').trim();
      if (text.indexOf('登录') !== -1 || text.indexOf('Log In') !== -1) {
        notify();
        break;
      }
      el = el.parentElement;
    }
  }, true);
  document.addEventListener('submit', function(e) {
    notify();
  }, true);
})();
''';
    _controller.runJavaScript(js).catchError((_) {});
  }

  void _startAutoLoginFlow({bool immediateOverlay = true}) {
    if (_hasSuccessfullyLogged) return;
    if (immediateOverlay && !_isAutoLoggingIn && mounted) {
      setState(() => _isAutoLoggingIn = true);
    }
    _autoLoginPollingTimer?.cancel();
    int attempts = 0;
    _autoLoginPollingTimer = Timer.periodic(
      const Duration(milliseconds: 600),
      (timer) async {
        if (_hasSuccessfullyLogged || !mounted) {
          timer.cancel();
          return;
        }
        attempts++;
        if (attempts > 35) {
          timer.cancel();
          if (mounted && _isAutoLoggingIn) {
            setState(() => _isAutoLoggingIn = false);
          }
          return;
        }
        await _checkAndSaveCookies(silent: true);
      },
    );
    _checkAndSaveCookies(silent: true);
  }

  @override
  void dispose() {
    _cookieCheckTimer?.cancel();
    _autoLoginPollingTimer?.cancel();
    for (final token in _activeVerificationTokens) {
      token.cancel('Login page disposed');
    }
    super.dispose();
  }

  void _showManualCookieDialog() {
    final controller = TextEditingController();
    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动导入 Token / Cookie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '支持直接粘贴完整 Cookie 字符串，或单独的 SUB 字符串：',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '例如: SUB=_2AkMR...; SUBP=... 或 _2AkMR...',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final raw = controller.text.trim();
              if (raw.isNotEmpty) {
                final nav = Navigator.of(context);
                Navigator.pop(ctx);

                final success = await ref
                    .read(authProvider.notifier)
                    .setAndVerifyCookie(raw);
                if (success) {
                  ref
                      .read(feedControllerProvider.notifier)
                      .setCategory('friends');
                  if (mounted) {
                    AppToast.show(context, '🎉 凭据导入成功！已切换至关注流');
                  }
                  nav.pop(true);
                } else {
                  if (mounted) {
                    AppToast.show(context, '导入失败，未识别到有效凭据');
                  }
                }
              }
            },
            child: const Text('验证并导入'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('微博账号登录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined, size: 20),
            tooltip: '清除旧会话',
            onPressed: () async {
              try {
                await _cookieChannel.invokeMethod('clearNativeCookies');
                await WebViewCookieManager().clearCookies();
                _controller.loadRequest(Uri.parse(weiboWebLoginUrl));
                if (context.mounted) {
                  AppToast.show(context, '已清除旧登录会话并重置页面');
                }
              } catch (_) {}
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.paste_rounded, size: 18),
            label: const Text('手动导入'),
            onPressed: _showManualCookieDialog,
          ),
          const SizedBox(width: 8),
        ],
        bottom: _progress < 1.0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3.0),
                child: LinearProgressIndicator(value: _progress),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isAutoLoggingIn && !_hasSuccessfullyLogged)
                  Container(
                    color: colorScheme.surface,
                    width: double.infinity,
                    height: double.infinity,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 38,
                            height: 38,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '正在完成登录并同步凭据...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '已检测到登录操作，正在为您自动同步，无需手动操作',
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('刷新页面'),
                      onPressed: () => _controller.reload(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      icon: _isChecking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline_rounded,
                              size: 18),
                      label: Text(
                        _isChecking
                            ? (_manualCheckQueued ? '已排队重新检测' : '检测中（点击可重试）')
                            : '完成登录 / 同步凭据',
                      ),
                      onPressed: () => _checkAndSaveCookies(silent: false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
