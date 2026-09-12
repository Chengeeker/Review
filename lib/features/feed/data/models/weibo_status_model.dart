import 'weibo_engagement_models.dart';

int? _visibilityCodeFromValue(Object? value) {
  if (value is num) return value.toInt();
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final numeric = int.tryParse(text);
  if (numeric != null) return numeric;

  switch (text.toLowerCase()) {
    case 'public':
    case '公开':
      return 0;
    case 'fans':
    case '粉丝':
    case '仅粉丝可见':
      return 10;
    case 'friends':
    case '好友':
    case '好友圈':
    case '好友圈可见':
    case '仅好友可见':
      return 6;
    case 'private':
    case '私密':
    case '仅自己可见':
    case '仅自己':
      return 1;
    case 'group':
    case '群友':
    case '群可见':
    case '群友可见':
      return 5;
  }
  return null;
}

int? _visibilityTypeFromJson(Map<String, dynamic> json) {
  for (final key in const [
    'visible_type',
    'visibleType',
    'visibility_type',
    'visibilityType',
    'privacy_type',
    'privacyType',
  ]) {
    final code = _visibilityCodeFromValue(json[key]);
    if (code != null) return code;
  }

  final visible = json['visible'];
  if (visible is Map) {
    for (final key in const [
      'type',
      'visible_type',
      'visibleType',
      'code',
      'value',
    ]) {
      final code = _visibilityCodeFromValue(visible[key]);
      if (code != null) return code;
    }
  } else {
    final code = _visibilityCodeFromValue(visible);
    if (code != null) return code;
  }

  return _visibilityCodeFromValue(json['privacy']);
}

String? _normalizeMediaUrl(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;

  final normalized = raw.startsWith('//')
      ? 'https:$raw'
      : (raw.startsWith('http://')
          ? raw.replaceFirst('http://', 'https://')
          : raw);
  final uri = Uri.tryParse(normalized);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }

  // A live-room page is HTML, not a playable media source. It can still be
  // used to extract the live id, but must never be handed to video_player.
  final lower = normalized.toLowerCase();
  if (lower.contains('weibo.com/l/wblive/') ||
      lower.contains('weibo.cn/l/wblive/')) {
    return null;
  }
  return normalized;
}

String? _liveIdFromString(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;

  final pageMatch = RegExp(
    r'(?:https?://)?(?:www\.)?weibo\.(?:com|cn)/l/(?:wblive/)?p/show/([^/?#]+)',
    caseSensitive: false,
  ).firstMatch(text);
  if (pageMatch != null) {
    return Uri.decodeComponent(pageMatch.group(1) ?? '');
  }

  final queryMatch = RegExp(r'(?:[?&])live_id=([^&#]+)', caseSensitive: false)
      .firstMatch(text);
  if (queryMatch != null) {
    return Uri.decodeComponent(queryMatch.group(1) ?? '');
  }
  return null;
}

String? _extractLiveId(Object? value) {
  if (value is String) return _liveIdFromString(value);
  if (value is List) {
    for (final item in value) {
      final liveId = _extractLiveId(item);
      if (liveId != null && liveId.isNotEmpty) return liveId;
    }
    return null;
  }
  if (value is Map) {
    for (final key in const ['live_id', 'liveId', 'liveid', 'lid']) {
      final candidate = value[key]?.toString().trim() ?? '';
      if (candidate.isNotEmpty && !candidate.contains('/')) return candidate;
    }
    for (final item in value.values) {
      final liveId = _extractLiveId(item);
      if (liveId != null && liveId.isNotEmpty) return liveId;
    }
  }
  return null;
}

int? _liveStatusFromValue(Object? value) {
  if (value is num) return value.toInt();
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : int.tryParse(text);
}

class WeiboPicModel {
  final String pid;
  final String thumbnail;
  final String large;
  final String original;
  final double width;
  final double height;
  final bool isGif;
  final bool isLongPic;
  final bool isLivePhoto;
  final String? livePhotoVideoUrl;
  final bool isVideo;
  final String? videoUrl;
  final String? videoDuration;
  final String? videoTitle;

  const WeiboPicModel({
    required this.pid,
    required this.thumbnail,
    required this.large,
    required this.original,
    this.width = 0,
    this.height = 0,
    this.isGif = false,
    this.isLongPic = false,
    this.isLivePhoto = false,
    this.livePhotoVideoUrl,
    this.isVideo = false,
    this.videoUrl,
    this.videoDuration,
    this.videoTitle,
  });

  /// High quality preview URL for feed cards & grid (uses orj960 / large: crisp 80%-100% original quality, not blurry thumbnail)
  String get previewUrl => large.isNotEmpty ? large : bmiddleUrl;

  /// Upgraded bmiddleUrl (now uses orj960/large high-res preview instead of blurry 440px bmiddle)
  String get bmiddleUrl {
    if (large.isNotEmpty) return large;
    if (thumbnail.contains('/thumbnail/')) {
      return thumbnail.replaceAll('/thumbnail/', '/orj960/');
    }
    if (thumbnail.contains('/bmiddle/')) {
      return thumbnail.replaceAll('/bmiddle/', '/orj960/');
    }
    return thumbnail;
  }

