import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/storage/storage_service.dart';

/// 微博私信/聊天 网页版页面 (精准直连官方私信 https://api.weibo.com/chat#/chat)
class WeiboChatWebViewPage extends ConsumerStatefulWidget {
  final String? initialUrl;

  const WeiboChatWebViewPage({
    super.key,
    this.initialUrl,
  });

  @override
  ConsumerState<WeiboChatWebViewPage> createState() => _WeiboChatWebViewPageState();
}

class _WeiboChatWebViewPageState extends ConsumerState<WeiboChatWebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _progress = 0.0;
  String _title = '微博聊天';

  static const String defaultChatUrl = 'https://api.weibo.com/chat#/chat';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final storage = ref.read(storageServiceProvider);
    final fullCookie = storage.getFullCookie() ?? '';

    // 1. 同步 Cookie 到 WebViewCookieManager
    if (fullCookie.isNotEmpty) {
      final cookieManager = WebViewCookieManager();
      final pairs = fullCookie.split(';');
      for (final p in pairs) {
        final kv = p.trim().split('=');
        if (kv.length >= 2) {
          final name = kv[0].trim();
          final val = kv.sublist(1).join('=').trim();
          if (name.isNotEmpty && val.isNotEmpty) {
            try {
              await cookieManager.setCookie(
                WebViewCookie(
                  name: name,
                  value: val,
                  domain: '.weibo.com',
                  path: '/',
                ),
              );
              await cookieManager.setCookie(
                WebViewCookie(
                  name: name,
                  value: val,
                  domain: 'api.weibo.com',
                  path: '/',
                ),
              );
            } catch (_) {}
          }
        }
      }
    }

    // 2. 初始化 WebViewController
    final targetUrl = widget.initialUrl ?? defaultChatUrl;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100.0);
          },
          onPageStarted: (url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) async {
            if (mounted) {
              setState(() => _isLoading = false);
              final pageTitle = await _controller.getTitle();
              if (pageTitle != null && pageTitle.isNotEmpty && !pageTitle.contains('404')) {
                setState(() => _title = pageTitle);
              }
            }
          },
        ),
      )
      ..loadRequest(
        Uri.parse(targetUrl),
        headers: {
          if (fullCookie.isNotEmpty) 'Cookie': fullCookie,
          'Referer': 'https://weibo.com/',
        },
      );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final targetUrl = widget.initialUrl ?? defaultChatUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded),
            tooltip: '在浏览器中打开',
            onPressed: () async {
              final uri = Uri.parse(targetUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2.5),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.transparent,
                  color: colorScheme.primary,
                ),
              )
            : null,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
