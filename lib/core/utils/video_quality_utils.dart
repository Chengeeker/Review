/// Expose only explicit resolution tiers; aliases are playback fallbacks, not tiers.
Map<String, String> normalizeVideoQualities(
  Map<String, String> qualities, {
  String? preferredUrl,
}) {
  final tiers = <int, String>{};
  final seenUrls = <String>{};
  final entries = qualities.entries
      .where((e) => e.value.trim().isNotEmpty)
      .toList();
  for (final entry in entries) {
    final match = RegExp(
      r'(?:^|[^0-9])(2160|1440|1080|720|480|360)(?:p|[^0-9]|$)',
      caseSensitive: false,
    ).firstMatch(entry.key);
    if (match == null) continue;
    final height = int.parse(match.group(1)!);
    final url = entry.value.trim();
    if (!tiers.containsKey(height) || url == preferredUrl) tiers[height] = url;
  }
  final result = <String, String>{};
  for (final height in (tiers.keys.toList()..sort((a, b) => b.compareTo(a)))) {
    final url = tiers[height]!;
    if (seenUrls.add(url)) result['${height}P'] = url;
  }
  if (result.isNotEmpty) return result;
  if (entries.isEmpty) return result;
  final fallback = entries.firstWhere(
    (e) => e.value.trim() == preferredUrl,
    orElse: () => entries.first,
  );
  return {fallback.key == '直播' ? '直播' : '分辨率未知': fallback.value.trim()};
}
