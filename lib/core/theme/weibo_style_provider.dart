import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/storage_service.dart';

/// 微博样式全套配置模型
class WeiboStyleSettings {
  final String weiboSuffix; // '来自微博国际版'
  final String cardBackgroundLayout; // 'normal' | 'floating_rect' | 'floating_rounded' | 'normal_thin_divider' | 'card_rounded'
  final double fontSize; // 默认 16.0 (范围 12 - 22)
  final double fontLineHeight; // 默认 1.3 (范围 1.0 - 2.0)
  final bool linkColorFollowTheme; // 链接颜色跟随主题
  final bool showRemarkAndName; // 同时显示备注和名字
  final bool showBackgroundImage; // 显示背景图片
  final bool showUserActivityIcon; // 微博显示用户活动图标
  final bool largeImageMode; // 大图片模式(小图模式即为官方微博一样的样式)
  final bool roundedImageCorners; // 微博内图片圆角显示
  final bool showMenuAtBottom; // 菜单键显示在底部
  final String showIpLocationMode; // 'all' (列表和详情都显示) | 'detail_only' (仅详情显示) | 'none' (不显示)
  final bool showProfileLikedTweets; // 个人主页是否显示ta赞过的微博

  const WeiboStyleSettings({
    this.weiboSuffix = '来自微博国际版',
    this.cardBackgroundLayout = 'card_rounded',
    this.fontSize = 16.0,
    this.fontLineHeight = 1.3,
    this.linkColorFollowTheme = true,
    this.showRemarkAndName = false,
    this.showBackgroundImage = false,
    this.showUserActivityIcon = true,
    this.largeImageMode = true,
    this.roundedImageCorners = true,
    this.showMenuAtBottom = true,
    this.showIpLocationMode = 'all',
    this.showProfileLikedTweets = false,
  });

  WeiboStyleSettings copyWith({
    String? weiboSuffix,
    String? cardBackgroundLayout,
    double? fontSize,
    double? fontLineHeight,
    bool? linkColorFollowTheme,
    bool? showRemarkAndName,
    bool? showBackgroundImage,
    bool? showUserActivityIcon,
    bool? largeImageMode,
    bool? roundedImageCorners,
    bool? showMenuAtBottom,
    String? showIpLocationMode,
    bool? showProfileLikedTweets,
  }) {
    return WeiboStyleSettings(
      weiboSuffix: weiboSuffix ?? this.weiboSuffix,
      cardBackgroundLayout: cardBackgroundLayout ?? this.cardBackgroundLayout,
      fontSize: fontSize ?? this.fontSize,
      fontLineHeight: fontLineHeight ?? this.fontLineHeight,
      linkColorFollowTheme: linkColorFollowTheme ?? this.linkColorFollowTheme,
      showRemarkAndName: showRemarkAndName ?? this.showRemarkAndName,
      showBackgroundImage: showBackgroundImage ?? this.showBackgroundImage,
      showUserActivityIcon: showUserActivityIcon ?? this.showUserActivityIcon,
      largeImageMode: largeImageMode ?? this.largeImageMode,
      roundedImageCorners: roundedImageCorners ?? this.roundedImageCorners,
      showMenuAtBottom: showMenuAtBottom ?? this.showMenuAtBottom,
      showIpLocationMode: showIpLocationMode ?? this.showIpLocationMode,
      showProfileLikedTweets: showProfileLikedTweets ?? this.showProfileLikedTweets,
    );
  }
}

/// Weibo Style Notifier
class WeiboStyleNotifier extends StateNotifier<WeiboStyleSettings> {
  final StorageService _storage;

