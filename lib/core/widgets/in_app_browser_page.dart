import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/link_routing_service.dart';
import '../storage/storage_service.dart';
import '../utils/app_toast.dart';
import '../utils/haptic_feedback_util.dart';

/// 全功能应用内浏览器 (支持 Cookie 注入、进度条、微博文章拦截、复制链接与外部打开)
class InAppBrowserPage extends ConsumerStatefulWidget {
  final String url;
  final String? title;

  const InAppBrowserPage({
    super.key,
    required this.url,
    this.title,
  });

  @override
  ConsumerState<InAppBrowserPage> createState() => _InAppBrowserPageState();
}

class _InAppBrowserPageState extends ConsumerState<InAppBrowserPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _progress = 0.0;
  String _currentTitle = '';
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.title ?? '网页浏览';
    _currentUrl = widget.url;
    _initWebView();
  }

  Future<void> _initWebView() async {
    final storage = ref.read(storageServiceProvider);
    final fullCookie = storage.getFullCookie() ?? '';

    // 1. 同步 Cookie 到各大微博与新浪域名
    if (fullCookie.isNotEmpty) {
      final cookieManager = WebViewCookieManager();
      final pairs = fullCookie.split(';');
      final domains = [
        '.weibo.com',
        'weibo.com',
        '.weibo.cn',
        'm.weibo.cn',
        'api.weibo.com',
        'sina.cn',
        '.sina.cn',
        't.cn',
      ];
      for (final p in pairs) {
        final kv = p.trim().split('=');
        if (kv.length >= 2) {
          final name = kv[0].trim();
          final val = kv.sublist(1).join('=').trim();
          if (name.isNotEmpty && val.isNotEmpty) {
            for (final d in domains) {
              try {
                await cookieManager.setCookie(
                  WebViewCookie(
                    name: name,
                    value: val,
                    domain: d,
                    path: '/',
                  ),
                );
              } catch (_) {}
            }
          }
        }
      }
    }

    // 2. 初始化 WebViewController
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100.0);
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _currentUrl = url;
              });
            }
          },
          onPageFinished: (url) async {
            if (mounted) {
              setState(() => _isLoading = false);
              final pageTitle = await _controller.getTitle();
              if (pageTitle != null && pageTitle.isNotEmpty && !pageTitle.contains('404')) {
                setState(() => _currentTitle = pageTitle);
              }
            }
          },
          onNavigationRequest: (request) {
            final target = request.url;
            // 如果跳转到了微博文章/博主原生页面，尝试拦截并在原生打开
            if (LinkRoutingService.canHandleNatively(target)) {
              LinkRoutingService.openUrl(context, target, replaceCurrent: true);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(
        Uri.parse(widget.url),
        headers: {
          if (fullCookie.isNotEmpty) 'Cookie': fullCookie,
        },
      );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currentTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_currentUrl.isNotEmpty)
              Text(
                _currentUrl,
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
            onPressed: () {
              HapticFeedbackUtil.light();
              _controller.reload();
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) async {
              HapticFeedbackUtil.light();
              if (val == 'copy') {
                final current = (await _controller.currentUrl()) ?? _currentUrl;
                await Clipboard.setData(ClipboardData(text: current));
                if (context.mounted) {
                  AppToast.show(context, '链接已复制到剪贴板');
                }
              } else if (val == 'browser') {
                final current = (await _controller.currentUrl()) ?? _currentUrl;
                final uri = Uri.tryParse(current);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('复制链接'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'browser',
                child: Row(
                  children: [
                    Icon(Icons.open_in_browser_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('在外部浏览器打开'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 2,
                  color: colorScheme.primary,
                  backgroundColor: Colors.transparent,
                ),
              )
            : null,
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _controller.canGoBack()) {
            await _controller.goBack();
          } else {
            if (context.mounted) Navigator.pop(context);
          }
        },
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