  /// Large URL for gallery / full screen
  String get largeUrl => large.isNotEmpty ? large : bmiddleUrl;

  /// Original lossless URL
  String get originalUrl =>
      original.isNotEmpty ? original : (large.isNotEmpty ? large : bmiddleUrl);
  bool get isLive => isLivePhoto;
  bool get isLong => isLongPic;

  factory WeiboPicModel.fromJson(Map<String, dynamic> json) {
    final pid = json['pid']?.toString() ?? '';
    final thumbnail = json['thumbnail']?['url']?.toString() ??
        json['url']?.toString() ??
        (pid.isNotEmpty ? 'https://wx1.sinaimg.cn/thumbnail/$pid.jpg' : '');
    final orj960 = json['orj960']?['url']?.toString() ??
        (pid.isNotEmpty ? 'https://wx1.sinaimg.cn/orj960/$pid.jpg' : '');
    final large = json['large']?['url']?.toString() ??
        json['large_url']?.toString() ??
        (orj960.isNotEmpty
            ? orj960
            : (pid.isNotEmpty ? 'https://wx1.sinaimg.cn/large/$pid.jpg' : ''));
    final original = json['original']?['url']?.toString() ??
        json['largest']?['url']?.toString() ??
        json['mw2000']?['url']?.toString() ??
        (large.isNotEmpty
            ? large
            : (pid.isNotEmpty
                ? 'https://wx1.sinaimg.cn/large/$pid.jpg'
                : thumbnail));

    final geo = json['large']?['geo'] as Map<String, dynamic>? ??
        json['geo'] as Map<String, dynamic>?;
    final w = geo?['width'] ?? json['width'] ?? 0;
    final h = geo?['height'] ?? json['height'] ?? 0;

    final type = json['type']?.toString().toLowerCase();

    // Parse Live Photo video stream URL
    String? videoUrl;
    if (json['video'] is String && (json['video'] as String).isNotEmpty) {
      videoUrl = json['video'] as String;
    } else if (json['video'] is Map && json['video']['url'] != null) {
      videoUrl = json['video']['url']?.toString();
    } else if (json['video_url'] != null) {
      videoUrl = json['video_url']?.toString();
    } else if (json['livephoto_video'] != null) {
      videoUrl = json['livephoto_video']?.toString();
    } else if (json['fid'] != null && json['fid'].toString().isNotEmpty) {
      videoUrl = 'https://video.weibo.com/media/livephoto/${json['fid']}.mp4';
    }

    final isLive = type == 'livephoto' ||
        json['is_livephoto'] == true ||
        json['live_photo'] != null ||
        (videoUrl != null && videoUrl.isNotEmpty);

    final isLong = json['is_long'] == true ||
        json['cut_type'] == 1 ||
        (h > 0 && w > 0 && h / w > 2.0);

    final isVideo = type == 'video' ||
        json['is_video'] == true ||
        (json['video_url'] != null &&
            json['video_url'].toString().isNotEmpty) ||
        (json['isVideo'] == true);

    final vUrl = json['video_url']?.toString() ?? json['videoUrl']?.toString();
    final vDur =
        json['video_duration']?.toString() ?? json['videoDuration']?.toString();
    final vTitle =
        json['video_title']?.toString() ?? json['videoTitle']?.toString();

    return WeiboPicModel(
      pid: pid,
      thumbnail: thumbnail,
      large: large,
      original: original,
      width: w.toDouble(),
      height: h.toDouble(),
      isGif: type == 'gif' || thumbnail.endsWith('.gif'),
      isLongPic: isLong,
      isLivePhoto: isLive,
      livePhotoVideoUrl: videoUrl,
      isVideo: isVideo,
      videoUrl: vUrl,
      videoDuration: vDur,
      videoTitle: vTitle,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pid': pid,
      'thumbnail': {'url': thumbnail},
      'large': {'url': large, 'width': width, 'height': height},
      'original': {'url': original},
      'width': width,
      'height': height,
      'type': isLivePhoto
          ? 'livephoto'
          : (isGif ? 'gif' : (isVideo ? 'video' : 'jpg')),
      'is_long': isLongPic,
      'is_livephoto': isLivePhoto,
      'livePhotoVideoUrl': livePhotoVideoUrl,
      'isVideo': isVideo,
      'videoUrl': videoUrl,
      'videoDuration': videoDuration,
      'videoTitle': videoTitle,
    };
  }
}

/// Weibo User Model
class WeiboUserModel {
  final String id;
  final String screenName;
  final String avatar;
  final String avatarHd;
  final bool verified;
  final int verifiedType;
  final String verifiedReason;
  final String description;
  final int followersCount;
  final int friendsCount;
  final int statusesCount;
  final bool following;
  final bool followMe;
  final String gender;
  final String ipLocation;

  const WeiboUserModel({
    required this.id,
    required this.screenName,
    required this.avatar,
    this.avatarHd = '',
    this.verified = false,
    this.verifiedType = -1,
    this.verifiedReason = '',
    this.description = '',
    this.followersCount = 0,
    this.friendsCount = 0,
    this.statusesCount = 0,
    this.following = false,
    this.followMe = false,
    this.gender = 'm',
    this.ipLocation = '',
  });

