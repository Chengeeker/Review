import '../../../feed/data/models/weibo_status_model.dart';

/// Weibo Comment Data Model with Nested Sub-Replies and Image Attachments
class WeiboCommentModel {
  final String id;
  final String mid;
  final String textRaw;
  final String createdAt;
  final int likeCount;
  final bool liked;
  final String? source;
  final WeiboUserModel user;
  final List<WeiboPicModel> pics;
  final List<Map<String, dynamic>> urlStruct;
  final List<WeiboCommentModel> subComments;
  final int subCommentsCount;

  const WeiboCommentModel({
    required this.id,
    required this.mid,
    required this.textRaw,
    required this.createdAt,
    required this.likeCount,
    this.liked = false,
    this.source,
    required this.user,
    this.pics = const [],
    this.urlStruct = const [],
    this.subComments = const [],
    this.subCommentsCount = 0,
  });

  WeiboPicModel? get pic => pics.isNotEmpty ? pics.first : null;

  /// Formatted IP location or AI generation tag (e.g. "来自 湖北", "来自 AI生成")
  String get formattedIpOrSource {
    final rawSrc = source?.trim() ?? '';
    final screenName = user.screenName.toLowerCase();

    // 1. Detect AI generated comments (千问, 元宝, 文心, Kimi, 豆包, AI bots)
    final isAi = screenName.contains('千问') ||
        screenName.contains('ai') ||
        rawSrc.contains('ai') ||
        rawSrc.contains('AI') ||
        rawSrc.contains('生成') ||
        rawSrc.contains('千问') ||
        rawSrc.contains('元宝') ||
        rawSrc.contains('文心') ||
        rawSrc.contains('kimi') ||
        rawSrc.contains('豆包') ||
        rawSrc.contains('chatgpt');

    if (isAi) {
      return '来自 AI生成';
    }

    if (rawSrc.isEmpty) return '';

    if (rawSrc.startsWith('来自')) {
      return rawSrc;
    }

    return '来自 $rawSrc';
  }

  /// Intelligent Real Image URL Validator
  /// Strictly distinguishes genuine image files/CDNs from web search cards (e.g. 微博智搜), topics, and pages.
  static bool isRealImageUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final lower = url.toLowerCase().trim();

    // 1. Definite negative cases: search pages, user profiles, status pages, html
    if (lower.contains('s.weibo.com') ||
        lower.contains('/search?') ||
        lower.contains('weibo.com/u/') ||
        lower.contains('weibo.com/n/') ||
        lower.contains('m.weibo.cn/status/') ||
        lower.contains('m.weibo.cn/detail/') ||
        lower.contains('weibo.com/detail/') ||
        lower.contains('.html') ||
        lower.contains('.htm')) {
      return false;
    }

    // 2. Definite positive cases: Sina image CDNs and photo domains
    if (lower.contains('.sinaimg.cn') ||
        lower.contains('photo.weibo.com') ||
        lower.contains('image.weibo.com') ||
        lower.contains('pic.weibo.com')) {
      return true;
    }

