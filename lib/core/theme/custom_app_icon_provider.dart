import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/storage_service.dart';

class PresetAppIconModel {
  final String id;
  final String name;
  final String description;
  final String assetPath;
  final String alias;

  const PresetAppIconModel({
    required this.id,
    required this.name,
    required this.description,
    required this.assetPath,
    required this.alias,
  });

  bool get isDefault => id == 'default';
}

/// 官方内置 3 套高清应用图标预设 (不可删除，支持自由切换)
const List<PresetAppIconModel> kPresetAppIcons = [
  PresetAppIconModel(
    id: 'default',
    name: '官方默认',
    description: 'Review 官方标准应用图标',
    assetPath: 'assets/icons/app_icon_default.png',
    alias: 'default',
  ),
  PresetAppIconModel(
    id: 'alias1',
    name: '质感经典',
    description: '深邃内敛，经典雅致视觉',
    assetPath: 'assets/icons/app_icon_1.png',
    alias: 'alias1',
  ),
  PresetAppIconModel(
    id: 'alias2',
    name: '活力新潮',
    description: '灵动纯粹，现代美学设计',
    assetPath: 'assets/icons/app_icon_2.png',
    alias: 'alias2',
  ),
];

class CustomAppIconState {
  final String currentId;

  const CustomAppIconState({
    this.currentId = 'default',
  });

  PresetAppIconModel get currentIcon {
    return kPresetAppIcons.firstWhere(
      (e) => e.id == currentId,
      orElse: () => kPresetAppIcons.first,
    );
  }

  String get currentAssetPath => currentIcon.assetPath;
  String get currentDisplayName => currentIcon.name;
  bool get isDefault => currentId == 'default';

  CustomAppIconState copyWith({String? currentId}) {
    return CustomAppIconState(
      currentId: currentId ?? this.currentId,
    );
  }
}

class CustomAppIconNotifier extends StateNotifier<CustomAppIconState> {
  final StorageService _storage;
  static const MethodChannel _channel = MethodChannel('com.sharelite/cookies');

  CustomAppIconNotifier(this._storage) : super(const CustomAppIconState()) {
    _loadFromStorage();
    syncWithSystem();
  }

  void _loadFromStorage() {
    final curId = _storage.getCurrentPresetAppIconId();
    final exists = kPresetAppIcons.any((e) => e.id == curId);
    final effectiveId = exists ? curId : 'default';
    state = CustomAppIconState(currentId: effectiveId);
  }

  /// 真实同步原生系统底层 PackageManager 当前激活的组件别名，彻底避免本地存储与系统状态脱节
  Future<void> syncWithSystem() async {
    try {
      if (Platform.isAndroid) {
        final actualAlias = await _channel.invokeMethod<String>('getCurrentAppIcon');
        if (actualAlias != null && kPresetAppIcons.any((e) => e.id == actualAlias)) {
          if (state.currentId != actualAlias) {
            await _storage.setCurrentPresetAppIconId(actualAlias);
            state = state.copyWith(currentId: actualAlias);
          }
        }
      }
    } catch (_) {}
  }

  /// 切换应用图标 (通过原生 activity-alias 物理替换桌面图标并可退出刷新)
  Future<bool> switchIcon(String iconId, {bool killProcessAfter = true}) async {
    final match = kPresetAppIcons.where((e) => e.id == iconId);
    if (match.isEmpty) return false;

    final target = match.first;
    await _storage.setCurrentPresetAppIconId(target.id);
    state = state.copyWith(currentId: target.id);

    try {
      await _channel.invokeMethod('switchAppIcon', {'alias': target.alias});
    } catch (_) {}

    if (killProcessAfter) {
      await killAppProcess();
    }
    return true;
  }

  /// 杀死当前应用进程以强制桌面 Launcher 刷新缓存
  Future<void> killAppProcess() async {
    try {
      await _channel.invokeMethod('killProcess');
    } catch (_) {
      exit(0);
    }
  }
}

final customAppIconProvider =
    StateNotifierProvider<CustomAppIconNotifier, CustomAppIconState>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return CustomAppIconNotifier(storage);
});
