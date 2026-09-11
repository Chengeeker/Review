import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/auth/auth_provider.dart';
import 'package:review/features/auth/presentation/login_page.dart';

void main() {
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
        isTrue,
      );
      expect(
        shouldProbeCookiesForUrl(
            'https://passport.weibo.com/sso/signin?ticket=abc'),
        isTrue,
      );
    });
  });
}
