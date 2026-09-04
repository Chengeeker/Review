import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../constants/api_constants.dart';
import '../storage/storage_service.dart';

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
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final StorageService _storage;

  AuthNotifier(this._storage) : super(const AuthState()) {
    _loadFromStorage();
  }

  void _loadFromStorage() {
    final isLoggedIn = _storage.isLoggedIn();
    final sub = _storage.getSubCookie();
    final subp = _storage.getSubpCookie();
    final full = _storage.getFullCookie();
    final uid = _storage.getString(StorageService.keyUserUid);
    final nickname = _storage.getString(StorageService.keyUserNickname);
    final avatar = _storage.getString(StorageService.keyUserAvatar);

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
    if (isLoggedIn && (uid == null || uid.isEmpty || avatar == null || avatar.isEmpty)) {
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
    String sub = '';
    String subp = '';

    final subMatch = RegExp(r'SUB=([^;]+)').firstMatch(fullCookie);
    if (subMatch != null) sub = subMatch.group(1)!.trim();

    final subpMatch = RegExp(r'SUBP=([^;]+)').firstMatch(fullCookie);
    if (subpMatch != null) subp = subpMatch.group(1)!.trim();

    await _storage.setLoggedIn(true);
    await _storage.setString(StorageService.keyUserUid, uid);
    await _storage.setString(StorageService.keyUserNickname, nickname);
    await _storage.setString(StorageService.keyUserAvatar, avatar);
    await _storage.setFullCookie(fullCookie);
    if (sub.isNotEmpty) await _storage.setSubCookie(sub);
    if (subp.isNotEmpty) await _storage.setSubpCookie(subp);

    state = AuthState(
      isLoggedIn: true,
      uid: uid,
      nickname: nickname,
      avatar: avatar,
      fullCookie: fullCookie,
      subCookie: sub,
      subpCookie: subp,
      isValidating: false,
    );
  }

  /// Parse and set user cookie or token from raw string
  Future<bool> setAndVerifyCookie(String rawInput) async {
    state = state.copyWith(isValidating: true);
    final raw = rawInput.trim();

    String sub = '';
    String subp = '';

    final subMatch = RegExp(r'SUB=([^;]+)').firstMatch(raw);
    if (subMatch != null) {
      sub = subMatch.group(1)!.trim();
    } else if (raw.startsWith('_2A')) {
      sub = raw;
    }

    final subpMatch = RegExp(r'SUBP=([^;]+)').firstMatch(raw);
    if (subpMatch != null) {
      subp = subpMatch.group(1)!.trim();
    }

    if (sub.isEmpty && !raw.contains('SUB=')) {
      state = state.copyWith(isValidating: false);
      return false;
    }

    final effectiveFullCookie = raw.contains('SUB=')
        ? raw
        : 'SUB=$sub; ${subp.isNotEmpty ? "SUBP=$subp;" : ""}';

    String xsrfToken = '';
    final xsrfMatch = RegExp(r'XSRF-TOKEN=([^;]+)').firstMatch(effectiveFullCookie);
    if (xsrfMatch != null) xsrfToken = xsrfMatch.group(1)!.trim();

    // Temporary in-memory verification without premature storage mutation
    String resolvedUid = '';
    String resolvedNickname = '';
    String resolvedAvatar = '';

    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: ApiConstants.baseUrl,
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
        final configRes = await dio.get('/ajax/config/getconfig');
        if (configRes.data is Map<String, dynamic> && configRes.data['data'] != null) {
          final configData = configRes.data['data'] as Map<String, dynamic>;
          final uidFromConfig = configData['uid']?.toString() ?? '';
          final userObj = configData['user'] as Map<String, dynamic>?;
          if (userObj != null) {
            resolvedUid = userObj['id']?.toString() ?? uidFromConfig;
            resolvedNickname = userObj['screen_name']?.toString() ?? '';
            resolvedAvatar = userObj['avatar_large']?.toString() ??
                userObj['avatar_hd']?.toString() ??
                userObj['profile_image_url']?.toString() ??
                '';
          } else if (uidFromConfig.isNotEmpty) {
            resolvedUid = uidFromConfig;
          }
        }
      } catch (_) {}

      // 2. Secondary: Try https://m.weibo.cn/api/config
      if (resolvedUid.isEmpty || resolvedNickname.isEmpty) {
        try {
          final mConfigRes = await dio.get('https://m.weibo.cn/api/config');
          if (mConfigRes.data is Map<String, dynamic> && mConfigRes.data['data'] != null) {
            final mData = mConfigRes.data['data'] as Map<String, dynamic>;
            final mUser = mData['user'] as Map<String, dynamic>?;
            final mUid = mData['uid']?.toString() ?? mUser?['id']?.toString() ?? '';
            if (mUid.isNotEmpty) {
              resolvedUid = mUid;
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
          final detailRes = await dio.get('/ajax/profile/detail');
          if (detailRes.data is Map<String, dynamic> && detailRes.data['data'] != null) {
            final verifiedUrl = detailRes.data['data']['verified_url']?.toString() ?? '';
            final uidMatch = RegExp(r'uid=(\d+)').firstMatch(verifiedUrl);
            if (uidMatch != null) {
              resolvedUid = uidMatch.group(1)!;
            }
          }
        } catch (_) {}
      }

      // 4. Quaternary: Try from /ajax/feed/allGroups
      if (resolvedUid.isEmpty) {
        try {
          final groupsRes = await dio.get('/ajax/feed/allGroups');
          if (groupsRes.data is Map<String, dynamic>) {
            final rawGroups = groupsRes.data['groups'] as List? ?? [];
            for (final item in rawGroups) {
              if (item is Map<String, dynamic> && item['group'] is List) {
                for (final g in item['group']) {
                  final gid = g['gid']?.toString() ?? '';
                  if (gid.startsWith('11000') && gid.length > 5) {
                    resolvedUid = gid.substring(5);
                    break;
                  }
                }
              }
            }
          }
        } catch (_) {}
      }

      // 5. If UID resolved, ensure profile details are queried
      if (resolvedUid.isNotEmpty && (resolvedNickname.isEmpty || resolvedAvatar.isEmpty)) {
        try {
          final infoRes = await dio.get('/ajax/profile/info', queryParameters: {'uid': resolvedUid});
          if (infoRes.data is Map<String, dynamic> && infoRes.data['data'] != null) {
            final userData = infoRes.data['data']['user'];
            if (userData is Map<String, dynamic>) {
              if (resolvedNickname.isEmpty) {
                resolvedNickname = userData['screen_name']?.toString() ?? '微博用户';
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

    // Atomic commit ONLY if verification resolved a genuine UID
    if (resolvedUid.isNotEmpty) {
      await _storage.setFullCookie(effectiveFullCookie);
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
      );
      return true;
    }

    // Verification completely failed -> Do NOT mutate storage or claim login
    state = state.copyWith(isValidating: false);
    return false;
  }

  void notifyCookieExpired() {
    if (state.isLoggedIn && !state.isCookieExpired) {
      state = state.copyWith(isCookieExpired: true);
    }
  }

  /// Check current user cookie validity via official session verification APIs
  Future<bool> checkCookieValidity({bool silent = false}) async {
    final fullCookie = _storage.getFullCookie();
    final isLoggedIn = _storage.isLoggedIn();
    final savedUid = _storage.getString(StorageService.keyUserUid) ?? state.uid ?? '';

    if (!isLoggedIn || fullCookie == null || fullCookie.isEmpty) {
      if (!silent) {
        state = state.copyWith(isCookieExpired: false, isValidating: false);
      }
      return false;
    }

    if (!silent) {
      state = state.copyWith(isValidating: true);
    }

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      bool isValid = false;
      String? resolvedUid;
      String? resolvedName;
      String? resolvedAvatar;

      // Tier 1: Mobile API Config Check (m.weibo.cn) - Primary for SMS/Mobile login sessions
      try {
        final mRes = await dio.get(
          'https://m.weibo.cn/api/config',
          options: Options(
            headers: {
              'Cookie': fullCookie,
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
          final mData = mRes.data['data'] as Map<String, dynamic>?;
          if (mData != null) {
            final mLogin = mData['login'] == true;
            final mUid = mData['uid']?.toString() ?? mData['user']?['id']?.toString() ?? '';
            if (mLogin && mUid.isNotEmpty) {
              isValid = true;
              resolvedUid = mUid;
              resolvedName = mData['user']?['screen_name']?.toString();
              resolvedAvatar = mData['user']?['profile_image_url']?.toString();
            }
          }
        }
      } catch (_) {}

      // Tier 2: Friends Timeline Accessibility Check (unreadfriendstimeline)
      if (!isValid) {
        try {
          final fRes = await dio.get(
            'https://weibo.com/ajax/feed/unreadfriendstimeline',
            options: Options(
              headers: {
                'Cookie': fullCookie,
                'Referer': 'https://weibo.com/',
                'User-Agent': ApiConstants.defaultUserAgent,
                'Accept': 'application/json, text/plain, */*',
                'X-Requested-With': 'XMLHttpRequest',
              },
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          if (fRes.statusCode == 200 && fRes.data is Map<String, dynamic>) {
            final ok = fRes.data['ok'];
            if (ok != -100 && ok != 0) {
              isValid = true;
            }
          }
        } catch (_) {}
      }

      // Tier 3: Desktop Config Check (/ajax/config/getconfig)
      if (!isValid) {
        try {
          final configRes = await dio.get(
            'https://weibo.com/ajax/config/getconfig',
            options: Options(
              headers: {
                'Cookie': fullCookie,
                'Referer': 'https://weibo.com/',
                'User-Agent': ApiConstants.defaultUserAgent,
                'Accept': 'application/json, text/plain, */*',
                'X-Requested-With': 'XMLHttpRequest',
              },
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          if (configRes.statusCode == 200 && configRes.data is Map<String, dynamic>) {
            final data = configRes.data['data'] as Map<String, dynamic>?;
            if (data != null) {
              final isLogin = data['islogin'] == 1 || data['islogin'] == true;
              final uid = data['uid']?.toString() ?? '';
              final user = data['user'] as Map<String, dynamic>?;
              if (isLogin && (uid.isNotEmpty || user != null)) {
                isValid = true;
                resolvedUid = user?['id']?.toString() ?? uid;
                resolvedName = user?['screen_name']?.toString();
                resolvedAvatar = user?['avatar_large']?.toString() ??
                    user?['avatar_hd']?.toString() ??
                    user?['profile_image_url']?.toString();
              }
            }
          }
        } catch (_) {}
      }

      // Tier 4: User Profile Verification if UID is available
      if (!isValid && savedUid.isNotEmpty) {
        try {
          final pRes = await dio.get(
            'https://weibo.com/ajax/profile/info',
            queryParameters: {'uid': savedUid},
            options: Options(
              headers: {
                'Cookie': fullCookie,
                'Referer': 'https://weibo.com/u/$savedUid',
                'User-Agent': ApiConstants.defaultUserAgent,
                'Accept': 'application/json, text/plain, */*',
              },
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          if (pRes.statusCode == 200 && pRes.data is Map<String, dynamic>) {
            final user = pRes.data['data']?['user'] as Map<String, dynamic>?;
            if (user != null && user['id']?.toString() == savedUid) {
              isValid = true;
              resolvedUid = savedUid;
              resolvedName = user['screen_name']?.toString();
              resolvedAvatar = user['avatar_large']?.toString() ??
                  user['avatar_hd']?.toString() ??
                  user['profile_image_url']?.toString();
            }
          }
        } catch (_) {}
      }

      if (isValid) {
        if (resolvedUid != null && resolvedUid.isNotEmpty) {
          await _storage.setString(StorageService.keyUserUid, resolvedUid);
        }
        if (resolvedName != null && resolvedName.isNotEmpty) {
          await _storage.setString(StorageService.keyUserNickname, resolvedName);
        }
        if (resolvedAvatar != null && resolvedAvatar.isNotEmpty) {
          await _storage.setString(StorageService.keyUserAvatar, resolvedAvatar);
        }

        state = state.copyWith(
          isLoggedIn: true,
          isCookieExpired: false,
          isValidating: false,
          uid: resolvedUid ?? state.uid,
          nickname: resolvedName ?? state.nickname,
          avatar: resolvedAvatar ?? state.avatar,
        );
        return true;
      } else {
        state = state.copyWith(
          isCookieExpired: true,
          isValidating: false,
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(isValidating: false);
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
      await const MethodChannel('com.sharelite/cookies').invokeMethod('clearNativeCookies');
      await WebViewCookieManager().clearCookies();
    } catch (_) {}
    state = const AuthState(isLoggedIn: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return AuthNotifier(storage);
});
