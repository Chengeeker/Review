import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/storage_service.dart';

class ThemeState {
  final ThemeMode themeMode;
  final bool useDynamicColor;
  final int themeColorIndex;
  final bool isPureBlackDark;
  final bool enableHaptics;
  final bool useFloatingNavBar;
  final bool useCustomFontWeight;
  final int customFontWeightDelta;
  final int systemFontWeightAdjustment;
  final int screenRefreshRateMode;

  const ThemeState({
    this.themeMode = ThemeMode.system,
    this.useDynamicColor = false,
    this.themeColorIndex = 0,
    this.isPureBlackDark = false,
    this.enableHaptics = true,
    this.useFloatingNavBar = true,
    this.useCustomFontWeight = false,
    this.customFontWeightDelta = 0,
    this.systemFontWeightAdjustment = 0,
    this.screenRefreshRateMode = 0,
  });

  /// 有效字重偏移：若开启自定义则完全不受系统全局设置影响，否则跟随系统全局字重
  int get effectiveFontWeightAdjustment =>
      useCustomFontWeight ? customFontWeightDelta : systemFontWeightAdjustment;

  ThemeState copyWith({
    ThemeMode? themeMode,
    bool? useDynamicColor,
    int? themeColorIndex,
    bool? isPureBlackDark,
    bool? enableHaptics,
    bool? useFloatingNavBar,
    bool? useCustomFontWeight,
    int? customFontWeightDelta,
    int? systemFontWeightAdjustment,
    int? screenRefreshRateMode,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      themeColorIndex: themeColorIndex ?? this.themeColorIndex,
      isPureBlackDark: isPureBlackDark ?? this.isPureBlackDark,
      enableHaptics: enableHaptics ?? this.enableHaptics,
      useFloatingNavBar: useFloatingNavBar ?? this.useFloatingNavBar,
      useCustomFontWeight: useCustomFontWeight ?? this.useCustomFontWeight,
      customFontWeightDelta: customFontWeightDelta ?? this.customFontWeightDelta,
      systemFontWeightAdjustment: systemFontWeightAdjustment ?? this.systemFontWeightAdjustment,
      screenRefreshRateMode: screenRefreshRateMode ?? this.screenRefreshRateMode,
    );
  }
}

class ThemeNotifier extends StateNotifier<ThemeState> {
  final StorageService _storage;
  static const MethodChannel _channel = MethodChannel('com.sharelite/cookies');

  ThemeNotifier(this._storage) : super(const ThemeState()) {
    _loadFromStorage();
    _initSystemFontWeight();
  }

  Future<void> _initSystemFontWeight() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFontWeightAdjustmentChanged') {
        final adj = call.arguments as int? ?? 0;
        setSystemFontWeightAdjustment(adj);
      }
    });

    try {
      final adj = await _channel.invokeMethod<int>('getFontWeightAdjustment');
      if (adj != null && adj != state.systemFontWeightAdjustment) {
        setSystemFontWeightAdjustment(adj);
      }
    } catch (_) {}
  }

  void setSystemFontWeightAdjustment(int adjustment) {
    if (state.systemFontWeightAdjustment != adjustment) {
      state = state.copyWith(systemFontWeightAdjustment: adjustment);
    }
  }

  void reload() {
    _loadFromStorage();
    _initSystemFontWeight();
  }

  void _loadFromStorage() {
    final modeIndex = _storage.getInt(StorageService.keyThemeMode, defaultValue: 0);
    final useDynamic = _storage.getBool(StorageService.keyUseDynamicColor, defaultValue: false);
    final colorIdx = _storage.getInt('key_theme_color_index', defaultValue: 0);
    final pureBlack = _storage.getBool('key_is_pure_black_dark', defaultValue: false);
    final haptics = _storage.getEnableHaptics();
    final floatingNav = _storage.getUseFloatingNavBar();
    final customFont = _storage.getUseCustomFontWeight();
    final customFontDelta = _storage.getCustomFontWeightDelta();
    final refreshMode = _storage.getScreenRefreshRateMode();

    ThemeMode mode = ThemeMode.system;
    if (modeIndex == 1) mode = ThemeMode.light;
    if (modeIndex == 2) mode = ThemeMode.dark;

    state = state.copyWith(
      themeMode: mode,
      useDynamicColor: useDynamic,
      themeColorIndex: colorIdx,
      isPureBlackDark: pureBlack,
      enableHaptics: haptics,
      useFloatingNavBar: floatingNav,
      useCustomFontWeight: customFont,
      customFontWeightDelta: customFontDelta,
      screenRefreshRateMode: refreshMode,
    );
    _applyScreenRefreshRateMode(refreshMode);
  }

  Future<void> setScreenRefreshRateMode(int mode) async {
    await _storage.setScreenRefreshRateMode(mode);
    state = state.copyWith(screenRefreshRateMode: mode);
    await _applyScreenRefreshRateMode(mode);
  }

  Future<void> _applyScreenRefreshRateMode(int mode) async {
    try {
      await _channel.invokeMethod('setScreenRefreshRateMode', {'mode': mode});
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    int index = 0;
    if (mode == ThemeMode.light) index = 1;
    if (mode == ThemeMode.dark) index = 2;

    await _storage.setInt(StorageService.keyThemeMode, index);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setUseDynamicColor(bool useDynamic) async {
    await _storage.setBool(StorageService.keyUseDynamicColor, useDynamic);
    state = state.copyWith(useDynamicColor: useDynamic);
  }

  Future<void> setThemeColorIndex(int index) async {
    await _storage.setInt('key_theme_color_index', index);
    state = state.copyWith(themeColorIndex: index);
  }

  Future<void> setPureBlackDark(bool enabled) async {
    await _storage.setBool('key_is_pure_black_dark', enabled);
    state = state.copyWith(isPureBlackDark: enabled);
  }

  Future<void> setEnableHaptics(bool enabled) async {
    await _storage.setEnableHaptics(enabled);
    state = state.copyWith(enableHaptics: enabled);
  }

  Future<void> setUseFloatingNavBar(bool enabled) async {
    await _storage.setUseFloatingNavBar(enabled);
    state = state.copyWith(useFloatingNavBar: enabled);
  }

  Future<void> setUseCustomFontWeight(bool enabled) async {
    await _storage.setUseCustomFontWeight(enabled);
    state = state.copyWith(useCustomFontWeight: enabled);
  }

  Future<void> setCustomFontWeightDelta(int delta) async {
    await _storage.setCustomFontWeightDelta(delta);
    state = state.copyWith(customFontWeightDelta: delta);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return ThemeNotifier(storage);
});
