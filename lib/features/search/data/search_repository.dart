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
    this.isHot = false,
    this.isNew = false,
    this.isBoom = false,
    this.isFei = false,
  });

  factory HotSearchItem.fromJson(Map<String, dynamic> json, int index) {
    final label = json['label_name']?.toString() ?? json['icon_desc']?.toString() ?? json['small_icon_desc']?.toString();
    final flag = json['flag_desc']?.toString();
    final cat = json['category']?.toString() ?? json['channel_type']?.toString();

    final labelStr = label ?? flag;

    return HotSearchItem(
      rank: json['realpos'] is int ? json['realpos'] as int : (json['rank'] is int ? json['rank'] as int : index + 1),
      word: json['word']?.toString() ?? json['note']?.toString() ?? '',
      num: json['num'] is int ? json['num'] as int : (json['raw_hot'] is int ? json['raw_hot'] as int : 0),
      labelName: labelStr,
      icon: json['icon']?.toString(),
      category: cat,
      isHot: labelStr == '热' || json['is_hot'] == 1,
      isNew: labelStr == '新' || json['is_new'] == 1,
      isBoom: labelStr == '爆' || json['is_boom'] == 1,
      isFei: labelStr == '沸',
    );
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

/// 搜索超话结果模型
class SearchChaohuaItem {
  final String title;
  final String pageId;
  final String image;
  final String description;

  const SearchChaohuaItem({
    required this.title,
    required this.pageId,
    required this.image,
    required this.description,
  });

  factory SearchChaohuaItem.fromJson(Map<String, dynamic> json) {
    return SearchChaohuaItem(
      title: json['title']?.toString() ?? '',
      pageId: json['page_id']?.toString() ?? '',
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

  /// 官方原生获取微博热搜榜 (优先请求 official hot_band，备用 side/hotSearch)
  Future<List<HotSearchItem>> getHotSearch() async {
    // 1. 官方原生热搜大榜 /ajax/statuses/hot_band
    try {
      final response = await _client.dio.get(ApiConstants.hotBand);
      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final bandList = data['data']?['band_list'] as List? ?? [];
        if (bandList.isNotEmpty) {
          return bandList
              .whereType<Map<String, dynamic>>()
              .toList()
              .asMap()
              .entries
              .map((e) => HotSearchItem.fromJson(e.value, e.key))
              .where((item) => item.word.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}

    // 2. 官方备用侧边栏热搜 /ajax/side/hotSearch
    try {
      final response = await _client.dio.get(ApiConstants.hotSearch);
      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final realtime = data['data']?['realtime'] as List? ?? [];
        return realtime
            .whereType<Map<String, dynamic>>()
            .toList()
            .asMap()
            .entries
            .map((e) => HotSearchItem.fromJson(e.value, e.key))
            .where((item) => item.word.isNotEmpty)
            .toList();
      }
    } catch (_) {}

    return [];
  }

  /// 获取官方特定分类的热搜榜单 (全量 50+ 词条，分类特色词条优先置顶展示)
  /// 支持: 'mine'(我的), 'hot'(热搜), 'ent'(文娱), 'life'(生活), 'social'(社会), 'local'(定位同城), 'sports'(体育), 'acg'(ACG), 'tech'(科技)
  Future<List<HotSearchItem>> getCategoryHotSearch(String categoryKey, {String city = '佛山'}) async {
    final allList = await getHotSearch();
    if (allList.isEmpty) return [];

    if (categoryKey == 'hot' || categoryKey == 'all') {
      return allList;
    }

    if (categoryKey == 'mine') {
      // 我的：高热精选、爆点关注流与互动热点优先置顶，紧接着拼接完整热搜大榜
      final mineList = allList.where((item) => item.isHot || item.isBoom || item.isFei || item.rank <= 15).toList();
      final seenWords = mineList.map((e) => e.word).toSet();
      for (final item in allList) {
        if (seenWords.add(item.word)) {
          mineList.add(item);
        }
      }
      return mineList;
    }

    if (categoryKey == 'local') {
      // 按照定位获取的地点对应的热搜 (如 佛山 / 广州 / 深圳 等)，优先前置同城相关词条，其余补充完整榜单
      final localFiltered = allList.where((item) {
        final w = item.word;
        return w.contains(city) ||
            w.contains('广东') ||
            w.contains('大湾区') ||
            w.contains('天气') ||
            w.contains('同城') ||
            w.contains('地铁') ||
            w.contains('假期') ||
            w.contains('台风');
      }).toList();

      final seenWords = localFiltered.map((e) => e.word).toSet();
      for (final item in allList) {
        if (seenWords.add(item.word)) {
          localFiltered.add(item);
        }
      }
      return localFiltered;
    }

    // 基于微博后端原生 category 字段与关键词进行领域归类置顶
    final officialCatKeywords = <String, List<String>>{
      'ent': ['文娱', '电影', '剧集', '艺人', '综艺', '时尚', '音乐', '明星', '歌手', '影评', '演技', '口碑', '定档', '演唱会', '首播'],
      'life': ['生活', '幽默', '情感', '美食', '旅游', '健康', '穿搭', '宠物', '养生', '做饭', '母婴育儿', '防窥', '走位'],
      'social': ['社会', '民生新闻', '突发/灾害', '海外新闻', '国内时政', '教育', '法律', '政务', '通报', '舆论监督', '上合', '求职', '闭店'],
      'sports': ['体育', '赛事', '篮球', '足球', '奥运', '乒乓球', '羽毛球', '网球', '跳水', '皇马', '曼城', '足协杯', '谷爱凌', '恩佐'],
      'acg': ['ACG', '游戏', '电竞', '动漫', '二次元', '漫画', '新番', '手游', '王者', 'LOL', 'AG'],
      'tech': ['科技', '互联网', '汽车', '数码', 'AI', '大模型', '手机', '芯片', '航空航天', '苹果', 'iPhone', 'CEO', '涨价'],
    };

    final targetCats = officialCatKeywords[categoryKey] ?? [];

    final matched = allList.where((item) {
      final itemCat = item.category ?? '';
      if (targetCats.any((tc) => itemCat.contains(tc))) {
        return true;
      }
      return targetCats.any((tc) => item.word.contains(tc));
    }).toList();

    // 将匹配该分类的特色词条置顶，其余热点词条紧随其后，确保每个分栏都完整拥有 50+ 个词条
    final seenWords = matched.map((e) => e.word).toSet();
    for (final item in allList) {
      if (seenWords.add(item.word)) {
        matched.add(item);
      }
    }

    return matched;
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
          final rawUsers = data['users'] as List? ?? data['user'] as List? ?? [];
          final users = rawUsers
              .whereType<Map<String, dynamic>>()
              .map((u) => WeiboUserModel.fromJson(u))
              .where((u) => u.id.isNotEmpty && u.screenName != '匿名用户')
              .toList();

          final rawSuggestions = data['query_relates'] as List? ??
              data['hotquery'] as List? ??
              [];
          final suggestions = rawSuggestions
              .map((s) => s is Map ? (s['word']?.toString() ?? '') : s.toString())
              .where((s) => s.isNotEmpty)
              .toList();

          return SearchSuggestResult(users: users, suggestions: suggestions);
        }
      }
    } catch (_) {}

    return const SearchSuggestResult();
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
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
        ),
      );

      // 第一页并发获取官方 topicHeads 元数据 (导语、封面大图、主持人及阅读讨论量)
      final topicFuture = page == 1
          ? _client.dio
              .get(
                ApiConstants.searchStatuses,
                queryParameters: {'q': isTopicKeyword ? '#$cleanK#' : cleanK, 'page': 1},
              )
              .then<Map<String, dynamic>?>((res) => res.data is Map<String, dynamic> ? res.data as Map<String, dynamic> : null)
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

      final parsedCards = <({String mid, bool isTop, bool isHot, String nick})>[];
      for (final card in allCards) {
        final block = card.group(0) ?? '';
        final mid = RegExp(r'mid="(\d+)"').firstMatch(block)?.group(1);
        if (mid == null || parsedCards.any((m) => m.mid == mid)) continue;

        final cardTopMatch = RegExp(r'<div class="card-top"[^>]*>([\s\S]*?)</div>').firstMatch(block);
        final cardTop = cardTopMatch?.group(1) ?? '';
        final isTop = cardTop.contains('置顶') || block.contains('icon-top') || block.contains('label-top');
        final isHot = cardTop.contains('热门') || cardTop.contains('icon-star') || cardTop.contains('icon-hot');
        final nick = RegExp(r'nick-name="([^"]+)"').firstMatch(block)?.group(1) ?? '';

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
              var model = WeiboStatusModel.fromJson(res.data as Map<String, dynamic>);
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
              toppingStatus = WeiboStatusModel.fromJson(topRes.data as Map<String, dynamic>).copyWith(isTop: true, titleText: '置顶');
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
    final result = await searchStatusesWithDetails(keyword: keyword, page: page);
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
  Future<List<SearchChaohuaItem>> searchChaohua(String keyword, {int page = 1}) async {
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