  String get followersCountStr {
    if (followersCount >= 10000) {
      return '${(followersCount / 10000).toStringAsFixed(1)}万';
    }
    return '$followersCount';
  }

  factory WeiboUserModel.fromJson(Map<String, dynamic> json) {
    return WeiboUserModel(
      id: json['id']?.toString() ??
          json['idstr']?.toString() ??
          json['uid']?.toString() ??
          '',
      screenName: json['screen_name']?.toString() ??
          json['name']?.toString() ??
          json['nick']?.toString() ??
          '匿名用户',
      avatar: json['avatar_hd']?.toString() ??
          json['avatar_large']?.toString() ??
          json['profile_image_url']?.toString() ??
          '',
      avatarHd: json['avatar_hd']?.toString() ?? '',
      verified: json['verified'] == true ||
          (json['verified_type'] is int && (json['verified_type'] as int) >= 0),
      verifiedType:
          json['verified_type'] is int ? json['verified_type'] as int : -1,
      verifiedReason: json['verified_reason']?.toString() ??
          json['verified_detail']?['desc']?.toString() ??
          '',
      description: json['description']?.toString() ??
          json['verified_reason']?.toString() ??
          '',
      followersCount: json['followers_count'] is int
          ? json['followers_count'] as int
          : (json['followers_count_str'] != null ? 0 : 0),
      friendsCount:
          json['friends_count'] is int ? json['friends_count'] as int : 0,
      statusesCount:
          json['statuses_count'] is int ? json['statuses_count'] as int : 0,
      following: json['following'] == true,
      followMe: json['follow_me'] == true,
      gender: json['gender']?.toString() ?? 'm',
      ipLocation:
          json['location']?.toString() ?? json['ip_location']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'screen_name': screenName,
      'avatar_large': avatar,
      'avatar_hd': avatarHd,
      'verified': verified,
      'verified_type': verifiedType,
      'verified_reason': verifiedReason,
      'description': description,
      'followers_count': followersCount,
      'friends_count': friendsCount,
      'statuses_count': statusesCount,
      'following': following,
      'follow_me': followMe,
      'gender': gender,
      'location': ipLocation,
    };
  }
}

/// Weibo Status (Tweet) Model
class WeiboStatusModel {
  final String id;
  final String mid;
  final String? mblogid;
  final String createdAt;
  final String textRaw;
  final String? textHtml;
  final String? fullTextRaw;
  final bool isLongText;
  final String source;
  final int repostsCount;
  final int commentsCount;
  final int attitudesCount;
  final bool liked;
  final bool favorited;
  final WeiboUserModel user;
  final List<WeiboPicModel> pics;
  final WeiboStatusModel? retweetedStatus;
  final String? regionName;
  final int? visibilityType;
  final String? titleText;
  final String? titleIcon;
  final bool isTop;
  final String? videoCoverUrl;
  final String? videoStreamUrl;
  final String? videoDuration;
  final int videoPlayCount;
  final String? videoTitle;
  final Map<String, String>? videoQualityUrls;

  /// Official live-room identifier (for example `1022:...`). This is
  /// different from a Live Photo URL and is resolved through Weibo's live
  /// room endpoint before playback.
  final String? liveId;
  /// Official live-room status: 0 not started, 1 live, 3 replay, 5 ended.
  final int? liveStatus;
  final String? chaohuaTitle;
  final String? chaohuaContainerId;
  final String? chaohuaAvatar;
  final List<Map<String, dynamic>>? urlStruct;
  final WeiboPollModel? poll;
  final WeiboHotTopicModel? hotTopic;
  final int editCount;

  const WeiboStatusModel({
    required this.id,
    required this.mid,
    this.mblogid,
    required this.createdAt,
    required this.textRaw,
    this.textHtml,
    this.fullTextRaw,
    this.isLongText = false,
    required this.source,
    required this.repostsCount,
    required this.commentsCount,
    required this.attitudesCount,
    this.liked = false,
    this.favorited = false,
    required this.user,
    this.pics = const [],
    this.retweetedStatus,
    this.regionName,
    this.visibilityType,
    this.titleText,
    this.titleIcon,
    this.isTop = false,
    this.videoCoverUrl,
    this.videoStreamUrl,
    this.videoDuration,
    this.videoPlayCount = 0,
    this.videoTitle,
    this.videoQualityUrls,
    this.liveId,
    this.liveStatus,
    this.chaohuaTitle,
    this.chaohuaContainerId,
    this.chaohuaAvatar,
    this.urlStruct,
    this.poll,
    this.hotTopic,
    this.editCount = 0,
  });

  bool get hasPlayableVideoStream =>
      videoStreamUrl != null && videoStreamUrl!.isNotEmpty;
  bool get isLiveBroadcast => liveId != null && liveId!.isNotEmpty;
  bool get isLiveNow => isLiveBroadcast && liveStatus == 1;
  bool get isLiveNotStarted => isLiveBroadcast && liveStatus == 0;
  bool get isLiveEnded =>
      isLiveBroadcast && liveStatus != null && liveStatus != 0 && liveStatus != 1;
  bool get hasVideo => hasPlayableVideoStream || isLiveBroadcast;
  String get effectiveText =>
      (fullTextRaw != null && fullTextRaw!.isNotEmpty) ? fullTextRaw! : textRaw;
  bool get needsLongText =>
      isLongText && (fullTextRaw == null || fullTextRaw!.isEmpty);
  bool get isEdited => editCount > 0;

