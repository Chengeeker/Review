import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent Key-Value Storage Service using SharedPreferences
class StorageService {
  static const String keySubCookie = 'weibo_sub_cookie';
  static const String keySubpCookie = 'weibo_subp_cookie';
  static const String keyFullCookie = 'weibo_full_cookie';
  static const String keyAccessToken = 'weibo_access_token';
  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyUserUid = 'user_uid';
  static const String keyUserNickname = 'user_nickname';
  static const String keyUserAvatar = 'user_avatar';
  static const String keyThemeMode = 'theme_mode';
  static const String keyUseDynamicColor = 'use_dynamic_color';
  static const String keyUseFloatingNavBar = 'use_floating_nav_bar';
  static const String keyAutoClearCacheOnExit = 'auto_clear_cache_on_exit';
  static const String keySavedDefaultGroups = 'saved_default_groups_json';
  static const String keySavedPersonalGroups = 'saved_personal_groups_json';
  static const String keySavedHotGroups = 'saved_hot_groups_json';
  static const String keyEnableHaptics = 'key_enable_haptics';
  static const String keyUseCustomFontWeight = 'key_use_custom_font_weight';
  static const String keyCustomFontWeightDelta = 'key_custom_font_weight_delta';
  static const String keyScreenRefreshRateMode = 'key_screen_refresh_rate_mode'; // 0~8
  static const String keyCurrentPresetAppIconId = 'key_current_preset_app_icon_id'; // 'default' | 'alias1' | 'alias2' | 'alias3'

  // Card Display & Date Settings Keys
  static const String keyTimeDisplayMode = 'time_display_mode'; // 'relative' | 'absolute'
  static const String keyShowWeekday = 'show_weekday'; // bool
  static const String keyShowYear = 'show_year'; // bool
  static const String keyShowTimezone = 'show_timezone'; // bool
  static const String keyShowSeconds = 'show_seconds'; // bool
  static const String keyShowSource = 'show_source'; // bool
  static const String keyShowRegion = 'show_region'; // bool
  static const String keyAppLanguage = 'app_language'; // 'zh' | 'en' | 'system'

  // Weibo Style Customization Keys (微博样式个性化)
  static const String keyWeiboSuffix = 'weibo_suffix'; // '来自微博国际版'
  static const String keyCardBackgroundLayout = 'card_background_layout'; // 'card_rounded' | 'flat_tile'
  static const String keyWeiboFontSize = 'weibo_font_size'; // double, default 16.0
  static const String keyWeiboFontLineHeight = 'weibo_font_line_height'; // double, default 1.3
  static const String keyLinkColorFollowTheme = 'link_color_follow_theme'; // bool, default true
  static const String keyShowRemarkAndName = 'show_remark_and_name'; // bool, default false
  static const String keyShowBackgroundImage = 'show_background_image'; // bool, default false
  static const String keyShowUserActivityIcon = 'show_user_activity_icon'; // bool, default true
  static const String keyLargeImageMode = 'large_image_mode'; // bool, default true
  static const String keyRoundedImageCorners = 'rounded_image_corners'; // bool, default true
  static const String keyShowMenuAtBottom = 'show_menu_at_bottom'; // bool, default true
  static const String keyShowIpLocationMode = 'show_ip_location_mode'; // 'all' | 'detail_only' | 'none'
  static const String keyShowProfileLikedTweets = 'show_profile_liked_tweets'; // bool, default false
  static const String keySearchHistory = 'search_history_list'; // List<String>
  static const String keyImageSavePathType = 'image_save_path_type'; // 0: Pictures/Review/, 1: Pictures/Review/{myNickname}, 2: Pictures/Review/{authorNickname}
  static const String keyVideoSavePathType = 'video_save_path_type'; // 0: Pictures/Review/, 1: Pictures/Review/{myNickname}, 2: Pictures/Review/{authorNickname}
  static const String keyWebDavUrl = 'webdav_url';
  static const String keyWebDavUsername = 'webdav_username';
  static const String keyWebDavPassword = 'webdav_password';
  static const String keyWebDavDirectory = 'webdav_directory';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  String? getSubCookie() => _prefs.getString(keySubCookie);
  Future<bool> setSubCookie(String value) => _prefs.setString(keySubCookie, value);

  String? getSubpCookie() => _prefs.getString(keySubpCookie);
  Future<bool> setSubpCookie(String value) => _prefs.setString(keySubpCookie, value);

  String? getFullCookie() => _prefs.getString(keyFullCookie);
  Future<bool> setFullCookie(String value) => _prefs.setString(keyFullCookie, value);

