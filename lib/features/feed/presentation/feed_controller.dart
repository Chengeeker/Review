import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/storage/storage_service.dart';
import '../data/feed_repository.dart';
import '../data/models/weibo_status_model.dart';

class FeedState {
  final List<WeiboStatusModel> statuses;
  final List<WeiboGroupModel> userGroups;
  final List<Map<String, String>> customDefaultGroups;
  final List<Map<String, String>> customPersonalGroups;
  final List<Map<String, String>> customHotGroups;
  final String currentCategory;
  final String currentCategoryTitle;
  final bool isLoading;
  final int page;
  final String maxId;
  final String sinceId;
  final bool hasMore;
  final String? errorMessage;

  const FeedState({
    required this.statuses,
    this.userGroups = const [],
    this.customDefaultGroups = const [],
    this.customPersonalGroups = const [],
    this.customHotGroups = const [],
    required this.currentCategory,
    this.currentCategoryTitle = '最新微博',
    this.isLoading = false,
    this.page = 1,
    this.maxId = '0',
    this.sinceId = '0',
    this.hasMore = true,
    this.errorMessage,
  });

  FeedState copyWith({
    List<WeiboStatusModel>? statuses,
    List<WeiboGroupModel>? userGroups,
    List<Map<String, String>>? customDefaultGroups,
    List<Map<String, String>>? customPersonalGroups,
    List<Map<String, String>>? customHotGroups,
    String? currentCategory,
    String? currentCategoryTitle,
    bool? isLoading,
    int? page,
    String? maxId,
    String? sinceId,
    bool? hasMore,
    String? errorMessage,
  }) {
    return FeedState(
      statuses: statuses ?? this.statuses,
      userGroups: userGroups ?? this.userGroups,
      customDefaultGroups: customDefaultGroups ?? this.customDefaultGroups,
      customPersonalGroups: customPersonalGroups ?? this.customPersonalGroups,
      customHotGroups: customHotGroups ?? this.customHotGroups,
      currentCategory: currentCategory ?? this.currentCategory,
      currentCategoryTitle: currentCategoryTitle ?? this.currentCategoryTitle,
      isLoading: isLoading ?? this.isLoading,
      page: page ?? this.page,
      maxId: maxId ?? this.maxId,
      sinceId: sinceId ?? this.sinceId,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class FeedController extends StateNotifier<FeedState> {
  final FeedRepository _repository;
  final StorageService _storage;
  final Ref _ref;
  int _generation = 0;

  static const List<Map<String, String>> defaultInitialGroups = [
    {'id': 'all_follow', 'name': '全部关注'},
    {'id': 'friends', 'name': '最新微博'},
    {'id': '4152890832681124', 'name': '特别关注'},
    {'id': 'friends_circle', 'name': '好友圈'},
    {'id': 'original', 'name': '原创'},
    {'id': 'video', 'name': '视频'},
    {'id': 'chaohua', 'name': '超话社区'},
    {'id': 'v_plus', 'name': 'V+微博'},
    {'id': 'group_wb', 'name': '群微博'},
  ];

  static const List<Map<String, String>> defaultInitialPersonalGroups = [
    {'id': '4155102849566877', 'name': '游戏'},
    {'id': '4204387791912034', 'name': '电影'},
    {'id': '4837511216240175', 'name': 'vivo'},
    {'id': '4152890832681125', 'name': '名人明星'},
    {'id': '4152890832681129', 'name': '同学'},
    {'id': '4152890832378839', 'name': '同事'},
    {'id': '100056367342728', 'name': '悄悄关注'},
  ];

  FeedController(this._repository, this._storage, this._ref)
      : super(const FeedState(
          statuses: [],
          currentCategory: 'friends',
          currentCategoryTitle: '最新微博',
          isLoading: true,
        )) {
    _loadInitialGroupPreferences();
    initAndLoad();
    _ref.listen<AuthState>(authProvider, (prev, next) {
      if (prev?.isLoggedIn != next.isLoggedIn || prev?.uid != next.uid) {
        initAndLoad();
      }
    });
  }

  void _loadInitialGroupPreferences() {
    List<Map<String, String>> defGroups = defaultInitialGroups;
    List<Map<String, String>> persGroups = defaultInitialPersonalGroups;
    List<Map<String, String>> hotGroups = [];

    final defJson = _storage.getSavedDefaultGroupsJson();
    if (defJson != null) {
      try {
        final list = jsonDecode(defJson) as List;
        final parsed = list.map((e) => Map<String, String>.from(e as Map)).toList();
        if (parsed.isNotEmpty) defGroups = parsed;
      } catch (_) {}
    }

    final persJson = _storage.getSavedPersonalGroupsJson();
    if (persJson != null) {
      try {
        final list = jsonDecode(persJson) as List;
        final parsed = list.map((e) => Map<String, String>.from(e as Map)).toList();
        if (parsed.isNotEmpty) persGroups = parsed;
      } catch (_) {}
    }

    final hotJson = _storage.getSavedHotGroupsJson();
    if (hotJson != null) {
      try {
        final list = jsonDecode(hotJson) as List;
        final parsed = list.map((e) => Map<String, String>.from(e as Map)).toList();
        if (parsed.isNotEmpty) hotGroups = parsed;
      } catch (_) {}
    }

    if (persGroups.isEmpty) {
      persGroups = defaultInitialPersonalGroups;
    }

    state = state.copyWith(
      customDefaultGroups: defGroups,
      customPersonalGroups: persGroups,
      customHotGroups: hotGroups,
    );
  }

  Future<void> updateGroupPreferences({
    required List<Map<String, String>> defaultGroups,
    required List<Map<String, String>> personalGroups,
    required List<Map<String, String>> hotGroups,
  }) async {
    await _storage.setSavedDefaultGroupsJson(jsonEncode(defaultGroups));
    await _storage.setSavedPersonalGroupsJson(jsonEncode(personalGroups));
    await _storage.setSavedHotGroupsJson(jsonEncode(hotGroups));

    state = state.copyWith(
      customDefaultGroups: defaultGroups,
      customPersonalGroups: personalGroups.isNotEmpty ? personalGroups : defaultInitialPersonalGroups,
      customHotGroups: hotGroups,
    );
  }

  Future<void> initAndLoad() async {
    try {
      final groupsResult = await _repository.getUserGroups();

      // 1. 实时抓取到微博云端个人分组
      if (groupsResult.personalGroups.isNotEmpty) {
        final mapped = groupsResult.personalGroups
            .where((g) => g.title != '特别关注')
            .map((g) => {'id': g.gid, 'name': g.title})
            .toList();

        if (mapped.isNotEmpty) {
          state = state.copyWith(
            userGroups: groupsResult.personalGroups,
            customPersonalGroups: mapped,
          );
          await _storage.setSavedPersonalGroupsJson(jsonEncode(mapped));
        }
      }
    } catch (_) {}

    // 2. 保证 customPersonalGroups 始终不为空
    if (state.customPersonalGroups.isEmpty) {
      state = state.copyWith(
        customPersonalGroups: defaultInitialPersonalGroups,
      );
    }

    await refreshFeed();
  }

  Future<void> setCategory(String category, [String? title]) async {
    String resolvedTitle = title ?? state.currentCategoryTitle;
    if (title == null) {
      if (category == 'friends' || category == 'all_follow') {
        resolvedTitle = '最新微博';
      } else if (category == '4152890832681124') {
        resolvedTitle = '特别关注';
      } else {
        final match = state.userGroups.where((g) => g.gid == category).firstOrNull;
        if (match != null) {
          resolvedTitle = match.title;
        } else {
          final customMatch = state.customPersonalGroups.where((g) => g['id'] == category).firstOrNull;
          if (customMatch != null) resolvedTitle = customMatch['name'] ?? resolvedTitle;
        }
      }
    }

    state = state.copyWith(
      currentCategory: category,
      currentCategoryTitle: resolvedTitle,
      statuses: [],
      page: 1,
      maxId: '0',
      sinceId: '0',
      isLoading: true,
      hasMore: true,
      errorMessage: null,
    );
    await refreshFeed();
  }

  Future<void> refreshFeed() async {
    final currentGen = ++_generation;
    state = state.copyWith(isLoading: true, errorMessage: null);
    final auth = _ref.read(authProvider);

    final result = await _repository.getTimeline(
      category: state.currentCategory,
      userUid: auth.uid,
      page: 1,
      maxId: '0',
      sinceId: '0',
    );

    // If another request was started while this one was in-flight, discard stale result
    if (currentGen != _generation) return;

    final nextMaxId = result.maxId != '0'
        ? result.maxId
        : (result.statuses.isNotEmpty ? result.statuses.last.id : '0');

    state = state.copyWith(
      statuses: result.statuses,
      page: 1,
      maxId: nextMaxId,
      sinceId: result.sinceId,
      hasMore: result.statuses.isNotEmpty,
      isLoading: false,
      errorMessage: result.error != null
          ? result.error
          : (result.statuses.isEmpty
              ? (state.currentCategory == 'friends' && !auth.isLoggedIn
                  ? '当前为访客模式，登录后即可查看关注博主动态'
                  : '暂无微博内容')
              : null),
    );
  }

  bool _isLoadingMore = false;

  Future<bool> loadMore() async {
    if (!state.hasMore || state.isLoading || _isLoadingMore) return false;
    final currentGen = _generation;
    _isLoadingMore = true;

    try {
      final auth = _ref.read(authProvider);
      final nextPage = state.page + 1;
      // 必须使用微博后端返回的精确游标 maxId，若不存在则回退至末条微博 ID
      final cursor = (state.maxId != '0' && state.maxId.isNotEmpty)
          ? state.maxId
          : (state.statuses.isNotEmpty ? state.statuses.last.id : '0');

      final result = await _repository.getTimeline(
        category: state.currentCategory,
        userUid: auth.uid,
        page: nextPage,
        maxId: cursor,
        sinceId: '0', // 下滑加载历史微博时严禁传递 sinceId，否则服务端会按最新时间过滤导致空结果
      );

      if (currentGen != _generation) return false;

      if (result.statuses.isEmpty) {
        state = state.copyWith(hasMore: false);
        return false;
      }

      // Deduplicate new tweets
      final existingIds = state.statuses.map((s) => s.id).toSet();
      final uniqueNew = result.statuses.where((s) => !existingIds.contains(s.id)).toList();

      final nextMaxId = (result.maxId != '0' && result.maxId.isNotEmpty)
          ? result.maxId
          : (uniqueNew.isNotEmpty ? uniqueNew.last.id : cursor);

      if (uniqueNew.isNotEmpty) {
        state = state.copyWith(
          statuses: [...state.statuses, ...uniqueNew],
          page: nextPage,
          maxId: nextMaxId,
          hasMore: true,
        );
        return true;
      } else {
        // 重叠时继续推进游标向下探查
        state = state.copyWith(
          page: nextPage,
          maxId: nextMaxId,
          hasMore: true,
        );
        return true;
      }
    } catch (_) {
      return false;
    } finally {
      _isLoadingMore = false;
    }
  }

  void syncLikeLocally(String statusId, bool liked, int attitudesCount) {
    final updated = state.statuses.map((s) {
      if (s.id == statusId) {
        return s.copyWith(
          liked: liked,
          attitudesCount: attitudesCount,
        );
      }
      return s;
    }).toList();
    state = state.copyWith(statuses: updated);
  }

  Future<bool> toggleLikeLocally(String statusId, {bool? currentlyLiked}) async {
    final previousStatuses = state.statuses;
    bool wasLiked = currentlyLiked ?? false;
    final updated = state.statuses.map((s) {
      if (s.id == statusId) {
        wasLiked = currentlyLiked ?? s.liked;
        final nextLiked = !wasLiked;
        return s.copyWith(
          liked: nextLiked,
          attitudesCount: nextLiked ? s.attitudesCount + 1 : (s.attitudesCount > 0 ? s.attitudesCount - 1 : 0),
        );
      }
      return s;
    }).toList();

    state = state.copyWith(statuses: updated);

    try {
      final success = await _repository.toggleLike(statusId, currentlyLiked: wasLiked);
      if (!success) {
        state = state.copyWith(statuses: previousStatuses);
        return false;
      }
      return true;
    } catch (_) {
      state = state.copyWith(statuses: previousStatuses);
      return false;
    }
  }

  void removeStatusLocally(String statusId) {
    final updated = state.statuses.where((s) => s.id != statusId).toList();
    state = state.copyWith(statuses: updated);
  }

  Future<bool> deleteStatus(String statusId) async {
    final previousStatuses = state.statuses;
    removeStatusLocally(statusId);
    try {
      final success = await _repository.deleteTweet(statusId);
      if (!success) {
        state = state.copyWith(statuses: previousStatuses);
        return false;
      }
      return true;
    } catch (_) {
      state = state.copyWith(statuses: previousStatuses);
      return false;
    }
  }
}

final feedControllerProvider =
    StateNotifierProvider<FeedController, FeedState>((ref) {
  final repository = ref.watch(feedRepositoryProvider);
  final storage = ref.watch(storageServiceProvider);
  return FeedController(repository, storage, ref);
});

/// Timeline 滚动状态与双击/单击手势交互处理器
class TimelineScrollNotifier extends StateNotifier<double> {
  TimelineScrollNotifier(this._ref) : super(0.0);

  final Ref _ref;
  ScrollController? scrollController;

  void attachController(ScrollController controller) {
    scrollController = controller;
  }

  void detachController() {
    scrollController = null;
  }

  /// 单击时间线底栏：
  /// - 若当前滚动位置 > 50：记录当前位置，并平滑滚动到顶部；
  /// - 若当前已经在顶部（offset <= 50）且存在记录位置：返回刚刚看的那篇文章的位置。
  void handleSingleTap() {
    final controller = scrollController;
    if (controller == null || !controller.hasClients) return;

    final currentOffset = controller.offset;
    if (currentOffset > 50) {
      // 记录当前位置
      state = currentOffset;
      controller.animateTo(
        0.0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else if (state > 50) {
      // 当前已经在顶部，再次单击回到刚刚看的那篇文章的位置
      final target = state;
      state = 0.0;
      controller.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      // 已经在顶部且无历史位置，轻微触顶
      controller.animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// 双击时间线底栏：回到顶部并刷新界面
  void handleDoubleTap() {
    final controller = scrollController;

    if (controller != null && controller.hasClients && controller.offset > 0) {
      controller.animateTo(
        0.0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
    _ref.read(feedControllerProvider.notifier).refreshFeed();
  }

  /// 双击顶栏：
  /// - 第一次双击（当前不在顶部）：回到顶部；
  /// - 第二次双击（当前已经在顶部）：触发刷新界面。
  void handleTopBarDoubleTap() {
    final controller = scrollController;

    if (controller != null && controller.hasClients && controller.offset > 50) {
      // 记录位置并回到顶部
      state = controller.offset;
      controller.animateTo(
        0.0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      // 已经在顶部，触发刷新
      _ref.read(feedControllerProvider.notifier).refreshFeed();
    }
  }
}

final timelineScrollProvider = StateNotifierProvider<TimelineScrollNotifier, double>((ref) {
  return TimelineScrollNotifier(ref);
});
