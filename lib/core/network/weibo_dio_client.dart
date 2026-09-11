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
          var effectiveCookie = (fullCookie != null && fullCookie.isNotEmpty)
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
            if ((xsrf == null || xsrf.isEmpty || xsrf == 'deleted') && isMutating) {
              xsrf = await ensureXsrfToken(customCookie: effectiveCookie);
            }

            if (xsrf != null && xsrf.isNotEmpty && xsrf != 'deleted') {
              options.headers['X-XSRF-TOKEN'] = xsrf;
              if (RegExp(r'XSRF-TOKEN=[^;]+', caseSensitive: false).hasMatch(effectiveCookie)) {
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
              var xsrf = _cachedXsrfToken ?? await ensureXsrfToken(customCookie: cookieStr);
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
          final alreadyRetried = error.requestOptions.extra['is_retried'] == true;

          // 1. Handle CSRF Token missing / expired (403 Forbidden with csrf error)
          if (!alreadyRetried && (statusCode == 403 || responseData.toLowerCase().contains('csrf') || responseData.toLowerCase().contains('token'))) {
            error.requestOptions.extra['is_retried'] = true;
            final freshXsrf = await ensureXsrfToken(forceRefresh: true);
            if (freshXsrf != null && freshXsrf.isNotEmpty && freshXsrf != 'deleted') {
              error.requestOptions.headers['X-XSRF-TOKEN'] = freshXsrf;
              var currentCookie = error.requestOptions.headers['Cookie']?.toString() ?? '';
              if (RegExp(r'XSRF-TOKEN=[^;]+', caseSensitive: false).hasMatch(currentCookie)) {
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
            if (fullCookie != null && fullCookie.isNotEmpty && storageService.isLoggedIn()) {
              return handler.next(error);
            }

            // Only refresh visitor sub for guest requests
            error.requestOptions.extra['is_retried'] = true;
            final newSub = await tokenEngine.getOrGenerateVisitorSub(forceRefresh: true);
            if (newSub != null) {
              final subp = storageService.getSubpCookie() ?? '';
              error.requestOptions.headers['Cookie'] = 'SUB=$newSub; SUBP=$subp;';
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

  static String? extractXsrfToken(String? cookie) {
    if (cookie == null || cookie.isEmpty) return null;
    final match = RegExp(
      r'(?:XSRF-TOKEN|xsrf-token|XSRF_TOKEN)=([^;]+)',
      caseSensitive: false,
    ).firstMatch(cookie);
    return match?.group(1)?.trim();
  }

  Future<String?> ensureXsrfToken({bool forceRefresh = false, String? customCookie}) async {
    if (!forceRefresh && _cachedXsrfToken != null && _cachedXsrfToken!.isNotEmpty) {
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
            if (fullCookie != null && fullCookie.isNotEmpty) 'Cookie': fullCookie,
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
    final currentFull = storageService.getFullCookie();
    if (currentFull != null && currentFull.isNotEmpty) {
      if (RegExp(r'XSRF-TOKEN=[^;]+', caseSensitive: false).hasMatch(currentFull)) {
        final updated = currentFull.replaceAll(
          RegExp(r'XSRF-TOKEN=[^;]+', caseSensitive: false),
          'XSRF-TOKEN=$token',
        );
        storageService.setFullCookie(updated);
      } else {
        final updated = '$currentFull; XSRF-TOKEN=$token';
        storageService.setFullCookie(updated);
      }
    }
  }
}

final weiboDioClientProvider = Provider<WeiboDioClient>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return WeiboDioClient(storage);
});