  String? getAccessToken() => _prefs.getString(keyAccessToken);
  Future<bool> setAccessToken(String value) => _prefs.setString(keyAccessToken, value);

  bool isLoggedIn() => _prefs.getBool(keyIsLoggedIn) ?? false;
  Future<bool> setLoggedIn(bool value) => _prefs.setBool(keyIsLoggedIn, value);

  String? getString(String key) => _prefs.getString(key);
  Future<bool> setString(String key, String value) => _prefs.setString(key, value);

  int getInt(String key, {int defaultValue = 0}) => _prefs.getInt(key) ?? defaultValue;
  Future<bool> setInt(String key, int value) => _prefs.setInt(key, value);

  double getDouble(String key, {double defaultValue = 0.0}) => _prefs.getDouble(key) ?? defaultValue;
  Future<bool> setDouble(String key, double value) => _prefs.setDouble(key, value);

  bool getBool(String key, {bool defaultValue = false}) => _prefs.getBool(key) ?? defaultValue;
  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);

  bool getUseFloatingNavBar() => _prefs.getBool(keyUseFloatingNavBar) ?? true;
  Future<bool> setUseFloatingNavBar(bool val) => _prefs.setBool(keyUseFloatingNavBar, val);

  int getImageSavePathType() => getInt(keyImageSavePathType, defaultValue: 0);
  Future<bool> setImageSavePathType(int value) => setInt(keyImageSavePathType, value);

  int getVideoSavePathType() => getInt(keyVideoSavePathType, defaultValue: 0);
  Future<bool> setVideoSavePathType(int value) => setInt(keyVideoSavePathType, value);

  bool getAutoClearCacheOnExit() => getBool(keyAutoClearCacheOnExit, defaultValue: false);
  Future<bool> setAutoClearCacheOnExit(bool value) => _prefs.setBool(keyAutoClearCacheOnExit, value);

  String? getSavedDefaultGroupsJson() => _prefs.getString(keySavedDefaultGroups);
  Future<bool> setSavedDefaultGroupsJson(String json) => _prefs.setString(keySavedDefaultGroups, json);

  String? getSavedPersonalGroupsJson() => _prefs.getString(keySavedPersonalGroups);
  Future<bool> setSavedPersonalGroupsJson(String json) => _prefs.setString(keySavedPersonalGroups, json);

  String? getSavedHotGroupsJson() => _prefs.getString(keySavedHotGroups);
  Future<bool> setSavedHotGroupsJson(String json) => _prefs.setString(keySavedHotGroups, json);

  bool getEnableHaptics() => _prefs.getBool(keyEnableHaptics) ?? true;
  Future<bool> setEnableHaptics(bool val) => _prefs.setBool(keyEnableHaptics, val);

  bool getUseCustomFontWeight() => getBool(keyUseCustomFontWeight, defaultValue: false);
  Future<bool> setUseCustomFontWeight(bool val) => setBool(keyUseCustomFontWeight, val);

  int getCustomFontWeightDelta() => getInt(keyCustomFontWeightDelta, defaultValue: 0);
  Future<bool> setCustomFontWeightDelta(int val) => setInt(keyCustomFontWeightDelta, val);

  int getScreenRefreshRateMode() => getInt(keyScreenRefreshRateMode, defaultValue: 0);
  Future<bool> setScreenRefreshRateMode(int val) => setInt(keyScreenRefreshRateMode, val);

  // Card Display getters & setters
  String getTimeDisplayMode() => _prefs.getString(keyTimeDisplayMode) ?? 'relative';
  Future<bool> setTimeDisplayMode(String mode) => _prefs.setString(keyTimeDisplayMode, mode);

  bool getShowWeekday() => _prefs.getBool(keyShowWeekday) ?? false;
  Future<bool> setShowWeekday(bool val) => _prefs.setBool(keyShowWeekday, val);

  bool getShowYear() => _prefs.getBool(keyShowYear) ?? false;
  Future<bool> setShowYear(bool val) => _prefs.setBool(keyShowYear, val);

  bool getShowTimezone() => _prefs.getBool(keyShowTimezone) ?? false;
  Future<bool> setShowTimezone(bool val) => _prefs.setBool(keyShowTimezone, val);

  bool getShowSeconds() => _prefs.getBool(keyShowSeconds) ?? false;
  Future<bool> setShowSeconds(bool val) => _prefs.setBool(keyShowSeconds, val);

  bool getShowSource() => _prefs.getBool(keyShowSource) ?? true;
  Future<bool> setShowSource(bool val) => _prefs.setBool(keyShowSource, val);

  bool getShowRegion() => _prefs.getBool(keyShowRegion) ?? true;
  Future<bool> setShowRegion(bool val) => _prefs.setBool(keyShowRegion, val);

  String getAppLanguage() => _prefs.getString(keyAppLanguage) ?? 'zh';
  Future<bool> setAppLanguage(String lang) => _prefs.setString(keyAppLanguage, lang);

  // Weibo Style Getters & Setters
  String getWeiboSuffix() => _prefs.getString(keyWeiboSuffix) ?? '来自微博国际版';
  Future<bool> setWeiboSuffix(String suffix) => _prefs.setString(keyWeiboSuffix, suffix);

  String getCardBackgroundLayout() => _prefs.getString(keyCardBackgroundLayout) ?? 'card_rounded';
  Future<bool> setCardBackgroundLayout(String layout) => _prefs.setString(keyCardBackgroundLayout, layout);

  double getWeiboFontSize() => _prefs.getDouble(keyWeiboFontSize) ?? 16.0;
  Future<bool> setWeiboFontSize(double size) => _prefs.setDouble(keyWeiboFontSize, size);

  double getWeiboFontLineHeight() => _prefs.getDouble(keyWeiboFontLineHeight) ?? 1.3;
  Future<bool> setWeiboFontLineHeight(double height) => _prefs.setDouble(keyWeiboFontLineHeight, height);

  bool getLinkColorFollowTheme() => _prefs.getBool(keyLinkColorFollowTheme) ?? true;
  Future<bool> setLinkColorFollowTheme(bool val) => _prefs.setBool(keyLinkColorFollowTheme, val);

  bool getShowRemarkAndName() => _prefs.getBool(keyShowRemarkAndName) ?? false;
  Future<bool> setShowRemarkAndName(bool val) => _prefs.setBool(keyShowRemarkAndName, val);

  bool getShowBackgroundImage() => _prefs.getBool(keyShowBackgroundImage) ?? false;
  Future<bool> setShowBackgroundImage(bool val) => _prefs.setBool(keyShowBackgroundImage, val);

  bool getShowUserActivityIcon() => _prefs.getBool(keyShowUserActivityIcon) ?? true;
  Future<bool> setShowUserActivityIcon(bool val) => _prefs.setBool(keyShowUserActivityIcon, val);

  bool getLargeImageMode() => _prefs.getBool(keyLargeImageMode) ?? true;
  Future<bool> setLargeImageMode(bool val) => _prefs.setBool(keyLargeImageMode, val);

  bool getRoundedImageCorners() => _prefs.getBool(keyRoundedImageCorners) ?? true;
  Future<bool> setRoundedImageCorners(bool val) => _prefs.setBool(keyRoundedImageCorners, val);

  bool getShowMenuAtBottom() => _prefs.getBool(keyShowMenuAtBottom) ?? true;
  Future<bool> setShowMenuAtBottom(bool val) => _prefs.setBool(keyShowMenuAtBottom, val);

  String getShowIpLocationMode() => _prefs.getString(keyShowIpLocationMode) ?? 'all';
  Future<bool> setShowIpLocationMode(String mode) => _prefs.setString(keyShowIpLocationMode, mode);

  bool getShowProfileLikedTweets() => _prefs.getBool(keyShowProfileLikedTweets) ?? false;
  Future<bool> setShowProfileLikedTweets(bool val) => _prefs.setBool(keyShowProfileLikedTweets, val);

  List<String> getSearchHistory() => _prefs.getStringList(keySearchHistory) ?? [];

  Future<bool> addSearchHistory(String keyword) async {
    final clean = keyword.trim();
    if (clean.isEmpty) return false;
    final list = List<String>.from(getSearchHistory());
    list.remove(clean);
    list.insert(0, clean);
    if (list.length > 20) {
      list.removeRange(20, list.length);
    }
    return _prefs.setStringList(keySearchHistory, list);
  }

  Future<bool> removeSearchHistory(String keyword) async {
    final list = List<String>.from(getSearchHistory());
    list.remove(keyword);
    return _prefs.setStringList(keySearchHistory, list);
  }

  Future<bool> clearSearchHistory() async {
    return _prefs.remove(keySearchHistory);
  }

  static const String keyBrowsingHistory = 'wb_browsing_history';
  static const String keyBrowsingHistoryStatuses = 'wb_browsing_history_statuses';

  List<String> getBrowsingHistoryStatusJsons() => _prefs.getStringList(keyBrowsingHistoryStatuses) ?? [];

  Future<bool> recordViewedStatusJson(String statusId, String statusJson) async {
    if (statusId.isEmpty || statusJson.isEmpty) return false;
    final list = List<String>.from(getBrowsingHistoryStatusJsons());
    list.removeWhere((item) => item.contains('"id":"$statusId"') || item.contains('"id":$statusId'));
    list.insert(0, statusJson);
    if (list.length > 60) {
      list.removeRange(60, list.length);
    }
    return _prefs.setStringList(keyBrowsingHistoryStatuses, list);
  }

  Future<bool> removeBrowsingHistoryItem(int index) async {
    final list = List<String>.from(getBrowsingHistoryStatusJsons());
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      return _prefs.setStringList(keyBrowsingHistoryStatuses, list);
    }
    return false;
  }

  Future<bool> clearBrowsingHistory() async => _prefs.remove(keyBrowsingHistoryStatuses);

  String getWebDavUrl() => _prefs.getString(keyWebDavUrl) ?? '';
  Future<bool> setWebDavUrl(String v) => _prefs.setString(keyWebDavUrl, v);

  String getWebDavUsername() => _prefs.getString(keyWebDavUsername) ?? '';
  Future<bool> setWebDavUsername(String v) => _prefs.setString(keyWebDavUsername, v);

  String getWebDavPassword() => _prefs.getString(keyWebDavPassword) ?? '';
  Future<bool> setWebDavPassword(String v) => _prefs.setString(keyWebDavPassword, v);

  String getWebDavDirectory() => _prefs.getString(keyWebDavDirectory) ?? 'Review';
  Future<bool> setWebDavDirectory(String v) => _prefs.setString(keyWebDavDirectory, v);

  String getCurrentPresetAppIconId() => _prefs.getString(keyCurrentPresetAppIconId) ?? 'default';
  Future<bool> setCurrentPresetAppIconId(String v) => _prefs.setString(keyCurrentPresetAppIconId, v);

  static const Set<String> allowedExportKeys = {
    keyCurrentPresetAppIconId,
    keyThemeMode,
    keyUseDynamicColor,
    keyUseFloatingNavBar,
    keyAutoClearCacheOnExit,
    keySavedDefaultGroups,
    keySavedPersonalGroups,
    keySavedHotGroups,
    keyEnableHaptics,
    keyTimeDisplayMode,
    keyShowWeekday,
    keyShowYear,
    keyShowTimezone,
    keyShowSeconds,
    keyShowSource,
    keyShowRegion,
    keyAppLanguage,
    keyWeiboSuffix,
    keyCardBackgroundLayout,
    keyWeiboFontSize,
    keyWeiboFontLineHeight,
    keyLinkColorFollowTheme,
    keyShowRemarkAndName,
    keyShowBackgroundImage,
    keyShowUserActivityIcon,
    keyLargeImageMode,
    keyRoundedImageCorners,
    keyShowMenuAtBottom,
    keyShowIpLocationMode,
    keyShowProfileLikedTweets,
    keySearchHistory,
    keyImageSavePathType,
    keyVideoSavePathType,
    keyWebDavUrl,
    keyWebDavUsername,
    keyWebDavDirectory,
  };

  Map<String, dynamic> exportAllData() {
    final map = <String, dynamic>{};
    for (final key in allowedExportKeys) {
      if (_prefs.containsKey(key)) {
        map[key] = _prefs.get(key);
      }
    }
    return {
      'app': 'Review',
      'version': '1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'preferences': map,
    };
  }

  Future<void> restoreAllData(Map<String, dynamic> data) async {
    final prefsMap = data['preferences'];
    if (prefsMap is Map<String, dynamic>) {
      for (final entry in prefsMap.entries) {
        final k = entry.key;
        if (!allowedExportKeys.contains(k)) continue;
        final v = entry.value;
        if (v is bool) {
          await _prefs.setBool(k, v);
        } else if (v is int) {
          await _prefs.setInt(k, v);
        } else if (v is double) {
          await _prefs.setDouble(k, v);
        } else if (v is String) {
          await _prefs.setString(k, v);
        } else if (v is List) {
          await _prefs.setStringList(k, v.map((e) => e.toString()).toList());
        }
      }
    }
  }

  Future<bool> clearAuth() async {
    await _prefs.remove(keySubCookie);
    await _prefs.remove(keySubpCookie);
    await _prefs.remove(keyFullCookie);
    await _prefs.remove(keyAccessToken);
    await _prefs.remove(keyIsLoggedIn);
    await _prefs.remove(keyUserUid);
    await _prefs.remove(keyUserNickname);
    await _prefs.remove(keyUserAvatar);
    return true;
  }
}

final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('StorageService must be initialized in main()');
});
