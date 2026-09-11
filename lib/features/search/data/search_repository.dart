import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../feed/data/models/weibo_status_model.dart';
import 'models/weibo_topic_header_model.dart';

class HotSearchItem {
  final int rank;
  final String word;
  final int num;
  final String? labelName;
  final String? icon;
  final String? category;
  final bool isPinned;
  final bool isRanked;
  final String? locationLabel;
  final bool isHot;
  final bool isNew;
  final bool isBoom;
  final bool isFei;

  const HotSearchItem({
    required this.rank,
    required this.word,
    required this.num,
    this.labelName,
    this.icon,
    this.category,
    this.isPinned = false,
    this.isRanked = true,
    this.locationLabel,
    this.isHot = false,
    this.isNew = false,
    this.isBoom = false,
    this.isFei = false,
  });

  factory HotSearchItem.fromJson(
    Map<String, dynamic> json,
    int index, {
    bool isPinned = false,
  }) {
    final realPos = _asInt(json['realpos']);
    final isRanked = realPos != null && realPos > 0;
    final descriptionValue = json['description'];
    final description = _firstNonEmptyString([descriptionValue]);
    final locationLabel =
        descriptionValue is String && description != null ? description : null;
    final label = _firstNonEmptyString([
      json['label_name'],
      json['icon_desc'],
      json['small_icon_desc'],
      json['flag_desc'],
    ]);
    final cat = _firstNonEmptyString([
      json['m_category'],
      json['category'],
      json['channel_type'],
    ]);
    final labelStr = label;

    return HotSearchItem(
      rank: realPos ?? _asInt(json['rank']) ?? index + 1,
      word: json['word']?.toString() ?? json['note']?.toString() ?? '',
      num: _asInt(json['num']) ??
          _asInt(json['raw_hot']) ??
          _asInt(descriptionValue) ??
          0,
      labelName: labelStr,
      icon: _firstNonEmptyString([json['icon'], json['icon_url']]),
      category: cat,
      isPinned: isPinned || json['is_gov'] == 1 || json['is_pinned'] == 1,
      isRanked: isRanked,
      locationLabel: !isRanked ? locationLabel : null,
      isHot: labelStr == '热' || json['is_hot'] == 1,
      isNew: labelStr == '新' || json['is_new'] == 1,
      isBoom: labelStr == '爆' || json['is_boom'] == 1,
      isFei: labelStr == '沸',
    );
  }

  static String? _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}

/// 搜索联想结果模型（包含匹配用户直达与联想词）
class SearchSuggestResult {
  final List<WeiboUserModel> users;
  final List<String> suggestions;

  const SearchSuggestResult({
    this.users = const [],
    this.suggestions = const [],
  });
}

/// 微博网页端发布器使用的主题联想项。
class WeiboTopicSuggestion {
  final String word;
  final int discussionCount;
  final bool isSuperTopic;
  final String topicId;

  const WeiboTopicSuggestion({
    required this.word,
    this.discussionCount = 0,
    this.isSuperTopic = false,
    this.topicId = '',
  });
}

/// 微博网页端地点选择器返回的 POI。
class SearchPlaceItem {
  final String poiid;
  final String title;
  final String pcTitle;
  final String clientShow;
  final String longitude;
  final String latitude;
  final int spotType;
  final double? distanceMeters;

  const SearchPlaceItem({
    required this.poiid,
    required this.title,
    this.pcTitle = '',
    this.clientShow = '',
    this.longitude = '',
    this.latitude = '',
    this.spotType = 0,
    this.distanceMeters,
  });

  factory SearchPlaceItem.fromJson(Map<String, dynamic> json) {
    return SearchPlaceItem(
      poiid: json['poiid']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? json['name']?.toString() ?? '',
      pcTitle: json['pc_title']?.toString() ?? '',
      clientShow: json['client_show']?.toString() ?? '',
      longitude: json['lon']?.toString() ?? json['longitude']?.toString() ?? '',
      latitude: json['lat']?.toString() ?? json['latitude']?.toString() ?? '',
      spotType: int.tryParse(json['spot_type']?.toString() ?? '') ?? 0,
      distanceMeters: _parseDistance(json['distance'] ?? json['distance_m']),
    );
  }

