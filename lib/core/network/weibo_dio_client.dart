import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';
import '../storage/storage_service.dart';
import 'visitor_token_engine.dart';

/// Weibo Unified Dio Client with Cookie Auto-Injection, XSRF Injection, and Token Retry Interceptor
class WeiboDioClient {
  late final Dio dio;
  final StorageService storageService;
  late final VisitorTokenEngine tokenEngine;
  String? _cachedXsrfToken;

  WeiboDioClient(this.storageService) {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 12),
        headers: {
          'User-Agent': ApiConstants.defaultUserAgent,
          'Referer': '${ApiConstants.baseUrl}/',
          'Accept': 'application/json, text/plain, */*',
          'X-Requested-With': 'XMLHttpRequest',
          'client-version': 'v2.44.89',
          'server-version': 'v2026.08.27.1',
        },
      ),
    );

    tokenEngine = VisitorTokenEngine(Dio(), storageService);

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final fullCookie = storageService.getFullCookie();
          final host = options.uri.host.toLowerCase();
          final isMobileWeiboHost = host == 'm.weibo.cn' ||
              host == 'weibo.cn' ||
              host.endsWith('.weibo.cn');
          final scopedCookie = isMobileWeiboHost
              ? storageService.getMobileCookie()
              : storageService.getDesktopCookie();
          var effectiveCookie =
              (scopedCookie != null && scopedCookie.isNotEmpty)
                  ? scopedCookie
                  : (fullCookie != null && fullCookie.isNotEmpty)
                      ? fullCookie
                      : (() {
                          final sub = storageService.getSubCookie();
                          final subp = storageService.getSubpCookie() ?? '';
                          if (sub != null && sub.isNotEmpty) {
                            return 'SUB=$sub; ${subp.isNotEmpty ? "SUBP=$subp;" : ""}';
                          }
                          return '';
                        })();

          final isMutating = options.method.toUpperCase() != 'GET';

          if (effectiveCookie.isNotEmpty) {
            var xsrf = _cachedXsrfToken ?? extractXsrfToken(effectiveCookie);
            if ((xsrf == null || xsrf.isEmpty || xsrf == 'deleted') &&
                isMutating) {
              xsrf = await ensureXsrfToken(customCookie: effectiveCookie);
            }

            if (xsrf != null && xsrf.isNotEmpty && xsrf != 'deleted') {
              options.headers['X-XSRF-TOKEN'] = xsrf;
              if (RegExp(r'XSRF-TOKEN=[^;]+', caseSensitive: false)
                  .hasMatch(effectiveCookie)) {
                effectiveCookie = effectiveCookie.replaceAll(
                  RegExp(r'XSRF-TOKEN=[^;]+', caseSensitive: false),
                  'XSRF-TOKEN=$xsrf',
                );
              } else {
                effectiveCookie = '$effectiveCookie; XSRF-TOKEN=$xsrf';
              }
            }

            options.headers['Cookie'] = effectiveCookie;
            options.headers['X-Requested-With'] = 'XMLHttpRequest';
            return handler.next(options);
          }

          // Guest / Visitor fallback
          var sub = storageService.getSubCookie();
          if (sub == null || sub.isEmpty) {
            sub = await tokenEngine.getOrGenerateVisitorSub();
          }

          final subp = storageService.getSubpCookie() ?? '';
          var cookieStr = '';
          if (sub != null && sub.isNotEmpty) {
            cookieStr = 'SUB=$sub; ${subp.isNotEmpty ? "SUBP=$subp;" : ""}';
            if (isMutating) {
              var xsrf = _cachedXsrfToken ??
                  await ensureXsrfToken(customCookie: cookieStr);
              if (xsrf != null && xsrf.isNotEmpty && xsrf != 'deleted') {
                options.headers['X-XSRF-TOKEN'] = xsrf;
                cookieStr = '$cookieStr XSRF-TOKEN=$xsrf;';
              }
            }
            options.headers['Cookie'] = cookieStr;
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          final setCookies = response.headers['set-cookie'];
          if (setCookies != null) {
            for (final sc in setCookies) {
              final token = extractXsrfToken(sc);
              if (token != null && token.isNotEmpty && token != 'deleted') {
                _updateXsrfToken(token);
                break;
              }
            }
          }
          return handler.next(response);
        },
        onError: (DioException error, handler) async {
          final statusCode = error.response?.statusCode;
          final responseData = error.response?.data?.toString() ?? '';
          final alreadyRetried =
              error.requestOptions.extra['is_retried'] == true;

          // 1. Handle CSRF Token missing / expired (403 Forbidden with csrf error)
          if (!alreadyRetried &&
              (statusCode == 403 ||
                  responseData.toLowerCase().contains('csrf') ||
                  responseData.toLowerCase().contains('token'))) {
            error.requestOptions.extra['is_retried'] = true;
            final freshXsrf = await ensureXsrfToken(forceRefresh: true);
            if (freshXsrf != null &&
                freshXsrf.isNotEmpty &&
                freshXsrf != 'deleted') {
              error.requestOptions.headers['X-XSRF-TOKEN'] = freshXsrf;
              var currentCookie =
                  error.requestOptions.headers['Cookie']?.toString() ?? '';
              if (RegExp(r'XSRF-TOKEN=[^;]+', caseSensitive: false)
                  .hasMatch(currentCookie)) {
                currentCookie = currentCookie.replaceAll(
                  RegExp(r'XSRF-TOKEN=[^;]+', caseSensitive: false),
                  'XSRF-TOKEN=$freshXsrf',
                );
              } else {
                currentCookie = '$currentCookie; XSRF-TOKEN=$freshXsrf';
              }
              error.requestOptions.headers['Cookie'] = currentCookie;

              try {
                final retryResponse = await dio.fetch(error.requestOptions);
                return handler.resolve(retryResponse);
              } catch (e) {
                return handler.next(error);
              }
            }
          }

          // 2. Handle Visitor sub expired (432 or 401 for unauthenticated requests)
          if (!alreadyRetried && (statusCode == 432 || statusCode == 401)) {
            final fullCookie = storageService.getFullCookie();
            if (fullCookie != null &&
                fullCookie.isNotEmpty &&
                storageService.isLoggedIn()) {
              return handler.next(error);
            }

            // Only refresh visitor sub for guest requests
            error.requestOptions.extra['is_retried'] = true;
            final newSub =
                await tokenEngine.getOrGenerateVisitorSub(forceRefresh: true);
            if (newSub != null) {
              final subp = storageService.getSubpCookie() ?? '';
              error.requestOptions.headers['Cookie'] =
                  'SUB=$newSub; SUBP=$subp;';
              try {
                final retryResponse = await dio.fetch(error.requestOptions);
                return handler.resolve(retryResponse);
              } catch (e) {
                return handler.next(error);
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  /// Fetches a long-form article as official HTML.
  ///
  /// Long-form pages are document requests, not AJAX JSON endpoints. They
  /// must not inherit the JSON client's `X-Requested-With` header or its
  /// CSRF/visitor retry interceptor. Try the scoped desktop session first so
  /// restricted articles keep working, then retry the public page without a
  /// Cookie when a stale session returns a login/empty shell. Keep all
  /// non-empty candidates: a stale desktop cookie can return a valid-looking
  /// shell before the public candidate returns the actual article body.
  Future<String> getArticleHtml(String articleId) async {
    final candidates = await getArticleHtmlCandidates(articleId);
    for (final html in candidates) {
      final lower = html.toLowerCase();
      if (lower.contains('node-type="contentbody"') ||
          lower.contains('class="wb_editor_iframe')) {
        return html;
      }
    }
    return candidates.first;
  }

  /// Returns the official HTML responses for each available session candidate.
  ///
  /// The caller can parse each response and choose the first one containing
  /// real article blocks. This matters when the persisted desktop cookie is
  /// stale: Weibo may return a 200 HTML shell for that cookie instead of a
  /// useful article document, while the unauthenticated public request still
  /// contains the public article.
  Future<List<String>> getArticleHtmlCandidates(String articleId) async {
    final desktopCookie = storageService.getDesktopCookie();
    final fullCookie = storageService.getFullCookie();
    final cookies = <String?>[];
    for (final candidate in [desktopCookie, fullCookie]) {
      final value = candidate?.trim() ?? '';
      if (value.isNotEmpty && !cookies.contains(value)) cookies.add(value);
    }
    cookies.add(null);

    final documentClient = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        followRedirects: true,
        maxRedirects: 5,
        headers: {
          'User-Agent': ApiConstants.defaultUserAgent,
          'Referer': '${ApiConstants.baseUrl}/',
          'Accept': 'text/html,application/xhtml+xml',
        },
      ),
    );

    String lastHtml = '';
    Object? lastError;
    final responses = <String>[];
    try {
      for (final cookie in cookies) {
        try {
          final response = await documentClient.get<String>(
            '/ttarticle/p/show',
            queryParameters: {'id': articleId},
            options: Options(
              responseType: ResponseType.plain,
              headers: {
                if (cookie != null) 'Cookie': cookie,
              },
            ),
          );
          final html = response.data?.toString() ?? '';
          if (html.isNotEmpty) {
            lastHtml = html;
            if (!responses.contains(html)) responses.add(html);
          }
        } catch (error) {
          lastError = error;
        }
      }
    } finally {
      documentClient.close(force: true);
    }

    if (responses.isNotEmpty) return List.unmodifiable(responses);
    if (lastHtml.isNotEmpty) return [lastHtml];
    if (lastError != null) throw lastError!;
    throw StateError('微博文章请求未返回内容');
  }

  static String? extractXsrfToken(String? cookie) {
    if (cookie == null || cookie.isEmpty) return null;
    final match = RegExp(
      r'(?:XSRF-TOKEN|xsrf-token|XSRF_TOKEN)=([^;]+)',
      caseSensitive: false,
    ).firstMatch(cookie);
    return match?.group(1)?.trim();
  }

  Future<String?> ensureXsrfToken(
      {bool forceRefresh = false, String? customCookie}) async {
    if (!forceRefresh &&
        _cachedXsrfToken != null &&
        _cachedXsrfToken!.isNotEmpty) {
      return _cachedXsrfToken;
    }

    final fullCookie = customCookie ?? storageService.getFullCookie();
    final extracted = extractXsrfToken(fullCookie);
    if (!forceRefresh && extracted != null && extracted.isNotEmpty) {
      _cachedXsrfToken = extracted;
      return extracted;
    }

    try {
      final rawDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
          headers: {
            'User-Agent': ApiConstants.defaultUserAgent,
            'Referer': 'https://weibo.com/',
            'Accept': 'application/json, text/plain, */*',
            'X-Requested-With': 'XMLHttpRequest',
            if (fullCookie != null && fullCookie.isNotEmpty)
              'Cookie': fullCookie,
          },
        ),
      );

      // 1. Primary: Fetch from https://weibo.com/ajax/statuses/config
      try {
        final res = await rawDio.get('https://weibo.com/ajax/statuses/config');
        final setCookies = res.headers['set-cookie'];
        if (setCookies != null) {
          for (final sc in setCookies) {
            final token = extractXsrfToken(sc);
            if (token != null && token.isNotEmpty && token != 'deleted') {
              _updateXsrfToken(token);
              return token;
            }
          }
        }
        if (res.data is Map<String, dynamic>) {
          final st = res.data['data']?['st']?.toString();
          if (st != null && st.isNotEmpty) {
            _updateXsrfToken(st);
            return st;
          }
        }
      } catch (_) {}

      // 2. Secondary: Fetch from https://weibo.com/ajax/config/getconfig
      final res2 = await rawDio.get('https://weibo.com/ajax/config/getconfig');
      final setCookies2 = res2.headers['set-cookie'];
      if (setCookies2 != null) {
        for (final sc in setCookies2) {
          final token = extractXsrfToken(sc);
          if (token != null && token.isNotEmpty && token != 'deleted') {
            _updateXsrfToken(token);
            return token;
          }
        }
      }

      if (res2.data is Map<String, dynamic>) {
        final st = res2.data['data']?['st']?.toString();
        if (st != null && st.isNotEmpty) {
          _updateXsrfToken(st);
          return st;
        }
      }
    } catch (_) {}

    return _cachedXsrfToken;
  }

  void _updateXsrfToken(String token) {
    _cachedXsrfToken = token;
    String updateCookie(String? cookie) {
      if (cookie == null || cookie.isEmpty) return '';
      final tokenPattern = RegExp(r'XSRF-TOKEN=[^;]+', caseSensitive: false);
      return tokenPattern.hasMatch(cookie)
          ? cookie.replaceAll(tokenPattern, 'XSRF-TOKEN=$token')
          : '$cookie; XSRF-TOKEN=$token';
    }

    final currentFull = storageService.getFullCookie();
    final updatedFull = updateCookie(currentFull);
    if (updatedFull.isNotEmpty) {
      storageService.setFullCookie(updatedFull);
    }

    final currentDesktop = storageService.getDesktopCookie();
    final updatedDesktop = updateCookie(currentDesktop);
    if (updatedDesktop.isNotEmpty) {
      storageService.setDesktopCookie(updatedDesktop);
    }

    final currentMobile = storageService.getMobileCookie();
    final updatedMobile = updateCookie(currentMobile);
    if (updatedMobile.isNotEmpty) {
      storageService.setMobileCookie(updatedMobile);
    }
  }
}

final weiboDioClientProvider = Provider<WeiboDioClient>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return WeiboDioClient(storage);
});
