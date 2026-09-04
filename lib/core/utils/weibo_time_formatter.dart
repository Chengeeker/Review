
/// Card Display Settings
class CardDisplaySettings {
  final String timeDisplayMode; // 'relative' | 'absolute'
  final bool showWeekday;
  final bool showYear;
  final bool showTimezone;
  final bool showSeconds;
  final bool showSource;
  final bool showRegion;

  const CardDisplaySettings({
    this.timeDisplayMode = 'relative',
    this.showWeekday = false,
    this.showYear = false,
    this.showTimezone = false,
    this.showSeconds = false,
    this.showSource = true,
    this.showRegion = true,
  });

  CardDisplaySettings copyWith({
    String? timeDisplayMode,
    bool? showWeekday,
    bool? showYear,
    bool? showTimezone,
    bool? showSeconds,
    bool? showSource,
    bool? showRegion,
  }) {
    return CardDisplaySettings(
      timeDisplayMode: timeDisplayMode ?? this.timeDisplayMode,
      showWeekday: showWeekday ?? this.showWeekday,
      showYear: showYear ?? this.showYear,
      showTimezone: showTimezone ?? this.showTimezone,
      showSeconds: showSeconds ?? this.showSeconds,
      showSource: showSource ?? this.showSource,
      showRegion: showRegion ?? this.showRegion,
    );
  }
}

/// Weibo Time Formatter (支持 RFC 822 时间解析、智能相对时间、绝对具体时间、中英多语言与各细项开关)
class WeiboTimeFormatter {
  WeiboTimeFormatter._();

  static const _monthNamesEn = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static const _weekdayNamesZh = [
    '', '周一', '周二', '周三', '周四', '周五', '周六', '周日'
  ];

  static const _weekdayNamesEn = [
    '', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];

  /// Parse Weibo raw date string (e.g. "Fri Aug 28 01:15:56 +0800 2026" or ISO 8601)
  static DateTime? parseWeiboDate(String raw) {
    if (raw.isEmpty) return null;

    // Handle Weibo standard RFC 822 date format: "Fri Aug 28 01:15:56 +0800 2026"
    final parts = raw.trim().split(RegExp(r'\s+'));
    if (parts.length >= 6) {
      final monthMap = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
      };
      final month = monthMap[parts[1]];
      final day = int.tryParse(parts[2]);
      final timeParts = parts[3].split(':');
      final year = int.tryParse(parts[5]);

      if (month != null && day != null && year != null && timeParts.length >= 2) {
        final hour = int.tryParse(timeParts[0]) ?? 0;
        final minute = int.tryParse(timeParts[1]) ?? 0;
        final second = timeParts.length > 2 ? (int.tryParse(timeParts[2]) ?? 0) : 0;
        return DateTime(year, month, day, hour, minute, second);
      }
    }

    // Try standard ISO-8601
    return DateTime.tryParse(raw);
  }

  /// Format date with customizable settings and localization
  static String format({
    required String rawDate,
    CardDisplaySettings settings = const CardDisplaySettings(),
    String language = 'zh', // 'zh' or 'en'
  }) {
    if (rawDate.isEmpty) return '';

    final isEn = language == 'en';
    final date = parseWeiboDate(rawDate);

    // If string is already relative text (e.g. "刚刚", "3分钟前") and not parsed
    if (date == null) {
      return rawDate;
    }

    final now = DateTime.now();
    final diff = now.difference(date);

    // 1. Optional Weekday string
    String weekdayStr = '';
    if (settings.showWeekday) {
      weekdayStr = isEn
          ? '${_weekdayNamesEn[date.weekday]} '
          : '${_weekdayNamesZh[date.weekday]} ';
    }

    // 2. Optional Timezone string
    String timezoneStr = settings.showTimezone ? ' +0800' : '';

    // 3. Time string (HH:mm or HH:mm:ss)
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');
    final timeStr = settings.showSeconds ? '$hour:$minute:$second' : '$hour:$minute';

    // Mode A: Relative Time (相对时间模式)
    if (settings.timeDisplayMode == 'relative') {
      if (diff.isNegative || diff.inSeconds < 60) {
        return (isEn ? 'Just now' : '刚刚') + timezoneStr;
      }
      if (diff.inMinutes < 60) {
        return (isEn ? '${diff.inMinutes}m ago' : '${diff.inMinutes}分钟前') + timezoneStr;
      }
      if (diff.inHours < 24 && date.day == now.day) {
        return (isEn ? '${diff.inHours}h ago' : '${diff.inHours}小时前') + timezoneStr;
      }

      final isYesterday = (now.day - date.day == 1 || (now.day == 1 && diff.inHours < 48)) &&
          now.month == date.month &&
          now.year == date.year;
      if (isYesterday) {
        return '$weekdayStr${isEn ? 'Yesterday' : '昨天'} $timeStr$timezoneStr';
      }

      // Same year
      if (date.year == now.year && !settings.showYear) {
        final dateStr = isEn
            ? '${_monthNamesEn[date.month]} ${date.day}'
            : '${date.month}月${date.day}日';
        return '$weekdayStr$dateStr $timeStr$timezoneStr';
      }

      // Cross year or forced showYear
      final dateStr = isEn
          ? '${_monthNamesEn[date.month]} ${date.day}, ${date.year}'
          : '${date.year}年${date.month}月${date.day}日';
      return '$weekdayStr$dateStr $timeStr$timezoneStr';
    }

    // Mode B: Absolute Time (具体绝对时间模式)
    final yearStr = settings.showYear || date.year != now.year
        ? (isEn ? '${date.year}-' : '${date.year}年')
        : '';
    final mStr = isEn
        ? date.month.toString().padLeft(2, '0')
        : '${date.month}月';
    final dStr = isEn
        ? date.day.toString().padLeft(2, '0')
        : '${date.day}日';

    final datePart = isEn ? '$yearStr$mStr-$dStr' : '$yearStr$mStr$dStr';
    return '$weekdayStr$datePart $timeStr$timezoneStr';
  }
}
