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
  String get originalUrl => original.isNotEmpty ? original : (large.isNotEmpty ? large : bmiddleUrl);
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
        (orj960.isNotEmpty ? orj960 : (pid.isNotEmpty ? 'https://wx1.sinaimg.cn/large/$pid.jpg' : ''));
    final original = json['original']?['url']?.toString() ??
        json['largest']?['url']?.toString() ??
        json['mw2000']?['url']?.toString() ??
        (large.isNotEmpty ? large : (pid.isNotEmpty ? 'https://wx1.sinaimg.cn/large/$pid.jpg' : thumbnail));

    final geo = json['large']?['geo'] as Map<String, dynamic>? ?? json['geo'] as Map<String, dynamic>?;
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
        (json['video_url'] != null && json['video_url'].toString().isNotEmpty) ||
        (json['isVideo'] == true);

    final vUrl = json['video_url']?.toString() ?? json['videoUrl']?.toString();
    final vDur = json['video_duration']?.toString() ?? json['videoDuration']?.toString();
    final vTitle = json['video_title']?.toString() ?? json['videoTitle']?.toString();

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
      'type': isLivePhoto ? 'livephoto' : (isGif ? 'gif' : (isVideo ? 'video' : 'jpg')),
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
      id: json['id']?.toString() ?? json['idstr']?.toString() ?? json['uid']?.toString() ?? '',
      screenName: json['screen_name']?.toString() ?? json['name']?.toString() ?? json['nick']?.toString() ?? '匿名用户',
      avatar: json['avatar_hd']?.toString() ??
          json['avatar_large']?.toString() ??
          json['profile_image_url']?.toString() ??
          '',
      avatarHd: json['avatar_hd']?.toString() ?? '',
      verified: json['verified'] == true ||
          (json['verified_type'] is int && (json['verified_type'] as int) >= 0),
      verifiedType: json['verified_type'] is int ? json['verified_type'] as int : -1,
      verifiedReason: json['verified_reason']?.toString() ?? json['verified_detail']?['desc']?.toString() ?? '',
      description: json['description']?.toString() ?? json['verified_reason']?.toString() ?? '',
      followersCount: json['followers_count'] is int
          ? json['followers_count'] as int
          : (json['followers_count_str'] != null ? 0 : 0),
      friendsCount: json['friends_count'] is int
          ? json['friends_count'] as int
          : 0,
      statusesCount: json['statuses_count'] is int
          ? json['statuses_count'] as int
          : 0,
      following: json['following'] == true,
      followMe: json['follow_me'] == true,
      gender: json['gender']?.toString() ?? 'm',
      ipLocation: json['location']?.toString() ?? json['ip_location']?.toString() ?? '',
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
  final String? titleText;
  final String? titleIcon;
  final bool isTop;
  final String? videoCoverUrl;
  final String? videoStreamUrl;
  final String? videoDuration;
  final int videoPlayCount;
  final String? videoTitle;
  final Map<String, String>? videoQualityUrls;
  final String? chaohuaTitle;
  final String? chaohuaContainerId;
  final String? chaohuaAvatar;
  final List<Map<String, dynamic>>? urlStruct;
  final int editCount;

  const WeiboStatusModel({
    required this.id,
    required this.mid,
    this.mblogid,
    required this.createdAt,
    required this.textRaw,
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
    this.titleText,
    this.titleIcon,
    this.isTop = false,
    this.videoCoverUrl,
    this.videoStreamUrl,
    this.videoDuration,
    this.videoPlayCount = 0,
    this.videoTitle,
    this.videoQualityUrls,
    this.chaohuaTitle,
    this.chaohuaContainerId,
    this.chaohuaAvatar,
    this.urlStruct,
    this.editCount = 0,
  });

  bool get hasVideo => videoStreamUrl != null && videoStreamUrl!.isNotEmpty;
  String get effectiveText => (fullTextRaw != null && fullTextRaw!.isNotEmpty) ? fullTextRaw! : textRaw;
  bool get needsLongText => isLongText && (fullTextRaw == null || fullTextRaw!.isEmpty);
  bool get isEdited => editCount > 0;

  static const String _base62Chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

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
    String? titleText,
    String? titleIcon,
    bool? isTop,
    String? videoCoverUrl,
    String? videoStreamUrl,
    String? videoDuration,
    int? videoPlayCount,
    String? videoTitle,
    Map<String, String>? videoQualityUrls,
    String? chaohuaTitle,
    String? chaohuaContainerId,
    String? chaohuaAvatar,
    List<Map<String, dynamic>>? urlStruct,
    int? editCount,
  }) {
    return WeiboStatusModel(
      id: id ?? this.id,
      mid: mid ?? this.mid,
      mblogid: mblogid ?? this.mblogid,
      createdAt: createdAt ?? this.createdAt,
      textRaw: textRaw ?? this.textRaw,
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
      titleText: titleText ?? this.titleText,
      titleIcon: titleIcon ?? this.titleIcon,
      isTop: isTop ?? this.isTop,
      videoCoverUrl: videoCoverUrl ?? this.videoCoverUrl,
      videoStreamUrl: videoStreamUrl ?? this.videoStreamUrl,
      videoDuration: videoDuration ?? this.videoDuration,
      videoPlayCount: videoPlayCount ?? this.videoPlayCount,
      videoTitle: videoTitle ?? this.videoTitle,
      videoQualityUrls: videoQualityUrls ?? this.videoQualityUrls,
      chaohuaTitle: chaohuaTitle ?? this.chaohuaTitle,
      chaohuaContainerId: chaohuaContainerId ?? this.chaohuaContainerId,
      chaohuaAvatar: chaohuaAvatar ?? this.chaohuaAvatar,
      urlStruct: urlStruct ?? this.urlStruct,
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
                        if (label == 'mp4_720p' || label == 'mp4_1080p' || label == 'mp4_hd' || label == 'mp4_2160p60') {
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
                  itemData['pic_info']?['pic_middle']?['url']?.toString() ?? '';
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

              final geo = itemData['pic_info']?['pic_big'] as Map<String, dynamic>? ??
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
                pics.add(WeiboPicModel.fromJson({...picInfo, 'pid': item['id']?.toString() ?? ''}));
              }
            }
          }
        }
      }
    }

    // Parse Retweeted Status if present
    WeiboStatusModel? retweeted;
    if (json['retweeted_status'] is Map<String, dynamic>) {
      retweeted = WeiboStatusModel.fromJson(json['retweeted_status'] as Map<String, dynamic>);
    }

    final rawSource = json['source']?.toString() ?? '';
    final cleanSource = rawSource.replaceAll(RegExp(r'<[^>]*>'), '');

    // Parse Title (e.g. 赞了这条微博 / 转发了微博)
    String? titleText;
    String? titleIcon;
    if (json['title'] is Map) {
      titleText = json['title']['text']?.toString();
      titleIcon = json['title']['icon_url']?.toString() ?? json['title']['struct_url']?.toString();
    } else if (json['title'] is String && (json['title'] as String).isNotEmpty) {
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

    final pageInfoRaw = json['page_info'];
    if (pageInfoRaw is Map) {
      final pageInfo = pageInfoRaw as Map<String, dynamic>;
      final pType = pageInfo['type']?.toString().toLowerCase();
      final mediaInfoRaw = pageInfo['media_info'];
      final mediaInfo = mediaInfoRaw is Map ? mediaInfoRaw as Map<String, dynamic> : null;

      if (pType == 'video' || pType == 'media' || mediaInfo != null) {
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
                final url = pi['url']?.toString();
                if (url != null && url.isNotEmpty) {
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
                  final normalizedUrl = url.startsWith('http://') ? url.replaceFirst('http://', 'https://') : url;
                  videoQualityMap[qName] = normalizedUrl;

                  if (label == 'mp4_720p' || label == 'mp4_1080p' || label == 'mp4_hd') {
                    videoStream ??= normalizedUrl;
                  } else if (videoStream == null && (pi['mime']?.toString().contains('mp4') == true || pi['type'] == 1)) {
                    videoStream ??= normalizedUrl;
                  }
                }
              }
            }
          }

          // 2. Direct resolution streams
          if (mediaInfo['mp4_1080p_mp4'] != null) {
            final u = mediaInfo['mp4_1080p_mp4'].toString().replaceFirst('http://', 'https://');
            videoQualityMap['1080P 超清'] = u;
            videoStream ??= u;
          }
          if (mediaInfo['mp4_720p_mp4'] != null) {
            final u = mediaInfo['mp4_720p_mp4'].toString().replaceFirst('http://', 'https://');
            videoQualityMap['720P 高清'] = u;
            videoStream ??= u;
          }
          if (mediaInfo['stream_url_hd'] != null) {
            final u = mediaInfo['stream_url_hd'].toString().replaceFirst('http://', 'https://');
            videoQualityMap['720P 高清'] ??= u;
            videoStream ??= u;
          }
          if (mediaInfo['mp4_hd_url'] != null) {
            final u = mediaInfo['mp4_hd_url'].toString().replaceFirst('http://', 'https://');
            videoQualityMap['720P 高清'] ??= u;
            videoStream ??= u;
          }
          if (mediaInfo['stream_url'] != null) {
            final u = mediaInfo['stream_url'].toString().replaceFirst('http://', 'https://');
            videoQualityMap['480P 标清'] ??= u;
            videoStream ??= u;
          }
          if (mediaInfo['mp4_sd_url'] != null) {
            final u = mediaInfo['mp4_sd_url'].toString().replaceFirst('http://', 'https://');
            videoQualityMap['480P 标清'] ??= u;
            videoStream ??= u;
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

          final playCount = mediaInfo['play_count'] ?? mediaInfo['online_users_number'];
          if (playCount is int) {
            videoPlayCount = playCount;
          }
        }
      }
    } else if (json['video'] is Map) {
      final vMap = json['video'] as Map<String, dynamic>;
      videoStream = vMap['stream_url']?.toString() ?? vMap['url']?.toString();
      if (videoStream != null && videoStream.startsWith('http://')) {
        videoStream = videoStream.replaceFirst('http://', 'https://');
      }
      if (videoStream != null && videoStream.isNotEmpty) {
        videoQualityMap['默认画质'] = videoStream;
      }
      videoCover = vMap['cover_url']?.toString();
    }

    final isLongText = json['isLongText'] == true ||
        json['isLongText'] == 1 ||
        json['is_long_text'] == true ||
        json['is_long_text'] == 1 ||
        json['continue_tag'] != null;

    final mblogid = json['mblogid']?.toString() ?? json['idstr']?.toString() ?? json['id']?.toString();
    final fullTextRaw = json['longTextContent_raw']?.toString() ??
        json['longTextContent']?.toString() ??
        json['full_text_raw']?.toString();

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
        final match = RegExp(r'(?:containerid|pageid)=(100808[0-9a-zA-Z]+)').firstMatch(url);
        if (match != null) {
          chaohuaCid = match.group(1);
        }
      }
    }

    final rawUrlStructList = json['url_struct'] as List? ?? [];
    final typedUrlStruct = rawUrlStructList
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    if (chaohuaCid == null || chaohuaCid.isEmpty) {
      for (final u in typedUrlStruct) {
        final pageId = u['page_id']?.toString() ?? '';
        final uTitle = u['url_title']?.toString() ?? '';
        final oriUrl = u['ori_url']?.toString() ?? '';
        if (pageId.startsWith('100808') || oriUrl.contains('100808') || uTitle.contains('超话')) {
          chaohuaTitle ??= uTitle.isNotEmpty ? uTitle : null;
          chaohuaCid = pageId.isNotEmpty ? pageId : RegExp(r'100808[0-9a-zA-Z]+').firstMatch(oriUrl)?.group(0);
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
        : (RegExp(r'^\d+$').hasMatch(rawId) ? rawId : mblogidToMid(mblogid ?? rawId));
    final effectiveId = RegExp(r'^\d+$').hasMatch(rawId)
        ? rawId
        : (numericMid.isNotEmpty ? numericMid : rawId);

    return WeiboStatusModel(
      id: effectiveId,
      mid: numericMid.isNotEmpty ? numericMid : rawMid,
      mblogid: mblogid,
      createdAt: json['created_at']?.toString() ?? '',
      textRaw: json['text_raw']?.toString() ?? json['text']?.toString() ?? '',
      fullTextRaw: fullTextRaw,
      isLongText: isLongText,
      source: cleanSource,
      repostsCount: json['reposts_count'] is int ? json['reposts_count'] as int : 0,
      commentsCount: json['comments_count'] is int ? json['comments_count'] as int : 0,
      attitudesCount: json['attitudes_count'] is int ? json['attitudes_count'] as int : 0,
      liked: json['liked'] == true || json['attitudes_status'] == 1 || (json['attitude_mask'] is int && (json['attitude_mask'] as int) > 0),
      favorited: json['favorited'] == true,
      user: user,
      pics: pics,
      retweetedStatus: retweeted,
      regionName: json['region_name']?.toString(),
      titleText: titleText,
      titleIcon: titleIcon,
      isTop: isTop,
      videoCoverUrl: videoCover,
      videoStreamUrl: videoStream,
      videoDuration: videoDuration,
      videoPlayCount: videoPlayCount,
      videoTitle: videoTitle,
      videoQualityUrls: videoQualityMap.isNotEmpty ? videoQualityMap : null,
      chaohuaTitle: chaohuaTitle,
      chaohuaContainerId: chaohuaCid,
      chaohuaAvatar: chaohuaAvatar,
      urlStruct: typedUrlStruct,
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
      'title': titleText,
      'is_top': isTop,
      'video_cover': videoCoverUrl,
      'video_stream': videoStreamUrl,
      'video_duration': videoDuration,
      'video_play_count': videoPlayCount,
      'video_title': videoTitle,
      'chaohua_title': chaohuaTitle,
      'chaohua_containerid': chaohuaContainerId,
      'chaohua_avatar': chaohuaAvatar,
      'url_struct': urlStruct,
      'edit_count': editCount,
    };
  }
}
