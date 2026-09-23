import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../constants/api_constants.dart';
import '../storage/storage_service.dart';

enum CookieValidationStatus {
  idle,
  valid,
  needsDesktopSync,
  expired,
  unavailable,
}

typedef DesktopCookieVerifier = Future<bool> Function(
  String cookie,
  String expectedUid,
);

class AuthState {
  final bool isLoggedIn;
  final String? uid;
  final String? nickname;
  final String? avatar;
  final String? subCookie;
  final String? subpCookie;
  final String? fullCookie;
  final bool isValidating;
  final bool isCookieExpired;
  final CookieValidationStatus cookieValidationStatus;

  const AuthState({
    this.isLoggedIn = false,
    this.uid,
    this.nickname,
    this.avatar,
    this.subCookie,
    this.subpCookie,
    this.fullCookie,
    this.isValidating = false,
    this.isCookieExpired = false,
    this.cookieValidationStatus = CookieValidationStatus.idle,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    String? uid,
    String? nickname,
    String? avatar,
    String? subCookie,
    String? subpCookie,
    String? fullCookie,
    bool? isValidating,
    bool? isCookieExpired,
    CookieValidationStatus? cookieValidationStatus,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      uid: uid ?? this.uid,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      subCookie: subCookie ?? this.subCookie,
      subpCookie: subpCookie ?? this.subpCookie,
      fullCookie: fullCookie ?? this.fullCookie,
      isValidating: isValidating ?? this.isValidating,
      isCookieExpired: isCookieExpired ?? this.isCookieExpired,
      cookieValidationStatus:
          cookieValidationStatus ?? this.cookieValidationStatus,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  static const MethodChannel _cookieChannel =
      MethodChannel('com.sharelite/cookies');

  final StorageService _storage;
  final DesktopCookieVerifier? _desktopCookieVerifier;
  Future<bool>? _nativeSyncFuture;

  AuthNotifier(
    this._storage, {
    DesktopCookieVerifier? desktopCookieVerifier,
  })  : _desktopCookieVerifier = desktopCookieVerifier,
        super(const AuthState()) {
    _loadFromStorage();
  }

  /// Whether the verified session still belongs to [uid] after async sync.
  bool isLoggedInAs(String? uid) =>
      uid != null && uid.isNotEmpty && state.isLoggedIn && state.uid == uid;

  /// Normalize cookies collected from multiple WebView domains.
  ///
  /// CookieManager may return the same cookie name more than once when values
  /// are collected from different domains. Sending duplicate SUB/SUBP values
  /// makes the server choose an arbitrary session. Keep the first value,
  /// which corresponds to the first, most relevant domain queried by the
  /// native bridge, and discard later duplicates.
  static String normalizeCookieHeader(String rawInput) {
    final cookies = <String, String>{};
    for (final segment in rawInput.split(';')) {
      final part = segment.trim();
      final separator = part.indexOf('=');
      if (separator <= 0) continue;

      final name = part.substring(0, separator).trim();
      final value = part.substring(separator + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;

      cookies.putIfAbsent(name.toLowerCase(), () => '$name=$value');
    }
    return cookies.values.join('; ');
  }

  static bool _isTruthy(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  /// A UID by itself is not enough to establish a login session; callers must
  /// also identify which documented verification path confirmed it. WebView
  /// login starts on m.weibo.cn, so callers may accept a verified mobile
  /// session while the desktop SSO cookie is still being synchronized.
  static bool canCommitVerifiedSession({
    required String uid,
    required bool desktopSessionVerified,
    required bool mobileSessionVerified,
    required bool requireDesktopSession,
  }) {
    if (uid.trim().isEmpty) return false;
    if (requireDesktopSession) return desktopSessionVerified;
    return desktopSessionVerified || mobileSessionVerified;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static bool isDefinitiveDesktopLogoutPayload(dynamic value) {
    final body = _asMap(value);
    if (body == null) return false;
    final ok = body['ok'];
    final redirectUrl = body['url']?.toString().toLowerCase() ?? '';
    return (ok is num && ok.toInt() == -100) || redirectUrl.contains('login');
  }

  static String desktopSessionUid(dynamic value) {
    final body = _asMap(value);
    final data = _asMap(body?['data']);
    final user = _asMap(data?['user']) ?? _asMap(body?['user']);
    for (final value in [
      data?['uid'],
      data?['id'],
      data?['idstr'],
      user?['id'],
      user?['idstr'],
      user?['uid'],
      body?['uid'],
    ]) {
      final uid = value?.toString().trim() ?? '';
      if (uid.isNotEmpty && uid != '0') return uid;
    }
    return '';
  }

  static bool desktopConfigShowsLoggedIn(dynamic value) {
    final body = _asMap(value);
    if (body == null || isDefinitiveDesktopLogoutPayload(body)) {
      return false;
    }
    final data = _asMap(body['data']);
    final user = _asMap(data?['user']) ?? _asMap(body['user']);
    final loginFlagPresent = (data != null &&
            (data.containsKey('islogin') || data.containsKey('login'))) ||
        body.containsKey('islogin') ||
        body.containsKey('login');
    final loggedIn = (data != null &&
            (_isTruthy(data['islogin']) || _isTruthy(data['login']))) ||
        _isTruthy(body['islogin']) ||
        _isTruthy(body['login']) ||
        (!loginFlagPresent && user != null);
    return loggedIn && desktopSessionUid(body).isNotEmpty;
  }

  static bool groupsPayloadMatchesUid(dynamic value, String expectedUid) {
    if (expectedUid.isEmpty) return false;
    final body = _asMap(value);
    final groups = body?['groups'];
    if (groups is! List) return false;
    for (final sectionValue in groups) {
      final section = _asMap(sectionValue);
      final entries = section?['group'];
      if (entries is! List) continue;
      for (final entryValue in entries) {
        final entry = _asMap(entryValue);
        final uid = entry?['uid']?.toString() ?? '';
        final gid = entry?['gid']?.toString() ?? '';
        if (uid == expectedUid ||
            (gid.length > expectedUid.length && gid.endsWith(expectedUid))) {
          return true;
        }
      }
    }
    return false;
  }

  void _loadFromStorage() {
    final isLoggedIn = _storage.isLoggedIn();
    final sub = _storage.getSubCookie();
    final subp = _storage.getSubpCookie();
    final storedFull = _storage.getFullCookie();
    final normalizedFull =
        storedFull == null ? '' : normalizeCookieHeader(storedFull);
    final full = normalizedFull.isNotEmpty ? normalizedFull : storedFull;
    final uid = _storage.getString(StorageService.keyUserUid);
    final nickname = _storage.getString(StorageService.keyUserNickname);
    final avatar = _storage.getString(StorageService.keyUserAvatar);

    if (storedFull != null && full != storedFull) {
      _storage.setFullCookie(full!);
    }
    state = AuthState(
      isLoggedIn: isLoggedIn,
      subCookie: sub,
      subpCookie: subp,
      fullCookie: full,
      uid: uid,
      nickname: nickname,
      avatar: avatar,
    );

    // If logged in but uid/avatar missing, refresh profile in background
    if (isLoggedIn &&
        (uid == null || uid.isEmpty || avatar == null || avatar.isEmpty)) {
      if (full != null && full.isNotEmpty) {
        setAndVerifyCookie(full);
      }
    }
  }

  /// Directly save authenticated session extracted from WebView JS context
  Future<void> saveDirectSession({
    required String uid,
    required String nickname,
    required String avatar,
    required String fullCookie,
  }) async {
    final normalizedCookie = normalizeCookieHeader(fullCookie);
    final effectiveCookie =
        normalizedCookie.isNotEmpty ? normalizedCookie : fullCookie.trim();
    String sub = '';
    String subp = '';

    final subMatch = RegExp(r'SUB=([^;]+)', caseSensitive: false)
        .firstMatch(effectiveCookie);
    if (subMatch != null) sub = subMatch.group(1)!.trim();

    final subpMatch = RegExp(r'SUBP=([^;]+)', caseSensitive: false)
        .firstMatch(effectiveCookie);
    if (subpMatch != null) subp = subpMatch.group(1)!.trim();

    await _storage.setLoggedIn(true);
    await _storage.setString(StorageService.keyUserUid, uid);
    await _storage.setString(StorageService.keyUserNickname, nickname);
    await _storage.setString(StorageService.keyUserAvatar, avatar);
    await _storage.setFullCookie(effectiveCookie);
    await _storage.setDesktopCookie(effectiveCookie);
    await _storage.setMobileCookie(effectiveCookie);
    await _storage.setCookieScopeSchemaVersion(
      StorageService.currentCookieScopeSchemaVersion,
    );
    if (sub.isNotEmpty) await _storage.setSubCookie(sub);
    if (subp.isNotEmpty) await _storage.setSubpCookie(subp);

    state = AuthState(
      isLoggedIn: true,
      uid: uid,
      nickname: nickname,
      avatar: avatar,
      fullCookie: effectiveCookie,
      subCookie: sub,
      subpCookie: subp,
      isValidating: false,
    );
  }

  /// Parse and set user cookie or token from raw string
  Future<bool> setAndVerifyCookie(
    String rawInput, {
    bool requireDesktopSession = false,
    CancelToken? cancelToken,
    Duration? verificationTimeout,
  }) async {
    state = state.copyWith(isValidating: true);
    final verificationCancelToken = cancelToken ?? CancelToken();
    if (_storage.getCookieScopeSchemaVersion() <
        StorageService.currentCookieScopeSchemaVersion) {
      // Manual import/profile refresh can run before the feed controller's
      // startup reconciliation. Remove only the old, derived scoped copies so
      // a mobile-only verification cannot preserve a poisoned desktop slot.
      await _storage.clearScopedCookiesForMigration();
      await _storage.setCookieScopeSchemaVersion(
        StorageService.currentCookieScopeSchemaVersion,
      );
    }
    final raw = rawInput.trim();
    final normalizedCookie = normalizeCookieHeader(raw);
    // A manually entered bare SUB token has no '=' separator and therefore
    // must remain intact instead of being normalized to an empty string.
    final cookieSource = normalizedCookie.isNotEmpty ? normalizedCookie : raw;

    String sub = '';
    String subp = '';

    final subMatch =
        RegExp(r'SUB=([^;]+)', caseSensitive: false).firstMatch(cookieSource);
    if (subMatch != null) {
      sub = subMatch.group(1)!.trim();
    } else if (cookieSource.startsWith('_2A')) {
      sub = cookieSource;
    }

    final subpMatch =
        RegExp(r'SUBP=([^;]+)', caseSensitive: false).firstMatch(cookieSource);
    if (subpMatch != null) {
      subp = subpMatch.group(1)!.trim();
    }

    if (sub.isEmpty &&
        !RegExp(r'SUB=', caseSensitive: false).hasMatch(cookieSource)) {
      state = state.copyWith(isValidating: false);
      return false;
    }

    final effectiveFullCookie =
        RegExp(r'SUB=', caseSensitive: false).hasMatch(cookieSource)
            ? cookieSource
            : 'SUB=$sub; ${subp.isNotEmpty ? "SUBP=$subp;" : ""}';

    String xsrfToken = '';
    final xsrfMatch = RegExp(r'XSRF-TOKEN=([^;]+)', caseSensitive: false)
        .firstMatch(effectiveFullCookie);
    if (xsrfMatch != null) xsrfToken = xsrfMatch.group(1)!.trim();

    // Temporary in-memory verification without premature storage mutation
    String resolvedUid = '';
    String resolvedNickname = '';
    String resolvedAvatar = '';
    bool desktopSessionVerified = false;
    bool mobileSessionVerified = false;
    final verificationTimeoutTimer = verificationTimeout == null
        ? null
        : Timer(
            verificationTimeout,
            () => verificationCancelToken.cancel(
              'Login credential verification timed out',
            ),
          );

    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: ApiConstants.baseUrl,
          connectTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: {
            'User-Agent': ApiConstants.defaultUserAgent,
            'Cookie': effectiveFullCookie,
            'Referer': 'https://weibo.com/',
            'Accept': 'application/json, text/plain, */*',
            'X-Requested-With': 'XMLHttpRequest',
            if (xsrfToken.isNotEmpty) 'X-XSRF-TOKEN': xsrfToken,
          },
        ),
      );

      // 1. Primary: Try /ajax/config/getconfig
      try {
        final configRes = await dio.get(
          '/ajax/config/getconfig',
          cancelToken: verificationCancelToken,
        );
        if (desktopConfigShowsLoggedIn(configRes.data)) {
          final body = _asMap(configRes.data);
          final configData = _asMap(body?['data']);
          final userObj = _asMap(configData?['user']) ?? _asMap(body?['user']);
          desktopSessionVerified = true;
          resolvedUid = desktopSessionUid(configRes.data);
          resolvedNickname = userObj?['screen_name']?.toString() ?? '';
          resolvedAvatar = userObj?['avatar_large']?.toString() ??
              userObj?['avatar_hd']?.toString() ??
              userObj?['profile_image_url']?.toString() ??
              '';
        }
      } catch (_) {}

      // 1.5. Desktop fallback: Try /ajax/statuses/config if getconfig was incomplete
      if (!desktopSessionVerified) {
        try {
          final statusConfigRes = await dio.get(
            '/ajax/statuses/config',
            cancelToken: verificationCancelToken,
          );
          if (desktopConfigShowsLoggedIn(statusConfigRes.data)) {
            final body = _asMap(statusConfigRes.data);
            final configData = _asMap(body?['data']);
            final userObj =
                _asMap(configData?['user']) ?? _asMap(body?['user']);
            desktopSessionVerified = true;
            resolvedUid = desktopSessionUid(statusConfigRes.data);
            if (resolvedNickname.isEmpty) {
              resolvedNickname = userObj?['screen_name']?.toString() ?? '';
            }
            if (resolvedAvatar.isEmpty) {
              resolvedAvatar = userObj?['avatar_large']?.toString() ??
                  userObj?['avatar_hd']?.toString() ??
                  userObj?['profile_image_url']?.toString() ??
                  '';
            }
          }
        } catch (_) {}
      }

      // 2. Secondary: Try https://m.weibo.cn/api/config
      if (resolvedUid.isEmpty || resolvedNickname.isEmpty) {
        try {
          final mConfigRes = await dio.get(
            'https://m.weibo.cn/api/config',
              options: Options(
                headers: {
                'Referer': 'https://m.weibo.cn/',
                'User-Agent':
                    'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
                'Accept': 'application/json, text/plain, */*',
                'X-Requested-With': 'XMLHttpRequest',
                },
              ),
              cancelToken: verificationCancelToken,
          );
          if (mConfigRes.data is Map<String, dynamic> &&
              mConfigRes.data['data'] != null) {
            final mData = mConfigRes.data['data'] as Map<String, dynamic>;
            final mUser = mData['user'] as Map<String, dynamic>?;
            final mUid =
                mData['uid']?.toString() ?? mUser?['id']?.toString() ?? '';
            if (_isTruthy(mData['login']) && mUid.isNotEmpty) {
              mobileSessionVerified = true;
              if (resolvedUid.isEmpty) resolvedUid = mUid;
              if (resolvedNickname.isEmpty) {
                resolvedNickname = mUser?['screen_name']?.toString() ?? '';
              }
              if (resolvedAvatar.isEmpty) {
                resolvedAvatar = mUser?['profile_image_url']?.toString() ?? '';
              }
            }
          }
        } catch (_) {}
      }

      // 3. Tertiary: Try from /ajax/profile/detail
      if (resolvedUid.isEmpty) {
        try {
          final detailRes = await dio.get(
            '/ajax/profile/detail',
            cancelToken: verificationCancelToken,
          );
          if (detailRes.data is Map<String, dynamic> &&
              detailRes.data['data'] != null) {
            final data = _asMap(detailRes.data['data']);
            final verifiedUrl = data?['verified_url']?.toString() ?? '';
            final uidMatch = RegExp(r'uid=(\d+)').firstMatch(verifiedUrl);
            final uid = uidMatch?.group(1) ??
                data?['uid']?.toString() ??
                data?['id']?.toString() ??
                '';
            if (uid.isNotEmpty && uid != '0') {
              resolvedUid = uid;
              desktopSessionVerified = true;
            }
          }
        } catch (_) {}
      }

      // 4. Quaternary: Try from /ajax/feed/allGroups
      if (resolvedUid.isEmpty) {
        try {
          final groupsRes = await dio.get(
            '/ajax/feed/allGroups',
            cancelToken: verificationCancelToken,
          );
          if (groupsRes.data is Map<String, dynamic>) {
            final rawGroups = groupsRes.data['groups'] as List? ?? [];
            for (final item in rawGroups) {
              if (item is Map<String, dynamic> && item['group'] is List) {
                for (final g in item['group']) {
                  final gid = g['gid']?.toString() ?? '';
                  if (gid.startsWith('11000') && gid.length > 5) {
                    resolvedUid = gid.substring(5);
                    desktopSessionVerified = true;
                    break;
                  }
                }
              }
            }
          }
        } catch (_) {}
      }

      // 5. If UID resolved, ensure profile details are queried
      if (resolvedUid.isNotEmpty &&
          (resolvedNickname.isEmpty || resolvedAvatar.isEmpty)) {
        try {
          final infoRes = await dio.get(
            '/ajax/profile/info',
            queryParameters: {'uid': resolvedUid},
            cancelToken: verificationCancelToken,
          );
          if (infoRes.data is Map<String, dynamic> &&
              infoRes.data['data'] != null) {
            final userData = infoRes.data['data']['user'];
            if (userData is Map<String, dynamic>) {
              if (resolvedNickname.isEmpty) {
                resolvedNickname =
                    userData['screen_name']?.toString() ?? '微博用户';
              }
              if (resolvedAvatar.isEmpty) {
                resolvedAvatar = userData['avatar_large']?.toString() ??
                    userData['profile_image_url']?.toString() ??
                    '';
              }
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    // Stop the deadline before the short local persistence phase. A timed-out
    // network verification must never leave a request running that can commit
    // an unexpected late session.
    verificationTimeoutTimer?.cancel();
    // A verification timeout cancels the actual Dio requests. Do not let a
    // late response from an abandoned verification commit a session afterwards.
    if (verificationCancelToken.isCancelled) {
      state = state.copyWith(isValidating: false);
      return false;
    }

    // Commit only after one of the supported desktop/mobile verification paths
    // confirms the session. Mobile WebView login may complete before desktop
    // SSO catches up; the feed controller reconciles desktop cookies later.
    if (canCommitVerifiedSession(
      uid: resolvedUid,
      desktopSessionVerified: desktopSessionVerified,
      mobileSessionVerified: mobileSessionVerified,
      requireDesktopSession: requireDesktopSession,
    )) {
      await _storage.setFullCookie(effectiveFullCookie);
      if (desktopSessionVerified) {
        await _storage.setDesktopCookie(effectiveFullCookie);
      } else {
        // Never retain a desktop cookie from another/older account while a
        // newly verified mobile session is waiting for SSO synchronization.
        await _storage.clearDesktopCookie();
      }
      if (mobileSessionVerified) {
        await _storage.setMobileCookie(effectiveFullCookie);
      }
      await _storage.setCookieScopeSchemaVersion(
        StorageService.currentCookieScopeSchemaVersion,
      );
      if (sub.isNotEmpty) await _storage.setSubCookie(sub);
      if (subp.isNotEmpty) await _storage.setSubpCookie(subp);
      await _storage.setAccessToken('');
      await _storage.setString(StorageService.keyUserUid, resolvedUid);
      await _storage.setString(
        StorageService.keyUserNickname,
        resolvedNickname.isNotEmpty ? resolvedNickname : '微博用户',
      );
      if (resolvedAvatar.isNotEmpty) {
        await _storage.setString(StorageService.keyUserAvatar, resolvedAvatar);
      }
      await _storage.setLoggedIn(true);

      state = AuthState(
        isLoggedIn: true,
        subCookie: sub,
        subpCookie: subp,
        fullCookie: effectiveFullCookie,
        uid: resolvedUid,
        nickname: resolvedNickname.isNotEmpty ? resolvedNickname : '微博用户',
        avatar: resolvedAvatar.isNotEmpty ? resolvedAvatar : null,
        isValidating: false,
        isCookieExpired: false,
        cookieValidationStatus: desktopSessionVerified
            ? CookieValidationStatus.valid
            : CookieValidationStatus.needsDesktopSync,
      );
      return true;
    }

    // Verification completely failed -> Do NOT mutate storage or claim login
    state = state.copyWith(isValidating: false);
    return false;
  }

  /// Reconcile the persisted session with WebView's host-scoped cookies.
  ///
  /// Weibo's mobile and desktop SSO cookies can be temporarily different.
  /// The old bridge flattened cookies from both hosts into one arbitrary
  /// order, so an otherwise valid mobile session could be sent to the desktop
  /// following-feed endpoint. This method prefers the desktop cookie for
  /// desktop requests and only adopts a changed native session after the
  /// desktop config endpoint confirms the same account.
  Future<bool> reconcileNativeSession({bool force = false}) async {
    final running = _nativeSyncFuture;
    if (running != null) return running;

    final future = _reconcileNativeSession(force: force);
    _nativeSyncFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_nativeSyncFuture, future)) _nativeSyncFuture = null;
    }
  }

  Future<bool> _reconcileNativeSession({required bool force}) async {
    if (!_storage.isLoggedIn() && !state.isLoggedIn) return false;

    try {
      final needsScopeMigration = _storage.getCookieScopeSchemaVersion() <
          StorageService.currentCookieScopeSchemaVersion;
      if (needsScopeMigration) {
        // Versions before schema 2 copied one legacy, cross-domain Cookie
        // header into both scoped slots. Preserve the original full Cookie,
        // but discard those unverified derivatives so they cannot permanently
        // shadow a valid candidate after an app update.
        await _storage.clearScopedCookiesForMigration();
      }

      final raw = await _cookieChannel.invokeMethod<dynamic>(
        'getNativeCookiesByDomain',
      );

      final scoped = <String, String>{};
      if (raw is Map) {
        for (final entry in raw.entries) {
          final value = entry.value?.toString() ?? '';
          if (value.isNotEmpty) scoped[entry.key.toString()] = value;
        }
      }

      final nativeDesktop = normalizeCookieHeader(scoped['desktop'] ?? '');
      final nativeMobile = normalizeCookieHeader(scoped['mobile'] ?? '');
      final storedFull = normalizeCookieHeader(_storage.getFullCookie() ?? '');
      final storedDesktop =
          normalizeCookieHeader(_storage.getDesktopCookie() ?? '');
      final storedMobile =
          normalizeCookieHeader(_storage.getMobileCookie() ?? '');
      final expectedUid =
          _storage.getString(StorageService.keyUserUid) ?? state.uid ?? '';
      final candidates = <String>[];
      for (final candidate in [nativeDesktop, storedDesktop, storedFull]) {
        if (candidate.isEmpty ||
            _cookieValue(candidate, 'SUB').isEmpty ||
            candidates.contains(candidate)) {
          continue;
        }
        candidates.add(candidate);
      }

      String candidateDesktop = '';
      for (final candidate in candidates) {
        final canReuseVerifiedStoredCookie = !force &&
            !needsScopeMigration &&
            storedDesktop.isNotEmpty &&
            candidate == storedDesktop;
        if (canReuseVerifiedStoredCookie ||
            await _verifyDesktopCookie(candidate, expectedUid)) {
          candidateDesktop = candidate;
          break;
        }
      }

      if (candidateDesktop.isEmpty) {
        if (needsScopeMigration) {
          await _storage.setCookieScopeSchemaVersion(
            StorageService.currentCookieScopeSchemaVersion,
          );
        }
        return false;
      }

      final candidateSub = _cookieValue(candidateDesktop, 'SUB');
      final effectiveMobile = nativeMobile.isNotEmpty
          ? nativeMobile
          : (storedMobile.isNotEmpty ? storedMobile : storedFull);
      final merged = normalizeCookieHeader(
        [candidateDesktop, effectiveMobile, storedFull]
            .where((item) => item.isNotEmpty)
            .join('; '),
      );
      if (merged.isEmpty) return false;

      final candidateSubp = _cookieValue(candidateDesktop, 'SUBP');
      await _storage.setFullCookie(merged);
      await _storage.setDesktopCookie(candidateDesktop);
      if (effectiveMobile.isNotEmpty) {
        await _storage.setMobileCookie(effectiveMobile);
      }
      if (candidateSub.isNotEmpty) await _storage.setSubCookie(candidateSub);
      if (candidateSubp.isNotEmpty) {
        await _storage.setSubpCookie(candidateSubp);
      }
      await _storage.setCookieScopeSchemaVersion(
        StorageService.currentCookieScopeSchemaVersion,
      );

      state = state.copyWith(
        fullCookie: merged,
        subCookie: candidateSub.isNotEmpty ? candidateSub : state.subCookie,
        subpCookie: candidateSubp.isNotEmpty ? candidateSubp : state.subpCookie,
        isCookieExpired: false,
      );
      // A true result means that an account-matching desktop session was
      // verified, regardless of whether persistence needed to change.
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _verifyDesktopCookie(String cookie, String expectedUid) async {
    final verifier = _desktopCookieVerifier;
    if (verifier != null) return verifier(cookie, expectedUid);

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      try {
        final response = await dio.get(
          '${ApiConstants.baseUrl}/ajax/config/getconfig',
          options: Options(
            headers: {
              'Cookie': cookie,
              'Referer': 'https://weibo.com/',
              'User-Agent': ApiConstants.defaultUserAgent,
              'Accept': 'application/json, text/plain, */*',
              'X-Requested-With': 'XMLHttpRequest',
            },
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        if (response.statusCode == 200) {
          final uid = desktopSessionUid(response.data);
          if (desktopConfigShowsLoggedIn(response.data) &&
              (expectedUid.isEmpty || uid == expectedUid)) {
            return true;
          }
          if (isDefinitiveDesktopLogoutPayload(response.data)) return false;
        }
      } catch (_) {
        // Continue with the independently authenticated groups endpoint.
      }

      // getconfig occasionally returns an incomplete shape even though the
      // authenticated desktop session still works. allGroups is also an
      // official account-scoped endpoint. The public/visitor response contains
      // another account's default groups, so only accept it when an embedded
      // uid exactly matches the already stored account uid.
      if (expectedUid.isEmpty) return false;
      final groupsResponse = await dio.get(
        '${ApiConstants.baseUrl}/ajax/feed/allGroups',
        options: Options(
          headers: {
            'Cookie': cookie,
            'Referer': 'https://weibo.com/',
            'User-Agent': ApiConstants.defaultUserAgent,
            'Accept': 'application/json, text/plain, */*',
            'X-Requested-With': 'XMLHttpRequest',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return groupsResponse.statusCode == 200 &&
          groupsPayloadMatchesUid(groupsResponse.data, expectedUid);
    } catch (_) {
      return false;
    }
  }

  static String _cookieValue(String cookie, String name) {
    if (cookie.isEmpty) return '';
    final match = RegExp(
      '(?:^|;)\\s*${RegExp.escape(name)}=([^;]*)',
      caseSensitive: false,
    ).firstMatch(cookie);
    return match?.group(1)?.trim() ?? '';
  }

  void notifyCookieExpired() {
    if (state.isLoggedIn && !state.isCookieExpired) {
      state = state.copyWith(
        isCookieExpired: true,
        cookieValidationStatus: CookieValidationStatus.expired,
      );
    }
  }

  /// Check current user cookie validity via official session verification APIs
  Future<bool> checkCookieValidity({bool silent = false}) async {
    final isLoggedIn = _storage.isLoggedIn();
    if (!isLoggedIn) {
      state = state.copyWith(
        isCookieExpired: false,
        isValidating: false,
        cookieValidationStatus: CookieValidationStatus.unavailable,
      );
      return false;
    }

    state = state.copyWith(
      isCookieExpired: false,
      isValidating: !silent,
      cookieValidationStatus: CookieValidationStatus.idle,
    );

    // Refresh the host-scoped snapshot first. This prevents a stale merged
    // Cookie header from making the validity check disagree with the desktop
    // timeline request after an SSO/WebView refresh.
    final desktopSessionVerified = await reconcileNativeSession(force: true);
    if (desktopSessionVerified) {
      state = state.copyWith(
        isLoggedIn: true,
        isCookieExpired: false,
        isValidating: false,
        cookieValidationStatus: CookieValidationStatus.valid,
      );
      return true;
    }

    final storedFullCookie = _storage.getFullCookie();
    final storedDesktopCookie = _storage.getDesktopCookie();
    final storedMobileCookie = _storage.getMobileCookie();
    final normalizedFullCookie = normalizeCookieHeader(storedFullCookie ?? '');
    final normalizedDesktopCookie =
        normalizeCookieHeader(storedDesktopCookie ?? '');
    final normalizedMobileCookie =
        normalizeCookieHeader(storedMobileCookie ?? '');
    final fullCookie = normalizedFullCookie.isNotEmpty
        ? normalizedFullCookie
        : normalizeCookieHeader(
            [normalizedDesktopCookie, normalizedMobileCookie]
                .where((cookie) => cookie.isNotEmpty)
                .join('; '),
          );
    final desktopCookie = normalizedDesktopCookie.isNotEmpty
        ? normalizedDesktopCookie
        : fullCookie;
    final mobileCookie =
        normalizedMobileCookie.isNotEmpty ? normalizedMobileCookie : fullCookie;

    if (fullCookie.isEmpty) {
      state = state.copyWith(
        isCookieExpired: false,
        isValidating: false,
        cookieValidationStatus: CookieValidationStatus.unavailable,
      );
      return false;
    }

    state = state.copyWith(
      fullCookie: fullCookie,
      isCookieExpired: false,
      isValidating: !silent,
      cookieValidationStatus: CookieValidationStatus.idle,
    );

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      bool desktopSessionValid = false;
      bool mobileSessionObserved = false;
      bool sawDefinitiveInvalidResponse = false;
      String? resolvedUid;
      String? resolvedName;
      String? resolvedAvatar;

      // Tier 1: Desktop Config Check. This is the only authoritative login
      // signal because the app's following timeline is a weibo.com endpoint.
      try {
        final configRes = await dio.get(
          'https://weibo.com/ajax/config/getconfig',
          options: Options(
            headers: {
              'Cookie': desktopCookie,
              'Referer': 'https://weibo.com/',
              'User-Agent': ApiConstants.defaultUserAgent,
              'Accept': 'application/json, text/plain, */*',
              'X-Requested-With': 'XMLHttpRequest',
            },
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        if (configRes.statusCode == 200 &&
            configRes.data is Map<String, dynamic>) {
          final body = _asMap(configRes.data);
          final data = _asMap(body?['data']);
          if (isDefinitiveDesktopLogoutPayload(body)) {
            sawDefinitiveInvalidResponse = true;
          }
          if (data != null) {
            final user = _asMap(data['user']);
            final loginFlagPresent =
                data.containsKey('islogin') || data.containsKey('login');
            final loggedIn = _isTruthy(data['islogin']) ||
                _isTruthy(data['login']) ||
                (!loginFlagPresent && user != null);
            if (loginFlagPresent && !loggedIn) {
              sawDefinitiveInvalidResponse = true;
            }
            final uid = desktopSessionUid(body);
            if (loggedIn && uid.isNotEmpty) {
              desktopSessionValid = true;
              resolvedUid = uid;
              resolvedName = user?['screen_name']?.toString();
              resolvedAvatar = user?['avatar_large']?.toString() ??
                  user?['avatar_hd']?.toString() ??
                  user?['profile_image_url']?.toString();
            }
          }
        }
      } catch (_) {}

      // Tier 2: Mobile Config Check. It is useful for filling profile data and
      // diagnosing an SSO race, but it must not by itself declare the desktop
      // following session valid.
      if (!desktopSessionValid) {
        try {
          final mRes = await dio.get(
            'https://m.weibo.cn/api/config',
            options: Options(
              headers: {
                'Cookie': mobileCookie,
                'Referer': 'https://m.weibo.cn/',
                'User-Agent':
                    'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
                'Accept': 'application/json, text/plain, */*',
                'X-Requested-With': 'XMLHttpRequest',
              },
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          if (mRes.statusCode == 200 && mRes.data is Map<String, dynamic>) {
            final mData = _asMap(mRes.data['data']);
            if (mData != null) {
              final mUser = _asMap(mData['user']);
              final mLogin = _isTruthy(mData['login']);
              final mUid = mData['uid']?.toString() ??
                  mUser?['id']?.toString() ??
                  mUser?['idstr']?.toString() ??
                  '';
              if (mLogin && mUid.isNotEmpty) {
                mobileSessionObserved = true;
                resolvedUid ??= mUid;
                resolvedName ??= mUser?['screen_name']?.toString();
                resolvedAvatar ??= mUser?['profile_image_url']?.toString();
              }
            }
          }
        } catch (_) {}
      }

      // Only enrich an already verified desktop session. A public profile
      // response is not evidence that the Cookie can access the feed.
      if (desktopSessionValid &&
          resolvedUid != null &&
          (resolvedName == null || resolvedAvatar == null)) {
        try {
          final pRes = await dio.get(
            'https://weibo.com/ajax/profile/info',
            queryParameters: {'uid': resolvedUid},
            options: Options(
              headers: {
                'Cookie': desktopCookie,
                'Referer': 'https://weibo.com/u/$resolvedUid',
                'User-Agent': ApiConstants.defaultUserAgent,
                'Accept': 'application/json, text/plain, */*',
              },
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          if (pRes.statusCode == 200 && pRes.data is Map<String, dynamic>) {
            final user = pRes.data['data']?['user'] as Map<String, dynamic>?;
            if (user != null && user['id']?.toString() == resolvedUid) {
              resolvedName ??= user['screen_name']?.toString();
              resolvedAvatar ??= user['avatar_large']?.toString() ??
                  user['avatar_hd']?.toString() ??
                  user['profile_image_url']?.toString();
            }
          }
        } catch (_) {}
      }

      if (desktopSessionValid &&
          resolvedUid != null &&
          resolvedUid.isNotEmpty) {
        await _storage.setString(StorageService.keyUserUid, resolvedUid);
        if (resolvedName != null && resolvedName.isNotEmpty) {
          await _storage.setString(
              StorageService.keyUserNickname, resolvedName);
        }
        if (resolvedAvatar != null && resolvedAvatar.isNotEmpty) {
          await _storage.setString(
              StorageService.keyUserAvatar, resolvedAvatar);
        }

        state = state.copyWith(
          isLoggedIn: true,
          isCookieExpired: false,
          isValidating: false,
          cookieValidationStatus: CookieValidationStatus.valid,
          uid: resolvedUid,
          nickname: resolvedName ?? state.nickname,
          avatar: resolvedAvatar ?? state.avatar,
        );
        return true;
      } else {
        // A valid mobile session while the desktop endpoint is unavailable is
        // a recoverable synchronization state, not proof that the Cookie has
        // expired. Keep the account logged in and let the next feed refresh
        // reconcile the native jars again.
        if (mobileSessionObserved) {
          state = state.copyWith(
            isCookieExpired: false,
            isValidating: false,
            cookieValidationStatus: CookieValidationStatus.needsDesktopSync,
          );
          return false;
        }

        // A timeout, DNS failure, proxy error, or an undocumented response
        // shape is not evidence that the account has expired. Keep the
        // existing session state and let the user retry later.
        if (!sawDefinitiveInvalidResponse) {
          state = state.copyWith(
            isCookieExpired: false,
            isValidating: false,
            cookieValidationStatus: CookieValidationStatus.unavailable,
          );
          return false;
        }
        state = state.copyWith(
          isCookieExpired: true,
          isValidating: false,
          cookieValidationStatus: CookieValidationStatus.expired,
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isValidating: false,
        cookieValidationStatus: CookieValidationStatus.unavailable,
      );
      return false;
    }
  }

  Future<void> refreshUserProfile() async {
    final fullCookie = _storage.getFullCookie();
    if (fullCookie != null && fullCookie.isNotEmpty) {
      await setAndVerifyCookie(fullCookie);
    }
  }

  Future<void> logout() async {
    await _storage.clearAuth();
    try {
      await const MethodChannel('com.sharelite/cookies')
          .invokeMethod('clearNativeCookies');
      await WebViewCookieManager().clearCookies();
    } catch (_) {}
    state = const AuthState(isLoggedIn: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return AuthNotifier(storage);
});
