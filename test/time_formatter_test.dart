import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/utils/weibo_time_formatter.dart';

void main() {
  group('WeiboTimeFormatter Unit Tests', () {
    test('parseWeiboDate correctly parses RFC 822 Weibo date string', () {
      const raw = 'Fri Aug 28 01:15:56 +0800 2026';
      final dt = WeiboTimeFormatter.parseWeiboDate(raw);
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
      expect(dt.month, 8);
      expect(dt.day, 28);
      expect(dt.hour, 1);
      expect(dt.minute, 15);
      expect(dt.second, 56);
    });

    test('format relative time in Chinese & English', () {
      final now = DateTime.now();
      // 5 minutes ago
      final fiveMinAgo = now.subtract(const Duration(minutes: 5));
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final monthStr = months[fiveMinAgo.month - 1];
      final dayStr = days[fiveMinAgo.weekday - 1];
      final raw = '$dayStr $monthStr ${fiveMinAgo.day.toString().padLeft(2, '0')} ${fiveMinAgo.hour.toString().padLeft(2, '0')}:${fiveMinAgo.minute.toString().padLeft(2, '0')}:00 +0800 ${fiveMinAgo.year}';

      const zhSettings = CardDisplaySettings(timeDisplayMode: 'relative');
      final formattedZh = WeiboTimeFormatter.format(rawDate: raw, settings: zhSettings, language: 'zh');
      expect(formattedZh.contains('分钟前') || formattedZh == '刚刚', isTrue);

      final formattedEn = WeiboTimeFormatter.format(rawDate: raw, settings: zhSettings, language: 'en');
      expect(formattedEn.contains('m ago') || formattedEn == 'Just now', isTrue);
    });

    test('format absolute time with customizable options', () {
      const raw = 'Fri Aug 28 01:15:56 +0800 2026';
      const settings = CardDisplaySettings(
        timeDisplayMode: 'absolute',
        showYear: true,
        showWeekday: true,
        showTimezone: true,
        showSeconds: true,
      );

      final formattedZh = WeiboTimeFormatter.format(rawDate: raw, settings: settings, language: 'zh');
      expect(formattedZh.contains('2026年8月28日'), isTrue);
      expect(formattedZh.contains('周五'), isTrue);
      expect(formattedZh.contains('+0800'), isTrue);
      expect(formattedZh.contains(':56'), isTrue);
    });
  });
}