  static double? _parseDistance(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  SearchPlaceItem copyWith({double? distanceMeters}) {
    return SearchPlaceItem(
      poiid: poiid,
      title: title,
      pcTitle: pcTitle,
      clientShow: clientShow,
      longitude: longitude,
      latitude: latitude,
      spotType: spotType,
      distanceMeters: distanceMeters ?? this.distanceMeters,
    );
  }
}

class WeiboMovieItem {
  final String filmId;
  final String title;
  final String poster;
  final String description;

  const WeiboMovieItem({
    required this.filmId,
    required this.title,
    this.poster = '',
    this.description = '',
  });

  factory WeiboMovieItem.fromJson(Map<String, dynamic> json) {
    return WeiboMovieItem(
      filmId: json['film_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['name']?.toString() ?? json['title']?.toString() ?? '',
      poster: json['poster']?.toString() ??
          json['poster_url']?.toString() ??
          json['pic']?.toString() ??
          '',
      description: json['release_date']?.toString() ??
          json['score']?.toString() ??
          json['description']?.toString() ??
          '',
    );
  }
}

class WeiboMonographItem {
  final String id;
  final String url;
  final String title;
  final String summary;
  final String cover;

  const WeiboMonographItem({
    required this.id,
    required this.url,
    required this.title,
    this.summary = '',
    this.cover = '',
  });

  factory WeiboMonographItem.fromJson(Map<String, dynamic> json) {
    return WeiboMonographItem(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
    );
  }
}

/// 搜索超话结果模型
class SearchChaohuaItem {
  final String title;
  final String pageId;
  final String topicId;
  final String image;
  final String description;

  const SearchChaohuaItem({
    required this.title,
    required this.pageId,
    this.topicId = '',
    required this.image,
    required this.description,
  });

  factory SearchChaohuaItem.fromJson(Map<String, dynamic> json) {
    final topicId = json['oid']?.toString() ??
        json['topic_id']?.toString() ??
        json['page_id']?.toString() ??
        '';
    return SearchChaohuaItem(
      title: json['title']?.toString() ?? '',
      pageId: json['page_id']?.toString() ?? topicId,
      topicId: topicId,
      image: json['image']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
    );
  }
}

/// 搜索微博多维结果模型 (包含微博流、词条介绍卡片、置顶博文与热门官方账号)
class SearchStatusesResult {
  final List<WeiboStatusModel> statuses;
  final WeiboTopicHeaderModel? topicHeader;
  final WeiboStatusModel? toppingStatus;
  final List<WeiboUserModel> hotOfficialUsers;

  const SearchStatusesResult({
    required this.statuses,
    this.topicHeader,
    this.toppingStatus,
    this.hotOfficialUsers = const [],
  });
}

/// Search Repository for Hot Search List and Keyword Search
class SearchRepository {
  final WeiboDioClient _client;

  SearchRepository(this._client);

  /// 获取网页端热搜总榜。
  ///
  /// /ajax/side/hotSearch 是网页 /hot/search 实际使用的接口，
  /// hot_band 仅作为接口临时不可用时的官方兼容回退。
  Future<List<HotSearchItem>> getHotSearch() async {
    final primary = await _fetchOfficialHotList(ApiConstants.hotSearch);
    if (primary.isNotEmpty) return primary;
    return _fetchOfficialHotList(ApiConstants.hotBand);
  }

  Future<List<HotSearchItem>> _fetchOfficialHotList(String endpoint) async {
    try {
      final response = await _client.dio.get(endpoint);
      if (response.data is! Map<String, dynamic>) return [];

      final payload = response.data as Map<String, dynamic>;
      final data = payload['data'];
      if (data is! Map<String, dynamic>) return [];

      // /hot/search and /hot/mine use realtime; category pages use band_list.
      final rawList =
          data['realtime'] is List ? data['realtime'] : data['band_list'];
      if (rawList is! List) return [];

      final rankedItems = rawList
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
          .asMap()
          .entries
          .map((entry) => HotSearchItem.fromJson(entry.value, entry.key))
          .where((item) => item.word.isNotEmpty)
          .toList();

      // 网页端会把 hotgov/hotgovs 单独展示在实时榜单之前。
      final pinnedItems = <HotSearchItem>[];
      final rawPinnedList = data['hotgovs'];
      if (rawPinnedList is List) {
        for (final rawItem in rawPinnedList.whereType<Map>()) {
          final item = HotSearchItem.fromJson(
            Map<String, dynamic>.from(rawItem),
            pinnedItems.length,
            isPinned: true,
          );
          if (item.word.isNotEmpty &&
              !pinnedItems.any((pinned) => pinned.word == item.word)) {
            pinnedItems.add(item);
          }
        }
      }

      final rawPinnedItem = data['hotgov'];
      if (rawPinnedItem is Map) {
        final item = HotSearchItem.fromJson(
          Map<String, dynamic>.from(rawPinnedItem),
          pinnedItems.length,
          isPinned: true,
        );
        if (item.word.isNotEmpty &&
            !pinnedItems.any((pinned) => pinned.word == item.word) &&
            !rankedItems.any((ranked) => ranked.word == item.word)) {
          pinnedItems.add(item);
        }
      }

      return [...pinnedItems, ...rankedItems];
    } catch (_) {
      return [];
    }
  }