    // 3. Image file extension ending or query param
    final extMatch = RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp|heic)($|\?|#)', caseSensitive: false);
    if (extMatch.hasMatch(lower)) {
      return true;
    }

    return false;
  }

  factory WeiboCommentModel.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : <String, dynamic>{};
    final user = WeiboUserModel.fromJson(userJson);

    final subList = <WeiboCommentModel>[];
    if (json['comments'] is List) {
      final rawSub = json['comments'] as List;
      for (final s in rawSub) {
        if (s is Map<String, dynamic>) {
          subList.add(WeiboCommentModel.fromJson(s));
        }
      }
    }

    // Parse raw url_struct
    final rawUrlStruct = <Map<String, dynamic>>[];
    if (json['url_struct'] is List) {
      for (final u in json['url_struct'] as List) {
        if (u is Map<String, dynamic>) {
          rawUrlStruct.add(u);
        }
      }
    }

    // Parse comment image attachments
    final picsList = <WeiboPicModel>[];
    final seenUrls = <String>{};
    final imageShortUrls = <String>{};

    // 1. Direct 'pic' field (Map or String)
    if (json['pic'] is Map<String, dynamic>) {
      final p = json['pic'] as Map<String, dynamic>;
      final parsed = WeiboPicModel.fromJson(p);
      final candidateUrl = parsed.largeUrl.isNotEmpty ? parsed.largeUrl : parsed.thumbnail;
      if (isRealImageUrl(candidateUrl) && seenUrls.add(candidateUrl)) {
        picsList.add(parsed);
      }
    } else if (json['pic'] is String && (json['pic'] as String).isNotEmpty) {
      final url = json['pic'] as String;
      if (isRealImageUrl(url) && seenUrls.add(url)) {
        picsList.add(WeiboPicModel(
          pid: '',
          thumbnail: url,
          large: url,
          original: url,
        ));
      }
    }

    // 2. 'pic_infos' field
    if (json['pic_infos'] is Map<String, dynamic>) {
      final picInfos = json['pic_infos'] as Map<String, dynamic>;
      for (final entry in picInfos.values) {
        if (entry is Map<String, dynamic>) {
          final parsed = WeiboPicModel.fromJson(entry);
          final candidateUrl = parsed.largeUrl.isNotEmpty ? parsed.largeUrl : parsed.thumbnail;
          if (isRealImageUrl(candidateUrl) && seenUrls.add(candidateUrl)) {
            picsList.add(parsed);
          }
        }
      }
    }

    // 3. 'url_struct' field (Weibo image card attachments embedded in URLs)
    for (final u in rawUrlStruct) {
      final shortUrl = u['short_url']?.toString();
      final urlTitle = u['url_title']?.toString() ?? '';
      final urlType = u['url_type'];
      final oriUrl = u['ori_url']?.toString() ?? u['long_url']?.toString() ?? '';

      bool isImage = false;

      if (u['pic_infos'] is Map<String, dynamic>) {
        final pInfos = u['pic_infos'] as Map<String, dynamic>;
        for (final entry in pInfos.values) {
          if (entry is Map<String, dynamic>) {
            final parsed = WeiboPicModel.fromJson(entry);
            final candidateUrl = parsed.largeUrl.isNotEmpty ? parsed.largeUrl : parsed.thumbnail;
            if (isRealImageUrl(candidateUrl) && seenUrls.add(candidateUrl)) {
              picsList.add(parsed);
              isImage = true;
            }
          }
        }
      } else if (u['pic_info'] is Map<String, dynamic>) {
        final parsed = WeiboPicModel.fromJson(u['pic_info'] as Map<String, dynamic>);
        final candidateUrl = parsed.largeUrl.isNotEmpty ? parsed.largeUrl : parsed.thumbnail;
        if (isRealImageUrl(candidateUrl) && seenUrls.add(candidateUrl)) {
          picsList.add(parsed);
          isImage = true;
        }
      } else if (urlType == 39 || urlTitle == '查看图片' || isRealImageUrl(oriUrl)) {
        if (isRealImageUrl(oriUrl) && seenUrls.add(oriUrl)) {
          picsList.add(WeiboPicModel(
            pid: '',
            thumbnail: oriUrl,
            large: oriUrl,
            original: oriUrl,
          ));
        }
        isImage = true;
      }

      // If and only if it is a verified image attachment, record shortUrl for removal from text_raw
      if (isImage && shortUrl != null && shortUrl.isNotEmpty) {
        imageShortUrls.add(shortUrl);
      }
    }

    // Clean up text_raw by removing ONLY the short URLs that belong to real rendered images
    String rawText = json['text_raw']?.toString() ?? json['text']?.toString() ?? '';
    if (picsList.isNotEmpty) {
      for (final shortUrl in imageShortUrls) {
        rawText = rawText.replaceAll(shortUrl, '').trim();
      }
      rawText = rawText.replaceAll(RegExp(r'\[查看图片\]'), '').trim();
    }

    String? rawSource = json['source']?.toString();
    if (rawSource != null && rawSource.contains('<')) {
      rawSource = rawSource.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    }

    return WeiboCommentModel(
      id: json['id']?.toString() ?? '',
      mid: json['mid']?.toString() ?? json['id']?.toString() ?? '',
      textRaw: rawText,
      createdAt: json['created_at']?.toString() ?? '',
      likeCount: json['like_counts'] is int
          ? json['like_counts'] as int
          : (json['likes_count'] is int ? json['likes_count'] as int : 0),
      liked: json['liked'] == true,
      source: rawSource,
      user: user,
      pics: picsList,
      urlStruct: rawUrlStruct,
      subComments: subList,
      subCommentsCount: json['total_number'] is int
          ? json['total_number'] as int
          : (json['comments_count'] is int ? json['comments_count'] as int : subList.length),
    );
  }
}
