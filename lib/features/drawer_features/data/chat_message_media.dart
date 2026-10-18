import 'dart:convert';

import '../../feed/data/models/weibo_status_model.dart';

String chatAttachmentUrl(String fid) => Uri.https(
  'upload.api.weibo.com',
  '/2/mss/msget',
  {'source': '209678993', 'fid': fid},
).toString();

List<String> chatMessageVideoIds(Map<String, dynamic> message) {
  if (!{'10', '5'}.contains(message['media_type']?.toString())) return [];
  final raw = message['att_ids'] ?? message['fids'] ?? message['fid'];
  return (raw is List ? raw : (raw?.toString() ?? '').split(','))
      .map((id) => id.toString().trim())
      .where((id) => id.isNotEmpty && id != 'null')
      .toSet()
      .toList();
}

/// The official metadata service returns JSONP; only decode the named callback.
Map<String, dynamic> chatAttachmentMetadata(Object? raw) {
  if (raw is String) {
    var json = raw.trim();
    final match = RegExp(r'^__review_video_meta\s*\(([\s\S]*)\)\s*;?$')
        .firstMatch(json);
    if (match != null) json = match.group(1)!;
    try {
      raw = jsonDecode(json);
    } catch (_) {
      return {};
    }
  }
  return raw is Map ? Map<String, dynamic>.from(raw) : {};
}

WeiboPicModel? chatMessageVideo(
  Map<String, dynamic> message,
  String fid,
  Map<String, dynamic> metadata,
) {
  if (metadata['is_delete'] == true ||
      metadata['is_delete']?.toString() == '1') {
    return null;
  }
  if (message['media_type']?.toString() != '10' &&
      metadata['extension']?.toString().toLowerCase() != 'mp4') {
    return null;
  }
  final posterFid = message['ext_text_video_pic_fid']?.toString().trim() ?? '';
  final cover = posterFid.isNotEmpty
      ? chatAttachmentUrl(posterFid)
      : chatMediaUrl(
              metadata['screenshot'] ??
                  metadata['thumbnail_240'] ??
                  message['screenshot'],
            ) ??
            '';
  final size = metadata['videosize']?.toString().split('*') ?? [];
  return WeiboPicModel(
    pid: fid,
    thumbnail: cover,
    large: cover,
    original: cover,
    width: size.length == 2 ? double.tryParse(size[0]) ?? 0 : 0,
    height: size.length == 2 ? double.tryParse(size[1]) ?? 0 : 0,
    isVideo: true,
    videoUrl: chatAttachmentUrl(
      metadata['fid']?.toString().trim().isNotEmpty == true
          ? metadata['fid'].toString()
          : fid,
    ),
    videoTitle: '聊天视频',
  );
}

/// Image fields used by Weibo's WebIM conversation and group history APIs.
List<String> chatMessageImageUrls(Map<String, dynamic> message) {
  final urls = <String>{};
  if (message['media_type']?.toString() == '1') {
    final attachments = message['att_ids'] ?? message['fids'];
    final ids = attachments is List
        ? attachments
        : (attachments?.toString() ?? '').split(',');
    for (final value in ids) {
      final fid = value?.toString().trim() ?? '';
      if (fid.isEmpty) continue;
      urls.add(
        Uri.https('upload.api.weibo.com', '/2/mss/msget', {
          'source': '209678993',
          'fid': fid,
          'imageType': 'origin',
        }).toString(),
      );
    }
  }
  if (urls.isNotEmpty) return urls.toList(growable: false);
  final pictures = message['pic_infos'] ?? message['pic_gifs'];
  final pictureList = pictures is Map ? [pictures] : pictures;
  if (pictureList is List) {
    for (final picture in pictureList.whereType<Map>()) {
      var url = picture['original_pic']?.toString().trim() ?? '';
      if (url.startsWith('//')) url = 'https:$url';
      final uri = Uri.tryParse(url);
      if (uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty) {
        urls.add(url);
      }
    }
  }
  final objects = message['url_objects'];
  if (objects is List) {
    for (final entry in objects.whereType<Map>()) {
      final outer = entry['object'];
      final object = outer is Map && outer['object'] is Map
          ? outer['object'] as Map
          : outer;
      if (object is Map && object['gif_name'] != null) {
        final url = chatMediaUrl(object['url']);
        if (url != null) urls.add(url);
      }
    }
  }
  return urls.toList(growable: false);
}