  /// 获取网页端对应分类的热搜榜单，保持官方返回顺序，不做本地筛选或拼接。
  ///
  /// 网页端没有同城热搜页，因此未映射的分类返回空列表，避免展示伪造的榜单。
  Future<List<HotSearchItem>> getCategoryHotSearch(String categoryKey) async {
    final endpoint = ApiConstants.hotTrendCategoryEndpoints[categoryKey];
    if (endpoint == null) return [];
    return _fetchOfficialHotList(endpoint);
  }

  /// 搜索联想与用户直达接口 (/ajax/side/search)
  Future<SearchSuggestResult> getSearchSuggestions(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return const SearchSuggestResult();

    try {
      final response = await _client.dio.get(
        ApiConstants.searchSuggest,
        queryParameters: {'q': clean},
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data['data'];
        if (data is Map<String, dynamic>) {
          final rawUsers =
              data['users'] as List? ?? data['user'] as List? ?? [];
          final users = rawUsers
              .whereType<Map<String, dynamic>>()
              .map((u) => WeiboUserModel.fromJson(u))
              .where((u) => u.id.isNotEmpty && u.screenName != '匿名用户')
              .toList();

          // If no user was matched in search suggest, attempt exact screen_name lookup
          if (users.isEmpty && clean.isNotEmpty) {
            final cleanScreenName =
                clean.startsWith('@') ? clean.substring(1).trim() : clean;
            if (cleanScreenName.isNotEmpty) {
              try {
                final directRes = await _client.dio.get(
                  '/ajax/profile/info',
                  queryParameters: {'screen_name': cleanScreenName},
                  options: Options(headers: {'Referer': 'https://weibo.com/'}),
                );
                if (directRes.data is Map<String, dynamic> &&
                    directRes.data['ok'] == 1) {
                  final uJson = directRes.data['data']?['user'];
                  if (uJson is Map<String, dynamic>) {
                    final directUser = WeiboUserModel.fromJson(uJson);
                    if (directUser.id.isNotEmpty) {
                      users.add(directUser);
                    }
                  }
                }
              } catch (_) {}
            }
          }

          final rawSuggestions =
              data['query_relates'] as List? ?? data['hotquery'] as List? ?? [];
          final suggestions = rawSuggestions
              .map((s) =>
                  s is Map ? (s['word']?.toString() ?? '') : s.toString())
              .where((s) => s.isNotEmpty)
              .toList();

          return SearchSuggestResult(users: users, suggestions: suggestions);
        }
      }
    } catch (_) {}

    return const SearchSuggestResult();
  }