  String? get visibilityLabel {
    switch (visibilityType) {
      case 0:
        return '公开';
      case 10:
        return '仅粉丝可见';
      case 6:
        return '好友圈可见';
      case 1:
        return '仅自己可见';
      case 5:
        return '群可见';
      default:
        return null;
    }
  }

  static const String _base62Chars =
      '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// Converts a Weibo alphanumeric mblogid (e.g. "RgxuHaukX") into numeric mid (e.g. "5339420032499899").
  /// If input is already numeric or cannot be converted, returns input or converted string.
  static String mblogidToMid(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return trimmed;
    }

    try {
      String mid = '';
      for (int i = trimmed.length - 4; i > -4; i -= 4) {
        final offset1 = i < 0 ? 0 : i;
        final len = i < 0 ? trimmed.length % 4 : 4;
        final sub = trimmed.substring(offset1, offset1 + len);
        int val = 0;
        for (int j = 0; j < sub.length; j++) {
          final idx = _base62Chars.indexOf(sub[j]);
          if (idx == -1) return trimmed;
          val = val * 62 + idx;
        }
        var strVal = val.toString();
        if (offset1 > 0) {
          strVal = strVal.padLeft(7, '0');
        }
        mid = strVal + mid;
      }
      return mid.isNotEmpty ? mid : trimmed;
    } catch (_) {
      return trimmed;
    }
  }

  WeiboStatusModel copyWith({
    String? id,
    String? mid,
    String? mblogid,
    String? createdAt,
    String? textRaw,
    String? textHtml,
    String? fullTextRaw,
    bool? isLongText,
    String? source,
    int? repostsCount,
    int? commentsCount,
    int? attitudesCount,
    bool? liked,
    bool? favorited,
    WeiboUserModel? user,
    List<WeiboPicModel>? pics,
    WeiboStatusModel? retweetedStatus,
    String? regionName,
    int? visibilityType,
    String? titleText,
    String? titleIcon,
    bool? isTop,
    String? videoCoverUrl,
    String? videoStreamUrl,
    String? videoDuration,
    int? videoPlayCount,
    String? videoTitle,
    Map<String, String>? videoQualityUrls,
    String? liveId,
    int? liveStatus,
    String? chaohuaTitle,
    String? chaohuaContainerId,
    String? chaohuaAvatar,
    List<Map<String, dynamic>>? urlStruct,
    WeiboPollModel? poll,
    WeiboHotTopicModel? hotTopic,
    int? editCount,
  }) {
    return WeiboStatusModel(
      id: id ?? this.id,
      mid: mid ?? this.mid,
      mblogid: mblogid ?? this.mblogid,
      createdAt: createdAt ?? this.createdAt,
      textRaw: textRaw ?? this.textRaw,
      textHtml: textHtml ?? this.textHtml,
      fullTextRaw: fullTextRaw ?? this.fullTextRaw,
      isLongText: isLongText ?? this.isLongText,
      source: source ?? this.source,
      repostsCount: repostsCount ?? this.repostsCount,
      commentsCount: commentsCount ?? this.commentsCount,
      attitudesCount: attitudesCount ?? this.attitudesCount,
      liked: liked ?? this.liked,
      favorited: favorited ?? this.favorited,
      user: user ?? this.user,
      pics: pics ?? this.pics,
      retweetedStatus: retweetedStatus ?? this.retweetedStatus,
      regionName: regionName ?? this.regionName,
      visibilityType: visibilityType ?? this.visibilityType,
      titleText: titleText ?? this.titleText,
      titleIcon: titleIcon ?? this.titleIcon,
      isTop: isTop ?? this.isTop,
      videoCoverUrl: videoCoverUrl ?? this.videoCoverUrl,
      videoStreamUrl: videoStreamUrl ?? this.videoStreamUrl,
      videoDuration: videoDuration ?? this.videoDuration,
      videoPlayCount: videoPlayCount ?? this.videoPlayCount,
      videoTitle: videoTitle ?? this.videoTitle,
      videoQualityUrls: videoQualityUrls ?? this.videoQualityUrls,
      liveId: liveId ?? this.liveId,
      liveStatus: liveStatus ?? this.liveStatus,
      chaohuaTitle: chaohuaTitle ?? this.chaohuaTitle,
      chaohuaContainerId: chaohuaContainerId ?? this.chaohuaContainerId,
      chaohuaAvatar: chaohuaAvatar ?? this.chaohuaAvatar,
      urlStruct: urlStruct ?? this.urlStruct,
      poll: poll ?? this.poll,
      hotTopic: hotTopic ?? this.hotTopic,
      editCount: editCount ?? this.editCount,
    );
  }

  factory WeiboStatusModel.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'] as Map<String, dynamic>? ?? {};
    final user = WeiboUserModel.fromJson(userJson);

    // Parse Pictures
    final picInfos = json['pic_infos'] as Map<String, dynamic>?;
    final picIds = json['pic_ids'] as List? ?? (picInfos?.keys.toList() ?? []);
    final pics = <WeiboPicModel>[];

    if (picInfos != null && picInfos.isNotEmpty) {
      for (final pid in picIds) {
        final info = picInfos[pid.toString()];
        if (info is Map<String, dynamic>) {
          pics.add(WeiboPicModel.fromJson({...info, 'pid': pid.toString()}));
        }
      }
    } else {
      for (final pid in picIds) {
        pics.add(WeiboPicModel.fromJson({'pid': pid.toString()}));
      }
    }

    // Parse mix_media_info (Multi-video / Mixed Media)
    final mixMediaInfo = json['mix_media_info'];
    if (mixMediaInfo is Map && mixMediaInfo['items'] is List) {
      final items = mixMediaInfo['items'] as List;
      for (final item in items) {
        if (item is Map) {
          final itemType = item['type']?.toString().toLowerCase();
          final itemData = item['data'] as Map<String, dynamic>?;
          if (itemData != null) {
            if (itemType == 'video') {
              final mediaInfo = itemData['media_info'] as Map<String, dynamic>?;
              String? vUrl;
              if (mediaInfo != null) {
                final playbackList = mediaInfo['playback_list'];
                if (playbackList is List && playbackList.isNotEmpty) {
                  for (final p in playbackList) {
                    if (p is Map && p['play_info'] is Map) {
                      final pi = p['play_info'] as Map<String, dynamic>;
                      final url = pi['url']?.toString();
                      if (url != null && url.isNotEmpty) {
                        final label = pi['label']?.toString().toLowerCase();
                        if (label == 'mp4_720p' ||
                            label == 'mp4_1080p' ||
                            label == 'mp4_hd' ||
                            label == 'mp4_2160p60') {
                          vUrl = url;
                          break;
                        } else if (vUrl == null) {
                          vUrl = url;
                        }
                      }
                    }
                  }
                }
                vUrl ??= mediaInfo['mp4_720p_mp4']?.toString() ??
                    mediaInfo['stream_url_hd']?.toString() ??
                    mediaInfo['stream_url']?.toString() ??
                    mediaInfo['h5_url']?.toString();
              }
              if (vUrl != null && vUrl.startsWith('http://')) {
                vUrl = vUrl.replaceFirst('http://', 'https://');
              }

              final cover = itemData['page_pic']?.toString() ??
                  itemData['pic_info']?['pic_big']?['url']?.toString() ??
                  itemData['pic_info']?['pic_middle']?['url']?.toString() ??
                  '';
              final title = itemData['page_title']?.toString() ?? '';
              final dur = mediaInfo?['duration'];
              String? durStr;
              if (dur is num && dur > 0) {
                final dInt = dur.toInt();
                final m = (dInt ~/ 60).toString().padLeft(2, '0');
                final s = (dInt % 60).toString().padLeft(2, '0');
                durStr = '$m:$s';
              } else if (dur is String && dur.isNotEmpty) {
                durStr = dur;
              }

              final geo = itemData['pic_info']?['pic_big']
                      as Map<String, dynamic>? ??
                  itemData['pic_info']?['pic_middle'] as Map<String, dynamic>?;
              final w = geo?['width'] ?? 0;
              final h = geo?['height'] ?? 0;

              pics.add(WeiboPicModel(
                pid: item['id']?.toString() ?? '',
                thumbnail: cover,
                large: cover,
                original: cover,
                width: double.tryParse(w.toString()) ?? 0,
                height: double.tryParse(h.toString()) ?? 0,
                isVideo: true,
                videoUrl: vUrl,
                videoDuration: durStr,
                videoTitle: title,
              ));
            } else if (itemType == 'pic') {
              final picInfo = itemData['pic_info'] as Map<String, dynamic>?;
              if (picInfo != null) {
                pics.add(WeiboPicModel.fromJson(
                    {...picInfo, 'pid': item['id']?.toString() ?? ''}));
              }
            }
          }
        }
      }
    }

    // Parse Retweeted Status if present
    WeiboStatusModel? retweeted;
    if (json['retweeted_status'] is Map<String, dynamic>) {
      retweeted = WeiboStatusModel.fromJson(
          json['retweeted_status'] as Map<String, dynamic>);
    }

    final rawSource = json['source']?.toString() ?? '';
    final cleanSource = rawSource.replaceAll(RegExp(r'<[^>]*>'), '');

    // Parse Title (e.g. 赞了这条微博 / 转发了微博)
    String? titleText;
    String? titleIcon;
    if (json['title'] is Map) {
      titleText = json['title']['text']?.toString();
      titleIcon = json['title']['icon_url']?.toString() ??
          json['title']['struct_url']?.toString();
    } else if (json['title'] is String &&
        (json['title'] as String).isNotEmpty) {
      titleText = json['title'] as String;
    }

    // Parse Top/Pinned status
    final isTop = json['isTop'] == 1 ||
        json['isTop'] == true ||
        json['is_top'] == 1 ||
        json['is_top'] == true ||
        json['top'] == 1 ||
        json['top'] == true ||
        json['tag']?.toString().contains('置顶') == true ||
        (titleText != null && titleText.contains('置顶'));

    // Parse Video Metadata (from page_info or video dict)
    String? videoCover;
    String? videoStream;
    String? videoDuration;
    int videoPlayCount = 0;
    String? videoTitle;
    final Map<String, String> videoQualityMap = {};

    final rawUrlStructList = json['url_struct'] as List? ?? [];
    final typedUrlStruct = rawUrlStructList
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final liveId = _extractLiveId({
      'live_id': json['live_id'],
      'liveId': json['liveId'],
      'live': json['live'],
      'live_info': json['live_info'],
      'page_info': json['page_info'],
      'card_info': json['card_info'],
      'url_struct': typedUrlStruct,
    });
    int? liveStatus = _liveStatusFromValue(json['live_status']) ??
        _liveStatusFromValue(json['liveStatus']);
    for (final key in const ['live', 'live_info', 'wblive', 'live_room']) {
      final liveInfo = json[key];
      if (liveInfo is Map) {
        liveStatus ??= _liveStatusFromValue(liveInfo['status']) ??
            _liveStatusFromValue(liveInfo['live_status']) ??
            _liveStatusFromValue(liveInfo['liveStatus']);
      }
    }
    final rawPageInfoForStatus = json['page_info'];
    if (rawPageInfoForStatus is Map) {
      final pageType =
          rawPageInfoForStatus['type']?.toString().toLowerCase() ?? '';
      final isLivePage = liveId != null ||
          pageType == 'live' ||
          pageType == 'wblive' ||
          pageType == 'live_video' ||
          pageType == 'livevideo';
      if (isLivePage) {
        liveStatus ??= _liveStatusFromValue(rawPageInfoForStatus['status']) ??
            _liveStatusFromValue(rawPageInfoForStatus['live_status']) ??
            _liveStatusFromValue(rawPageInfoForStatus['liveStatus']);
      }
    }

    final pageInfoRaw = json['page_info'];
    // A retweet wrapper can repeat the original post's page_info at the
    // wrapper level. That media belongs to retweeted_status and must not be
    // promoted to the author of the retweet, otherwise the same video is
    // rendered once outside and once inside the quoted card. Real media
    // attached to the wrapper through pic_infos/mix_media_info is still
    // parsed above and remains available.
    if (pageInfoRaw is Map && retweeted == null) {
      final pageInfo = pageInfoRaw as Map<String, dynamic>;
      final pType = pageInfo['type']?.toString().toLowerCase();
      final mediaInfoRaw = pageInfo['media_info'];
      final mediaInfo =
          mediaInfoRaw is Map ? mediaInfoRaw as Map<String, dynamic> : null;

      final isLivePage = liveId != null ||
          pType == 'live' ||
          pType == 'wblive' ||
          pType == 'live_video' ||
          pType == 'livevideo';
      if (pType == 'video' ||
          pType == 'media' ||
          mediaInfo != null ||
          isLivePage) {
        videoTitle = pageInfo['page_title']?.toString();

        final pagePic = pageInfo['page_pic'];
        if (pagePic is Map) {
          videoCover = pagePic['url']?.toString();
        } else if (pagePic is String) {
          videoCover = pagePic;
        }

        if (videoCover == null || videoCover.isEmpty) {
          final picInfo = pageInfo['pic_info'];
          if (picInfo is Map) {
            final picBig = picInfo['pic_big'];
            if (picBig is Map) {
              videoCover = picBig['url']?.toString();
            }
          }
        }

        if (mediaInfo != null) {
          // 1. First priority: Check playback_list which contains fully signed https URLs
          final playbackList = mediaInfo['playback_list'];
          if (playbackList is List && playbackList.isNotEmpty) {
            for (final p in playbackList) {
              if (p is Map && p['play_info'] is Map) {
                final pi = p['play_info'] as Map<String, dynamic>;
                final normalizedUrl = _normalizeMediaUrl(pi['url']);
                if (normalizedUrl != null && normalizedUrl.isNotEmpty) {
                  final label = pi['label']?.toString().toLowerCase() ?? '';
                  String qName = '标清';
                  if (label.contains('1080') || label.contains('fhd')) {
                    qName = '1080P 超清';
                  } else if (label.contains('720') || label.contains('hd')) {
                    qName = '720P 高清';
                  } else if (label.contains('480') || label.contains('sd')) {
                    qName = '480P 标清';
                  } else if (label.contains('360') || label.contains('ld')) {
                    qName = '360P 流畅';
                  } else {
                    qName = pi['quality_label']?.toString() ?? '默认画质';
                  }
                  videoQualityMap[qName] = normalizedUrl;

                  if (label == 'mp4_720p' ||
                      label == 'mp4_1080p' ||
                      label == 'mp4_hd') {
                    videoStream ??= normalizedUrl;
                  } else if (videoStream == null &&
                      (pi['mime']?.toString().contains('mp4') == true ||
                          pi['type'] == 1)) {
                    videoStream ??= normalizedUrl;
                  }
                }
              }
            }
          }

          // 2. Direct resolution streams
          if (mediaInfo['mp4_1080p_mp4'] != null) {
            final u = _normalizeMediaUrl(mediaInfo['mp4_1080p_mp4']);
            if (u != null) {
              videoQualityMap['1080P 超清'] = u;
              videoStream ??= u;
            }
          }
          if (mediaInfo['mp4_720p_mp4'] != null) {
            final u = _normalizeMediaUrl(mediaInfo['mp4_720p_mp4']);
            if (u != null) {
              videoQualityMap['720P 高清'] = u;
              videoStream ??= u;
            }
          }
          if (mediaInfo['stream_url_hd'] != null) {
            final u = _normalizeMediaUrl(mediaInfo['stream_url_hd']);
            if (u != null) {
              videoQualityMap['720P 高清'] ??= u;
              videoStream ??= u;
            }
          }
          if (mediaInfo['mp4_hd_url'] != null) {
            final u = _normalizeMediaUrl(mediaInfo['mp4_hd_url']);
            if (u != null) {
              videoQualityMap['720P 高清'] ??= u;
              videoStream ??= u;
            }
          }
          if (mediaInfo['stream_url'] != null) {
            final u = _normalizeMediaUrl(mediaInfo['stream_url']);
            if (u != null) {
              videoQualityMap['480P 标清'] ??= u;
              videoStream ??= u;
            }
          }
          if (mediaInfo['mp4_sd_url'] != null) {
            final u = _normalizeMediaUrl(mediaInfo['mp4_sd_url']);
            if (u != null) {
              videoQualityMap['480P 标清'] ??= u;
              videoStream ??= u;
            }
          }

          // Live posts use a separate live-room response. Some status
          // payloads already carry one of these fields; accept the direct
          // media URL but never the /l/wblive HTML page URL.
          if (liveStatus == null || liveStatus == 1) {
            for (final key in const [
              'live_origin_hls_url',
              'live_origin_flv_url',
              'hls_url',
              'm3u8_url',
              'play_url',
              'playback_url',
            ]) {
              final normalizedUrl = _normalizeMediaUrl(mediaInfo[key]);
              if (normalizedUrl != null) {
                videoQualityMap['直播'] ??= normalizedUrl;
                videoStream ??= normalizedUrl;
                break;
              }
            }
          }

          // 3. Normalize videoStream to HTTPS if it starts with http://
          if (videoStream != null && videoStream.startsWith('http://')) {
            videoStream = videoStream.replaceFirst('http://', 'https://');
          }

          final dur = mediaInfo['duration'];
          if (dur is int && dur > 0) {
            final m = (dur ~/ 60).toString().padLeft(2, '0');
            final s = (dur % 60).toString().padLeft(2, '0');
            videoDuration = '$m:$s';
          } else if (dur is num && dur > 0) {
            final dInt = dur.toInt();
            final m = (dInt ~/ 60).toString().padLeft(2, '0');
            final s = (dInt % 60).toString().padLeft(2, '0');
            videoDuration = '$m:$s';
          } else if (dur is String && dur.isNotEmpty) {
            videoDuration = dur;
          }

          final playCount =
              mediaInfo['play_count'] ?? mediaInfo['online_users_number'];
          if (playCount is int) {
            videoPlayCount = playCount;
          }
        }
      }
    } else if (json['video'] is Map) {
      final vMap = json['video'] as Map<String, dynamic>;
      videoStream = _normalizeMediaUrl(vMap['stream_url']) ??
          _normalizeMediaUrl(vMap['hls_url']) ??
          _normalizeMediaUrl(vMap['m3u8_url']) ??
          _normalizeMediaUrl(vMap['url']);
      if (videoStream != null && videoStream.isNotEmpty) {
        videoQualityMap['默认画质'] = videoStream;
      }
      videoCover = vMap['cover_url']?.toString() ??
          vMap['cover']?.toString() ??
          vMap['poster']?.toString();
    }

    final isLongText = json['isLongText'] == true ||
        json['isLongText'] == 1 ||
        json['is_long_text'] == true ||
        json['is_long_text'] == 1 ||
        json['continue_tag'] != null;

    final mblogid = json['mblogid']?.toString() ??
        json['idstr']?.toString() ??
        json['id']?.toString();
    final fullTextRaw = json['longTextContent_raw']?.toString() ??
        json['longTextContent']?.toString() ??
        json['full_text_raw']?.toString();
    final rawTextHtml = json['text']?.toString();
    final textHtml = rawTextHtml != null && rawTextHtml.contains('<img')
        ? rawTextHtml
        : null;
    // Some desktop responses expose the visibility only as title.text
    // (for example "公开") instead of the structured visible field.
    final visibilityType =
        _visibilityTypeFromJson(json) ?? _visibilityCodeFromValue(titleText);

    // Parse Chaohua from title_source, url_struct, or tag_struct
    String? chaohuaTitle = json['chaohua_title']?.toString();
    String? chaohuaCid = json['chaohua_containerid']?.toString();
    String? chaohuaAvatar = json['chaohua_avatar']?.toString();

    final titleSource = json['title_source'];
    if (titleSource is Map) {
      final name = titleSource['name']?.toString() ?? '';
      final url = titleSource['url']?.toString() ?? '';
      final img = titleSource['image']?.toString() ?? '';
      if (name.isNotEmpty) {
        chaohuaTitle = name;
        chaohuaAvatar = img.isNotEmpty ? img : chaohuaAvatar;
        final match = RegExp(r'(?:containerid|pageid)=(100808[0-9a-zA-Z]+)')
            .firstMatch(url);
        if (match != null) {
          chaohuaCid = match.group(1);
        }
      }
    }

    final poll = WeiboPollModel.fromStatusJson(
      json,
      creatorName: user.screenName,
    );
    final hotTopic = WeiboHotTopicModel.fromStatusJson(json);

    if (chaohuaCid == null || chaohuaCid.isEmpty) {
      for (final u in typedUrlStruct) {
        final pageId = u['page_id']?.toString() ?? '';
        final uTitle = u['url_title']?.toString() ?? '';
        final oriUrl = u['ori_url']?.toString() ?? '';
        if (pageId.startsWith('100808') ||
            oriUrl.contains('100808') ||
            uTitle.contains('超话')) {
          chaohuaTitle ??= uTitle.isNotEmpty ? uTitle : null;
          chaohuaCid = pageId.isNotEmpty
              ? pageId
              : RegExp(r'100808[0-9a-zA-Z]+').firstMatch(oriUrl)?.group(0);
          chaohuaAvatar ??= u['url_type_pic']?.toString();
          break;
        }
      }
    }

    final editCount = (json['edit_count'] is int)
        ? json['edit_count'] as int
        : (int.tryParse(json['edit_count']?.toString() ?? '') ??
            (json['is_edited'] == true ? 1 : 0));

    final rawId = json['id']?.toString() ?? json['idstr']?.toString() ?? '';
    final rawMid = json['mid']?.toString() ?? '';
    final numericMid = (rawMid.isNotEmpty && RegExp(r'^\d+$').hasMatch(rawMid))
        ? rawMid
        : (RegExp(r'^\d+$').hasMatch(rawId)
            ? rawId
            : mblogidToMid(mblogid ?? rawId));
    final effectiveId = RegExp(r'^\d+$').hasMatch(rawId)
        ? rawId
        : (numericMid.isNotEmpty ? numericMid : rawId);

    return WeiboStatusModel(
      id: effectiveId,
      mid: numericMid.isNotEmpty ? numericMid : rawMid,
      mblogid: mblogid,
      createdAt: json['created_at']?.toString() ?? '',
      textRaw: json['text_raw']?.toString() ?? json['text']?.toString() ?? '',
      textHtml: textHtml,
      fullTextRaw: fullTextRaw,
      isLongText: isLongText,
      source: cleanSource,
      repostsCount:
          json['reposts_count'] is int ? json['reposts_count'] as int : 0,
      commentsCount:
          json['comments_count'] is int ? json['comments_count'] as int : 0,
      attitudesCount:
          json['attitudes_count'] is int ? json['attitudes_count'] as int : 0,
      liked: json['liked'] == true ||
          json['attitudes_status'] == 1 ||
          (json['attitude_mask'] is int && (json['attitude_mask'] as int) > 0),
      favorited: json['favorited'] == true,
      user: user,
      pics: pics,
      retweetedStatus: retweeted,
      regionName: json['region_name']?.toString(),
      visibilityType: visibilityType,
      titleText: titleText,
      titleIcon: titleIcon,
      isTop: isTop,
      videoCoverUrl: videoCover,
      videoStreamUrl: videoStream,
      videoDuration: videoDuration,
      videoPlayCount: videoPlayCount,
      videoTitle: videoTitle,
      videoQualityUrls: videoQualityMap.isNotEmpty ? videoQualityMap : null,
      liveId: liveId,
      liveStatus: liveStatus,
      chaohuaTitle: chaohuaTitle,
      chaohuaContainerId: chaohuaCid,
      chaohuaAvatar: chaohuaAvatar,
      urlStruct: typedUrlStruct,
      poll: poll,
      hotTopic: hotTopic,
      editCount: editCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mid': mid,
      'mblogid': mblogid,
      'created_at': createdAt,
      'text_raw': textRaw,
      'text_html': textHtml,
      'full_text_raw': fullTextRaw,
      'is_long_text': isLongText,
      'source': source,
      'reposts_count': repostsCount,
      'comments_count': commentsCount,
      'attitudes_count': attitudesCount,
      'liked': liked,
      'favorited': favorited,
      'user': user.toJson(),
      'pics': pics.map((p) => p.toJson()).toList(),
      'retweeted_status': retweetedStatus?.toJson(),
      'region_name': regionName,
      'visibility_type': visibilityType,
      'title': titleText,
      'is_top': isTop,
      'video_cover': videoCoverUrl,
      'video_stream': videoStreamUrl,
      'video_duration': videoDuration,
      'video_play_count': videoPlayCount,
      'video_title': videoTitle,
      'live_id': liveId,
      'live_status': liveStatus,
      'chaohua_title': chaohuaTitle,
      'chaohua_containerid': chaohuaContainerId,
      'chaohua_avatar': chaohuaAvatar,
      'url_struct': urlStruct,
      'poll': poll?.toJson(),
      'hot_topic': hotTopic?.toJson(),
      'edit_count': editCount,
    };
  }
}