  WeiboStyleNotifier(this._storage)
      : super(WeiboStyleSettings(
          weiboSuffix: _storage.getWeiboSuffix(),
          cardBackgroundLayout: _storage.getCardBackgroundLayout(),
          fontSize: _storage.getWeiboFontSize(),
          fontLineHeight: _storage.getWeiboFontLineHeight(),
          linkColorFollowTheme: _storage.getLinkColorFollowTheme(),
          showRemarkAndName: _storage.getShowRemarkAndName(),
          showBackgroundImage: _storage.getShowBackgroundImage(),
          showUserActivityIcon: _storage.getShowUserActivityIcon(),
          largeImageMode: _storage.getLargeImageMode(),
          roundedImageCorners: _storage.getRoundedImageCorners(),
          showMenuAtBottom: _storage.getShowMenuAtBottom(),
          showIpLocationMode: _storage.getShowIpLocationMode(),
          showProfileLikedTweets: _storage.getShowProfileLikedTweets(),
        ));

  void reload() {
    state = WeiboStyleSettings(
      weiboSuffix: _storage.getWeiboSuffix(),
      cardBackgroundLayout: _storage.getCardBackgroundLayout(),
      fontSize: _storage.getWeiboFontSize(),
      fontLineHeight: _storage.getWeiboFontLineHeight(),
      linkColorFollowTheme: _storage.getLinkColorFollowTheme(),
      showRemarkAndName: _storage.getShowRemarkAndName(),
      showBackgroundImage: _storage.getShowBackgroundImage(),
      showUserActivityIcon: _storage.getShowUserActivityIcon(),
      largeImageMode: _storage.getLargeImageMode(),
      roundedImageCorners: _storage.getRoundedImageCorners(),
      showMenuAtBottom: _storage.getShowMenuAtBottom(),
      showIpLocationMode: _storage.getShowIpLocationMode(),
      showProfileLikedTweets: _storage.getShowProfileLikedTweets(),
    );
  }

  Future<void> setWeiboSuffix(String suffix) async {
    await _storage.setWeiboSuffix(suffix);
    state = state.copyWith(weiboSuffix: suffix);
  }

  Future<void> setCardBackgroundLayout(String layout) async {
    await _storage.setCardBackgroundLayout(layout);
    state = state.copyWith(cardBackgroundLayout: layout);
  }

  Future<void> setWeiboFontSize(double size) async {
    await _storage.setWeiboFontSize(size);
    state = state.copyWith(fontSize: size);
  }

  Future<void> setWeiboFontLineHeight(double height) async {
    await _storage.setWeiboFontLineHeight(height);
    state = state.copyWith(fontLineHeight: height);
  }

  Future<void> setLinkColorFollowTheme(bool val) async {
    await _storage.setLinkColorFollowTheme(val);
    state = state.copyWith(linkColorFollowTheme: val);
  }

  Future<void> setShowRemarkAndName(bool val) async {
    await _storage.setShowRemarkAndName(val);
    state = state.copyWith(showRemarkAndName: val);
  }

  Future<void> setShowBackgroundImage(bool val) async {
    await _storage.setShowBackgroundImage(val);
    state = state.copyWith(showBackgroundImage: val);
  }

  Future<void> setShowUserActivityIcon(bool val) async {
    await _storage.setShowUserActivityIcon(val);
    state = state.copyWith(showUserActivityIcon: val);
  }

  Future<void> setLargeImageMode(bool val) async {
    await _storage.setLargeImageMode(val);
    state = state.copyWith(largeImageMode: val);
  }

  Future<void> setRoundedImageCorners(bool val) async {
    await _storage.setRoundedImageCorners(val);
    state = state.copyWith(roundedImageCorners: val);
  }

  Future<void> setShowMenuAtBottom(bool val) async {
    await _storage.setShowMenuAtBottom(val);
    state = state.copyWith(showMenuAtBottom: val);
  }

  Future<void> setShowIpLocationMode(String mode) async {
    await _storage.setShowIpLocationMode(mode);
    state = state.copyWith(showIpLocationMode: mode);
  }

  Future<void> setShowProfileLikedTweets(bool val) async {
    await _storage.setShowProfileLikedTweets(val);
    state = state.copyWith(showProfileLikedTweets: val);
  }
}

final weiboStyleProvider = StateNotifierProvider<WeiboStyleNotifier, WeiboStyleSettings>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return WeiboStyleNotifier(storage);
});