String? chatMediaUrl(Object? value) {
  var url = value?.toString().trim().replaceAll('&amp;', '&') ?? '';
  if (url.startsWith('//')) url = 'https:$url';
  final uri = Uri.tryParse(url);
  return uri != null &&
          ['http', 'https'].contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? url
      : null;
}

String chatMessageCaption(
  String text, {
  required bool hasImages,
  bool hasVideo = false,
}) => hasVideo && const {'分享视频', '发送视频', '[视频]', '[视频消息]'}.contains(text.trim())
    ? ''
    : hasImages &&
          const {
            '[图片]',
            '[图片消息]',
            '发送图片',
            '分享图片',
            '[动画表情]',
            '分享动画',
            '分享动画表情',
            '发送表情',
            '[表情]',
          }.contains(text.trim())
    ? ''
    : text;

class ChatLinkPreview {
  const ChatLinkPreview(this.url, this.title, this.description, this.imageUrl);
  final String url;
  final String title;
  final String description;
  final String? imageUrl;

  static ChatLinkPreview? fromMessage(Map<String, dynamic> message) {
    final directUrl = [
      message['linkurl'],
      message['url_long'],
      message['url_short'],
    ].map(chatMediaUrl).whereType<String>().firstOrNull;
    final directTitle = message['cardtitle']?.toString() ?? '';
    final entries = message['url_objects'];
    for (final entry
        in (entries is List ? entries : const []).whereType<Map>()) {
      final info = entry['info'] is Map ? entry['info'] as Map : const {};
      final status = entry['status'];
      final user = entry['user'];
      final outer = entry['object'];
      final object = outer is Map && outer['object'] is Map
          ? outer['object']
          : outer;
      final data = status is Map
          ? status
          : user is Map
          ? user
          : object;
      if (data is! Map || data['gif_name'] != null) continue;
      final author = data['user'] is Map ? data['user'] as Map : const {};
      final title =
          (author['screen_name'] ??
                  data['screen_name'] ??
                  data['display_name'] ??
                  data['title'])
              ?.toString() ??
          '';
      final statusId = status is Map
          ? (status['idstr'] ?? status['id'] ?? status['mid'])?.toString()
          : null;
      final userId = user is Map
          ? (user['idstr'] ?? user['id'] ?? user['uid'])?.toString()
          : null;
      final url = [
        if (statusId != null && RegExp(r'^\d+$').hasMatch(statusId))
          'https://weibo.com/detail/$statusId',
        if (userId != null && RegExp(r'^\d+$').hasMatch(userId))
          'https://weibo.com/u/$userId',
        info['url_long'],
        data['url'],
        info['url_short'],
        message['url_short'],
      ].map(chatMediaUrl).whereType<String>().firstOrNull;
      if (url == null || title.isEmpty) continue;
      final image = data['image'] is Map
          ? (data['image'] as Map)['url']
          : data['image'];
      return ChatLinkPreview(
        url,
        title,
        (data['text'] ??
                data['summary'] ??
                data['description'] ??
                data['verified_reason'] ??
                '')
            .toString(),
        chatMediaUrl(
          data['thumbnail_pic'] ?? data['profile_image_url'] ?? image,
        ),
      );
    }
    return directUrl != null && directTitle.isNotEmpty
        ? ChatLinkPreview(
            directUrl,
            directTitle,
            (message['desc'] ?? '').toString(),
            chatMediaUrl(message['thumbnail_pic']),
          )
        : null;
  }
}
