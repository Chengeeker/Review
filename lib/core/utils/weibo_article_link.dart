/// Shared, UI-independent identification for Weibo's native article reader.
String? weiboArticleIdFromUrl(String rawUrl) {
  final value = rawUrl.trim().replaceAll('&amp;', '&');
  final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  final host = uri.host.toLowerCase();
  final isWeiboHost = host == 'weibo.com' ||
      host.endsWith('.weibo.com') ||
      host == 'weibo.cn' ||
      host.endsWith('.weibo.cn');
  if (!isWeiboHost) return null;

  final path = uri.path.replaceFirst(RegExp(r'/+$'), '').toLowerCase();
  final id = path == '/ttarticle/p/show'
      ? uri.queryParameters['id']?.trim()
      : RegExp(r'^/article/m/show/id/([^/]+)$').firstMatch(path)?.group(1);
  return id == null || id.isEmpty ? null : id;
}

String? weiboArticleUrlFromMetadata(Map<String, dynamic> entry) {
  for (final key in const [
    'article_url',
    'ori_url',
    'long_url',
    'h5_target_url',
    'target_url',
    'page_url',
    'url',
  ]) {
    final id = weiboArticleIdFromUrl(entry[key]?.toString() ?? '');
    if (id != null) return _articleUrl(id);
  }
  final type =
      (entry['card_object_type'] ?? entry['object_type'] ?? entry['type'])
          ?.toString()
          .toLowerCase();
  if (type != 'article') return null;
  for (final key in const ['page_id', 'object_id']) {
    final id = entry[key]?.toString().replaceFirst('1022:', '') ?? '';
    if (RegExp(r'^(?:230940|231047)\d+$').hasMatch(id)) return _articleUrl(id);
  }
  return null;
}

String _articleUrl(String id) =>
    'https://weibo.com/ttarticle/p/show?id=${Uri.encodeQueryComponent(id)}';