  /// 获取网页端发布器的“想用什么话题”联想结果。
  Future<List<WeiboTopicSuggestion>> getTopicSuggestions(String query) async {
    final clean = query.trim().replaceAll('#', '');
    if (clean.isEmpty) return [];

    try {
      final response = await _client.dio.get(
        ApiConstants.searchSuggest,
        queryParameters: {'q': clean, 'type': 'topic'},
      );
      final data = response.data is Map ? response.data['data'] : null;
      if (data is! Map) return [];

      final raw = <dynamic>[];
      if (data['hotquery'] is List) raw.addAll(data['hotquery'] as List);
      if (data['query_relates'] is List) {
        raw.addAll(data['query_relates'] as List);
      }

      final result = <WeiboTopicSuggestion>[];
      final seen = <String>{};
      for (final item in raw) {
        final map = item is Map ? item : const <String, dynamic>{};
        final word = (map['suggestion'] ?? map['word'] ?? map['query'] ?? item)
            .toString()
            .trim()
            .replaceAll(RegExp(r'^#+|#+$'), '');
        if (word.isEmpty || !seen.add(word)) continue;
        final isSuper = word.endsWith('[超话]') ||
            map['is_super_topic'] == 1 ||
            map['topic_type']?.toString() == 'super';
        result.add(
          WeiboTopicSuggestion(
            word: word.replaceFirst(RegExp(r'\[超话\]$'), '').trim(),
            discussionCount: int.tryParse(
                  (map['discuss_num'] ?? map['discuss'] ?? map['count'] ?? '')
                      .toString(),
                ) ??
                0,
            isSuperTopic: isSuper,
            topicId: (map['oid'] ?? map['topic_id'] ?? map['page_id'] ?? '')
                .toString(),
          ),
        );
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// 获取微博网页端地点选择器的附近/关键词 POI。
  ///
  /// 微博网页端的真实接口只有 q/page 参数；设备坐标不伪装成未公开的
  /// 服务端参数，而是在收到官方 POI 结果后按 POI 坐标做本地距离排序。
  Future<List<SearchPlaceItem>> searchPlaces(
    String query, {
    int page = 1,
    double? latitude,
    double? longitude,
  }) async {
    final clean = query.trim();

    try {
      final response = await _client.dio.get(
        '/ajax/statuses/place',
        queryParameters: {'q': clean, 'page': page},
      );
      final data = response.data is Map ? response.data['data'] : null;
      final raw = data is Map ? data['pois'] : null;
      if (raw is! List) return [];
      var places = raw
          .whereType<Map>()
          .map((item) =>
              SearchPlaceItem.fromJson(Map<String, dynamic>.from(item)))
          .where((place) => place.title.isNotEmpty)
          .toList();
      if (latitude == null || longitude == null) return places;

      places = places
          .map(
            (place) => place.copyWith(
              distanceMeters: place.distanceMeters ??
                  _distanceMeters(
                    latitude,
                    longitude,
                    double.tryParse(place.latitude),
                    double.tryParse(place.longitude),
                  ),
            ),
          )
          .toList();
      places.sort((a, b) {
        final aDistance = a.distanceMeters;
        final bDistance = b.distanceMeters;
        if (aDistance == null && bDistance == null) return 0;
        if (aDistance == null) return 1;
        if (bDistance == null) return -1;
        return aDistance.compareTo(bDistance);
      });
      return places;
    } catch (_) {
      return [];
    }
  }

  static double? _distanceMeters(
    double? fromLatitude,
    double? fromLongitude,
    double? toLatitude,
    double? toLongitude,
  ) {
    if (fromLatitude == null ||
        fromLongitude == null ||
        toLatitude == null ||
        toLongitude == null) {
      return null;
    }
    const earthRadiusMeters = 6371000.0;
    final latitudeDelta = _radians(toLatitude - fromLatitude);
    final longitudeDelta = _radians(toLongitude - fromLongitude);
    final fromLatitudeRadians = _radians(fromLatitude);
    final toLatitudeRadians = _radians(toLatitude);
    final a = math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(fromLatitudeRadians) *
            math.cos(toLatitudeRadians) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    final safeA = a.clamp(0.0, 1.0).toDouble();
    return 2 *
        earthRadiusMeters *
        math.atan2(math.sqrt(safeA), math.sqrt(1 - safeA));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  Future<List<WeiboMovieItem>> searchMovies(String query) async {
    final clean = query.trim();
    try {
      final response = await _client.dio.get(
        '/ajax/movie/${clean.isEmpty ? 'hot_top' : 'hot_search'}',
        queryParameters: clean.isEmpty ? {'type': 'hotshow'} : {'k': clean},
      );
      final data = response.data is Map ? response.data['data'] : null;
      final raw = data is Map && data['list'] is List ? data['list'] : data;
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((item) =>
              WeiboMovieItem.fromJson(Map<String, dynamic>.from(item)))
          .where((movie) => movie.filmId.isNotEmpty && movie.title.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<WeiboMonographItem>> getMonographs({int page = 1}) async {
    try {
      final response = await _client.dio.get(
        '/ajax/monograph/list',
        queryParameters: {'page': page},
      );
      final data = response.data is Map ? response.data['data'] : null;
      final raw = data is Map ? data['list'] : null;
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((item) =>
              WeiboMonographItem.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<SearchStatusesResult> searchStatusesWithDetails({
    required String keyword,
    int page = 1,
  }) async {
    final cleanK = keyword.replaceAll('#', '').trim();
    if (cleanK.isEmpty) return const SearchStatusesResult(statuses: []);

    final isTopicKeyword = keyword.startsWith('#') ||
        keyword.endsWith('#') ||
        cleanK.contains(RegExp(r'vs|VS|对战|PK|pk|与|和|战胜|击败'));
    final sQuery = isTopicKeyword ? '#$cleanK#' : keyword;

    // 1. 直连微博原生 s.weibo.com 综合搜索引擎 (微博网页端 1:1 真实排序与推荐)
    try {
      final sFuture = _client.dio.get<String>(
        'https://s.weibo.com/weibo',
        queryParameters: {'q': sQuery, 'page': page},
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Referer': 'https://s.weibo.com/',
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
        ),
      );

      // 第一页并发获取官方 topicHeads 元数据 (导语、封面大图、主持人及阅读讨论量)
      final topicFuture = page == 1
          ? _client.dio
              .get(
                ApiConstants.searchStatuses,
                queryParameters: {
                  'q': isTopicKeyword ? '#$cleanK#' : cleanK,
                  'page': 1
                },
              )
              .then<Map<String, dynamic>?>((res) =>
                  res.data is Map<String, dynamic>
                      ? res.data as Map<String, dynamic>
                      : null)
              .catchError((_) => null)
          : Future<Map<String, dynamic>?>.value(null);

      final responses = await Future.wait([
        sFuture,
        topicFuture,
      ]);

      final sResponse = responses[0] as Response<String>;
      final sHtml = sResponse.data?.toString() ?? '';
      final ajaxData = responses[1] as Map<String, dynamic>?;

      WeiboTopicHeaderModel? topicHeader;
      if (ajaxData != null && ajaxData['topicHeads'] is Map<String, dynamic>) {
        try {
          topicHeader = WeiboTopicHeaderModel.fromTopicHeads(
            ajaxData['topicHeads'] as Map<String, dynamic>,
          );
        } catch (_) {}
      }

      // 解析 s.weibo.com 页面卡片
      final cardReg = RegExp(
        r'<div class="card-wrap"[\s\S]*?(?=<div class="card-wrap"|<!--/card-wrap-->|$)',
        caseSensitive: false,
      );
      final allCards = cardReg.allMatches(sHtml).toList();

      final parsedCards =
          <({String mid, bool isTop, bool isHot, String nick})>[];
      for (final card in allCards) {
        final block = card.group(0) ?? '';
        final mid = RegExp(r'mid="(\d+)"').firstMatch(block)?.group(1);
        if (mid == null || parsedCards.any((m) => m.mid == mid)) continue;

        final cardTopMatch =
            RegExp(r'<div class="card-top"[^>]*>([\s\S]*?)</div>')
                .firstMatch(block);
        final cardTop = cardTopMatch?.group(1) ?? '';
        final isTop = cardTop.contains('置顶') ||
            block.contains('icon-top') ||
            block.contains('label-top');
        final isHot = cardTop.contains('热门') ||
            cardTop.contains('icon-star') ||
            cardTop.contains('icon-hot');
        final nick =
            RegExp(r'nick-name="([^"]+)"').firstMatch(block)?.group(1) ?? '';

        parsedCards.add((mid: mid, isTop: isTop, isHot: isHot, nick: nick));
      }

      if (parsedCards.isNotEmpty) {
        // 单页并发拉取完整微博详情 (原生 /ajax/statuses/show 高保真数据模型)
        final targetCards = parsedCards.take(20).toList();
        final showFutures = targetCards.map((it) async {
          try {
            final res = await _client.dio.get(
              ApiConstants.statusDetail,
              queryParameters: {'id': it.mid},
            );
            if (res.data is Map<String, dynamic>) {
              var model =
                  WeiboStatusModel.fromJson(res.data as Map<String, dynamic>);
              if (it.isTop) {
                model = model.copyWith(isTop: true, titleText: '置顶');
              } else if (it.isHot) {
                model = model.copyWith(titleText: '热门');
              }
              return model;
            }
          } catch (_) {}
          return null;
        });

        final statuses = (await Future.wait(showFutures))
            .whereType<WeiboStatusModel>()
            .where((s) => s.id.isNotEmpty)
            .toList();

        // 识别置顶博文 (信息流第一条标记为置顶，或 topicHeads 中指明的主持人/置顶博文)
        WeiboStatusModel? toppingStatus;
        if (statuses.isNotEmpty && statuses.first.isTop) {
          toppingStatus = statuses.first;
        } else if (topicHeader?.toppingMid != null &&
            topicHeader!.toppingMid!.isNotEmpty &&
            topicHeader.toppingMid != '-1') {
          try {
            final topRes = await _client.dio.get(
              ApiConstants.statusDetail,
              queryParameters: {'id': topicHeader.toppingMid},
            );
            if (topRes.data is Map<String, dynamic>) {
              toppingStatus =
                  WeiboStatusModel.fromJson(topRes.data as Map<String, dynamic>)
                      .copyWith(isTop: true, titleText: '置顶');
            }
          } catch (_) {}
        }

        return SearchStatusesResult(
          statuses: statuses,
          topicHeader: topicHeader,
          toppingStatus: toppingStatus,
        );
      }
    } catch (_) {}

    // 2. 官方备用接口 /ajax/statuses/search (如果 s.weibo.com 遭遇未登录反爬或离线)
    try {
      final response = await _client.dio.get(
        ApiConstants.searchStatuses,
        queryParameters: {
          'q': keyword,
          'page': page,
        },
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final rawList = data['data']?['statuses'] as List? ??
            data['data']?['list'] as List? ??
            data['statuses'] as List? ??
            [];

        final statuses = rawList
            .whereType<Map<String, dynamic>>()
            .map((item) => WeiboStatusModel.fromJson(item))
            .where((s) => s.id.isNotEmpty)
            .toList();

        WeiboTopicHeaderModel? topicHeader;
        if (data['topicHeads'] is Map<String, dynamic>) {
          try {
            topicHeader = WeiboTopicHeaderModel.fromTopicHeads(
              data['topicHeads'] as Map<String, dynamic>,
            );
          } catch (_) {}
        }

        return SearchStatusesResult(
          statuses: statuses,
          topicHeader: topicHeader,
        );
      }
    } catch (_) {}

    return const SearchStatusesResult(statuses: []);
  }

  Future<List<WeiboStatusModel>> searchStatuses({
    required String keyword,
    int page = 1,
  }) async {
    final result =
        await searchStatusesWithDetails(keyword: keyword, page: page);
    return result.statuses;
  }

  /// 官方原生搜索指定博主的微博 (GET /ajax/statuses/search?uid={uid}&q={keyword}&page={page})
  Future<List<WeiboStatusModel>> searchUserStatuses({
    required String uid,
    required String keyword,
    int page = 1,
  }) async {
    final clean = keyword.trim();
    if (clean.isEmpty || uid.isEmpty) return [];

    try {
      final response = await _client.dio.get(
        ApiConstants.searchStatuses,
        queryParameters: {
          'uid': uid,
          'q': clean,
          'page': page,
        },
        options: Options(
          headers: {'Referer': 'https://weibo.com/u/$uid'},
        ),
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final rawList = data['statuses'] as List? ??
            data['data']?['statuses'] as List? ??
            data['data']?['list'] as List? ??
            [];

        return rawList
            .whereType<Map<String, dynamic>>()
            .map((item) => WeiboStatusModel.fromJson(item))
            .where((s) => s.id.isNotEmpty)
            .toList();
      }
    } catch (_) {}

    return [];
  }

  /// 搜索超话本身 (官方原生接口: GET /ajax/stopic/list?keyword={keyword}&page={page})
  Future<List<SearchChaohuaItem>> searchChaohua(String keyword,
      {int page = 1}) async {
    final clean = keyword.trim();
    if (clean.isEmpty) return [];

    try {
      final response = await _client.dio.get(
        '/ajax/stopic/list',
        queryParameters: {
          'keyword': clean,
          'page': page,
        },
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final list = data['data'] as List? ?? [];
        return list
            .whereType<Map<String, dynamic>>()
            .map((item) => SearchChaohuaItem.fromJson(item))
            .where((ch) => ch.title.isNotEmpty && ch.pageId.isNotEmpty)
            .toList();
      }
    } catch (_) {}

    return [];
  }
}

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  final client = ref.watch(weiboDioClientProvider);
  return SearchRepository(client);
});
