import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:review/core/auth/auth_provider.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/auth/presentation/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const cookieChannel = MethodChannel('com.sharelite/cookies');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cookieChannel, null);
  });

  group('auth session handling', () {
    test('normalizes duplicate WebView cookie names', () {
      final normalized = AuthNotifier.normalizeCookieHeader(
        'SUB=first; SUBP=first-p; XSRF-TOKEN=csrf; SUB=stale; SUBP=stale-p;',
      );

      expect(normalized, 'SUB=first; SUBP=first-p; XSRF-TOKEN=csrf');
    });

    test('does not treat a bare SUB token as a cookie header', () {
      expect(AuthNotifier.normalizeCookieHeader('_2Aabcdef'), isEmpty);
    });

    test('accepts a verified mobile WebView session without desktop SSO', () {
      expect(
        AuthNotifier.canCommitVerifiedSession(
          uid: '1234567890',
          desktopSessionVerified: false,
          mobileSessionVerified: true,
          requireDesktopSession: false,
        ),
        isTrue,
      );
      expect(
        AuthNotifier.canCommitVerifiedSession(
          uid: '1234567890',
          desktopSessionVerified: false,
          mobileSessionVerified: true,
          requireDesktopSession: true,
        ),
        isFalse,
      );
    });

    test('does not commit a uid inferred without a verified session', () {
      expect(
        AuthNotifier.canCommitVerifiedSession(
          uid: '1234567890',
          desktopSessionVerified: false,
          mobileSessionVerified: false,
          requireDesktopSession: false,
        ),
        isFalse,
      );
    });

    test('recognizes the official desktop login redirect payload', () {
      expect(
        AuthNotifier.isDefinitiveDesktopLogoutPayload({
          'ok': -100,
          'url': 'https://weibo.com/login.php?url=https%3A%2F%2Fweibo.com%2F',
        }),
        isTrue,
      );
      expect(
        AuthNotifier.isDefinitiveDesktopLogoutPayload({
          'ok': 1,
          'data': {'islogin': true},
        }),
        isFalse,
      );
    });

    test('accepts current desktop config uid variants', () {
      final payload = {
        'ok': 1,
        'data': {
          'login': true,
          'user': {'idstr': '1234567890'},
        },
      };

      expect(AuthNotifier.desktopConfigShowsLoggedIn(payload), isTrue);
      expect(AuthNotifier.desktopSessionUid(payload), '1234567890');
    });

    test('only accepts account groups matching the stored uid', () {
      final payload = {
        'groups': [
          {
            'group': [
              {'gid': '110001641537045', 'uid': '1641537045'},
            ],
          },
        ],
      };

      expect(
        AuthNotifier.groupsPayloadMatchesUid(payload, '1641537045'),
        isTrue,
      );
      expect(
        AuthNotifier.groupsPayloadMatchesUid(payload, '5825150043'),
        isFalse,
      );
    });

    test('does not probe the initial passport login URL', () {
      expect(
        shouldProbeCookiesForUrl(
          'https://passport.weibo.com/sso/signin?entry=wapsso&url=https%3A%2F%2Fm.weibo.cn%2F',
        ),
        isFalse,
      );
    });

    test('probes after the login redirect reaches Weibo', () {
      expect(shouldProbeCookiesForUrl('https://m.weibo.cn/'), isTrue);
      expect(
        shouldProbeCookiesForUrl('https://passport.weibo.com/sso/crossdomain'),
        isFalse,
      );
      expect(
        shouldProbeCookiesForUrl(
            'https://login.sina.com.cn/sso/v2/crossdomain?ticket=abc'),
        isFalse,
      );
      expect(
        shouldProbeCookiesForUrl(
            'https://passport.weibo.com/sso/signin?ticket=abc'),
        isFalse,
      );
    });

    test('detects login transition URLs for automatic synchronization', () {
      expect(
        isLoginSuccessTransitionUrl(
            'https://login.sina.com.cn/sso/v2/crossdomain?ticket=ST-12345'),
        isTrue,
      );
      expect(
        isLoginSuccessTransitionUrl('https://m.weibo.cn/'),
        isTrue,
      );
      expect(
        isLoginSuccessTransitionUrl(
            'https://passport.weibo.com/sso/signin?entry=wapsso&url=https%3A%2F%2Fm.weibo.cn%2F'),
        isFalse,
      );
    });

    test('login returns to mobile Weibo landing page', () {
      final loginUri = Uri.parse(weiboWebLoginUrl);
      expect(loginUri.host, 'passport.weibo.com');
      expect(loginUri.queryParameters['entry'], 'wapsso');
      expect(loginUri.queryParameters['url'], 'https://m.weibo.cn/');
    });

    test('accepts desktop verified session', () {
      expect(
        AuthNotifier.canCommitVerifiedSession(
          uid: '1234567890',
          desktopSessionVerified: true,
          mobileSessionVerified: false,
          requireDesktopSession: true,
        ),
        isTrue,
      );
    });

    test('cookie diagnostics expose names but never values', () {
      final summary = cookieNamesForDiagnostics(
        'SUB=secret-value; SCF=another-secret; XSRF-TOKEN=csrf-secret',
      );
      expect(summary, 'SUB,SCF,XSRF-TOKEN');
      expect(summary, isNot(contains('secret')));
    });

    test('migrates legacy mixed cookies to a verified desktop session',
        () async {
      SharedPreferences.setMockInitialValues({
        StorageService.keyIsLoggedIn: true,
        StorageService.keyUserUid: '123',
        StorageService.keyUserNickname: 'tester',
        StorageService.keyUserAvatar: 'https://example.com/avatar.jpg',
        StorageService.keyFullCookie: 'SUB=legacy-mobile; XSRF-TOKEN=old',
        StorageService.keyDesktopCookie: 'SUB=legacy-mobile; XSRF-TOKEN=old',
        StorageService.keyMobileCookie: 'SUB=legacy-mobile; XSRF-TOKEN=old',
      });
      final storage = await StorageService.init();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(cookieChannel, (call) async {
        expect(call.method, 'getNativeCookiesByDomain');
        return <String, String>{
          'desktop': 'SUB=desktop-valid; XSRF-TOKEN=desktop-csrf',
          'mobile': 'SUB=mobile-valid; XSRF-TOKEN=mobile-csrf',
        };
      });

      final notifier = AuthNotifier(
        storage,
        desktopCookieVerifier: (cookie, expectedUid) async {
          expect(expectedUid, '123');
          return cookie.contains('SUB=desktop-valid');
        },
      );

      expect(await notifier.reconcileNativeSession(), isTrue);
      expect(storage.getDesktopCookie(), contains('SUB=desktop-valid'));
      expect(storage.getMobileCookie(), contains('SUB=mobile-valid'));
      expect(storage.getFullCookie(), startsWith('SUB=desktop-valid'));
      expect(
        storage.getCookieScopeSchemaVersion(),
        StorageService.currentCookieScopeSchemaVersion,
      );
      notifier.dispose();
    });

    test('tries full cookie after stale native and stored desktop candidates',
        () async {
      SharedPreferences.setMockInitialValues({
        StorageService.keyIsLoggedIn: true,
        StorageService.keyUserUid: '456',
        StorageService.keyUserNickname: 'tester',
        StorageService.keyUserAvatar: 'https://example.com/avatar.jpg',
        StorageService.keyFullCookie: 'SUB=full-valid; XSRF-TOKEN=full-csrf',
        StorageService.keyDesktopCookie: 'SUB=desktop-stale; XSRF-TOKEN=stale',
        StorageService.keyMobileCookie:
            'SUB=mobile-valid; XSRF-TOKEN=mobile-csrf',
        StorageService.keyCookieScopeSchemaVersion:
            StorageService.currentCookieScopeSchemaVersion,
      });
      final storage = await StorageService.init();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(cookieChannel, (call) async {
        return <String, String>{
          'desktop': 'SUB=native-stale; XSRF-TOKEN=native-csrf',
          'mobile': 'SUB=mobile-valid; XSRF-TOKEN=mobile-csrf',
        };
      });
      final attempts = <String>[];
      final notifier = AuthNotifier(
        storage,
        desktopCookieVerifier: (cookie, expectedUid) async {
          attempts.add(cookie);
          return cookie.contains('SUB=full-valid');
        },
      );

      expect(await notifier.reconcileNativeSession(force: true), isTrue);
      expect(attempts, hasLength(3));
      expect(attempts[0], contains('SUB=native-stale'));
      expect(attempts[1], contains('SUB=desktop-stale'));
      expect(attempts[2], contains('SUB=full-valid'));
      expect(storage.getDesktopCookie(), contains('SUB=full-valid'));
      notifier.dispose();
    });

    test('explicit validity check repairs a stale scoped desktop cookie',
        () async {
      SharedPreferences.setMockInitialValues({
        StorageService.keyIsLoggedIn: true,
        StorageService.keyUserUid: '789',
        StorageService.keyUserNickname: 'tester',
        StorageService.keyUserAvatar: 'https://example.com/avatar.jpg',
        StorageService.keyFullCookie: 'SUB=full-valid; XSRF-TOKEN=full-csrf',
        StorageService.keyDesktopCookie: 'SUB=desktop-stale',
        StorageService.keyMobileCookie: 'SUB=mobile-stale',
        StorageService.keyCookieScopeSchemaVersion:
            StorageService.currentCookieScopeSchemaVersion,
      });
      final storage = await StorageService.init();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(cookieChannel, (call) async {
        return <String, String>{
          'desktop': 'SUB=native-stale',
          'mobile': 'SUB=mobile-stale',
        };
      });
      final notifier = AuthNotifier(
        storage,
        desktopCookieVerifier: (cookie, expectedUid) async {
          expect(expectedUid, '789');
          return cookie.contains('SUB=full-valid');
        },
      );

      expect(await notifier.checkCookieValidity(), isTrue);
      expect(
        notifier.state.cookieValidationStatus,
        CookieValidationStatus.valid,
      );
      expect(storage.getDesktopCookie(), contains('SUB=full-valid'));
      notifier.dispose();
    });
  });
}
