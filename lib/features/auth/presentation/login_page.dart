import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/utils/app_dialog.dart';
import '../../../core/utils/app_toast.dart';
import '../../feed/presentation/feed_controller.dart';

/// Official Weibo Login with Automatic Cookie/Token Extraction
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  static const MethodChannel _cookieChannel = MethodChannel('com.sharelite/cookies');
  late final WebViewController _controller;
  double _progress = 0.0;
  bool _isChecking = false;
  bool _hasSuccessfullyLogged = false;

  static const String _defaultLoginUrl =
      'https://passport.weibo.com/sso/signin?entry=wapsso&source=wapssowb&url=https%3A%2F%2Fm.weibo.cn%2F';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
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
            if (url.contains('crossdomain')) {
              Future.delayed(const Duration(milliseconds: 350), () {
                if (mounted && !_hasSuccessfullyLogged) {
                  _checkAndSaveCookies(silent: true);
                }
              });
            }
            return NavigationDecision.navigate;
          },
          onUrlChange: (UrlChange change) async {
            final url = change.url ?? '';
            if (url.contains('crossdomain') ||
                url.contains('ticket=') ||
                url.contains('m.weibo.cn') ||
                url.contains('weibo.com')) {
              await _checkAndSaveCookies(silent: true);
            }
          },
          onWebResourceError: (WebResourceError error) async {
            // Check cookies safely if crossdomain errored
            await _checkAndSaveCookies(silent: true);
          },
          onPageFinished: (url) async {
            if (url.contains('crossdomain') ||
                url.contains('ticket=') ||
                url.contains('m.weibo.cn') ||
                url.contains('weibo.com')) {
              await _checkAndSaveCookies(silent: true);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_defaultLoginUrl));
  }

  Future<void> _checkAndSaveCookies({bool silent = false}) async {
    if (_hasSuccessfullyLogged) return;
    if (_isChecking) return;
    if (!silent && mounted) setState(() => _isChecking = true);

    try {
      // 1. Primary: Extract directly from Android's Native CookieManager via Platform Channel
      String? nativeCookies;
      try {
        nativeCookies = await _cookieChannel.invokeMethod<String>('getNativeCookies');
      } catch (_) {}

      // 2. Secondary: JS extraction inside WebView
      String? jsCookies;
      try {
        final rawJs = await _controller.runJavaScriptReturningResult('document.cookie');
        var s = rawJs.toString();
        if (s.startsWith('"') && s.endsWith('"')) s = jsonDecode(s);
        jsCookies = s;
      } catch (_) {}

      final effectiveCookie = (nativeCookies != null && nativeCookies.isNotEmpty)
          ? nativeCookies
          : (jsCookies ?? '');

      if (effectiveCookie.isNotEmpty && (effectiveCookie.contains('SUB=') || effectiveCookie.contains('_2A'))) {
        final success = await ref.read(authProvider.notifier).setAndVerifyCookie(effectiveCookie);
        if (success && mounted) {
          if (_hasSuccessfullyLogged) return;
          _hasSuccessfullyLogged = true;

          ref.read(feedControllerProvider.notifier).setCategory('friends');
          AppToast.show(context, '🎉 微博账号登录成功！已为您同步真实关注流');
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
          }
          return;
        }
      }

      if (!silent && mounted) {
        AppToast.show(context, '未检测到有效登录凭据，请在页面完成手机验证码或密码登录后再次点击');
      }
    } catch (e) {
      if (!silent && mounted) {
        AppToast.show(context, '读取登录凭据异常: $e');
      }
    } finally {
      if (mounted && !silent) setState(() => _isChecking = false);
    }
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final raw = controller.text.trim();
              if (raw.isNotEmpty) {
                final nav = Navigator.of(context);
                Navigator.pop(ctx);

                final success = await ref.read(authProvider.notifier).setAndVerifyCookie(raw);
                if (success) {
                  ref.read(feedControllerProvider.notifier).setCategory('friends');
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
                _controller.loadRequest(Uri.parse(_defaultLoginUrl));
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
          Expanded(child: WebViewWidget(controller: _controller)),
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
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline_rounded, size: 18),
                      label: Text(_isChecking ? '正在检测凭据...' : '完成登录 / 同步凭据'),
                      onPressed: _isChecking ? null : () => _checkAndSaveCookies(silent: false),
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
