/// Weibo API Endpoints & Request Constants
class ApiConstants {
  ApiConstants._();

  static const String appVersion = '1.6';
  static const int appVersionCode = 7;

  static const String baseUrl = 'https://weibo.com';
  static const String passportUrl = 'https://passport.weibo.com';
  static const String mWeiboUrl = 'https://m.weibo.cn';

  // Endpoints (2024-2026 Modern Weibo REST API)
  static const String visitorGen = '/visitor/genvisitor';
  static const String visitorIncarnate = '/visitor/visitor';
  
  static const String hotTimeline = '/ajax/feed/hottimeline';
  static const String friendsTimeline = '/ajax/feed/friendstimeline';
  static const String groupTimeline = '/ajax/feed/groupstimeline';
  static const String allGroups = '/ajax/feed/allGroups';
  static const String userTimeline = '/ajax/statuses/mymblog';
  static const String statusDetail = '/ajax/statuses/show';
  static const String editHistory = '/ajax/statuses/editHistory';
  static const String longText = '/ajax/statuses/longtext';
  static const String updateStatus = '/ajax/statuses/update';
  static const String modifyStatus = '/ajax/statuses/modify';
  static const String destroyStatus = '/ajax/statuses/destroy';
  static const String buildComments = '/ajax/statuses/buildComments';
  static const String secondComment = '/ajax/statuses/getSecondComment';
  static const String createComment = '/ajax/comments/create';
  static const String replyComment = '/ajax/comments/reply';
  static const String destroyComment = '/ajax/statuses/destroyComment';
  static const String hotSearch = '/ajax/side/hotSearch';
  static const String hotBand = '/ajax/statuses/hot_band';
  static const String searchSuggest = '/ajax/side/search';
  static const String searchStatuses = '/ajax/statuses/search';
  static const String setLike = '/ajax/statuses/setLike';
  static const String cancelLike = '/ajax/statuses/cancelLike';
  static const String createFavorites = '/ajax/statuses/createFavorites';
  static const String destroyFavorites = '/ajax/statuses/destoryFavorites';
  static const String updateCommentLike = '/ajax/statuses/updateLike';
  static const String followUser = '/ajax/friendships/create';
  static const String destroyFollow = '/ajax/friendships/destroy';

  // Category Channels (with '最新关注' as primary chronological follow tab)
  static const List<Map<String, String>> categories = [
    {'id': 'friends', 'name': '最新关注'},
    {'id': 'special', 'name': '特别关注'},
    {'id': '102803', 'name': '全网热门'},
    {'id': '102803_ctg1_1988_-_ctg1_1988', 'name': '数码'},
    {'id': '102803_ctg1_4188_-_ctg1_4188', 'name': '社会'},
    {'id': '102803_ctg1_2688_-_ctg1_2688', 'name': '动漫'},
    {'id': '102803_ctg1_3288_-_ctg1_3288', 'name': '游戏'},
    {'id': '102803_ctg1_1388_-_ctg1_1388', 'name': '电影'},
    {'id': '102803_ctg1_2088_-_ctg1_2088', 'name': '美妆'},
    {'id': '102803_ctg1_1888_-_ctg1_1888', 'name': '汽车'},
    {'id': '102803_ctg1_1488_-_ctg1_1488', 'name': '音乐'},
  ];

  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const Map<String, String> imageHeaders = {
    'Referer': 'https://weibo.com/',
    'User-Agent': defaultUserAgent,
  };
}
