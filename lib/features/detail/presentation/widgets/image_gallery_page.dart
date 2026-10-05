import 'dart:async';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../core/utils/app_toast.dart';
import '../../../../core/utils/haptic_feedback_util.dart';
import '../../../feed/data/models/weibo_status_model.dart';
import '../../../feed/presentation/widgets/weibo_video_player_page.dart';

/// Stable matching identity for a thumbnail and its fullscreen gallery image.
/// The scope is unique to the originating gallery widget, so two copies of the
/// same post on one route cannot accidentally claim the same Hero.
@immutable
class ImageGalleryHeroTag {
  const ImageGalleryHeroTag({
    required this.scope,
    required this.index,
    required this.mediaIdentity,
  });

  final Object scope;
  final int index;
  final String mediaIdentity;

  factory ImageGalleryHeroTag.forPic({
    required Object scope,
    required int index,
    required WeiboPicModel pic,
  }) =>
      ImageGalleryHeroTag(
        scope: scope,
        index: index,
        mediaIdentity: '${pic.pid}\u0000${pic.previewUrl}',
      );

  @override
  bool operator ==(Object other) =>
      other is ImageGalleryHeroTag &&
      identical(scope, other.scope) &&
      index == other.index &&
      mediaIdentity == other.mediaIdentity;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(scope), index, mediaIdentity);
}

/// Wraps a tapped source thumbnail with the same tag used by [ImageGalleryPage].
class ImageGalleryHeroThumbnail extends StatelessWidget {
  const ImageGalleryHeroThumbnail({
    super.key,
    required this.scope,
    required this.index,
    required this.pic,
    required this.child,
  });

  final Object scope;
  final int index;
  final WeiboPicModel pic;
  final Widget child;

  @override
  Widget build(BuildContext context) => Hero(
        tag: ImageGalleryHeroTag.forPic(
          scope: scope,
          index: index,
          pic: pic,
        ),
        child: child,
      );
}

/// Fullscreen Interactive Image & Live Photo Gallery with Physics Spring Transitions & Real-time Live Video Playback
class ImageGalleryPage extends ConsumerStatefulWidget {
  final List<WeiboPicModel> pics;
  final int initialIndex;
  final String statusId;
  final bool isDetail;
  final String? authorName;
  final Object? heroScope;

  const ImageGalleryPage({
    super.key,
    required this.pics,
    required this.initialIndex,
    required this.statusId,
    this.isDetail = false,
    this.authorName,
    this.heroScope,
  });

  @override
  ConsumerState<ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends ConsumerState<ImageGalleryPage>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _mediaChannel =
      MethodChannel('com.sharelite/cookies');
  late int _currentIndex;
  late final ValueNotifier<int> _activeMediaIndex;
  late final ExtendedPageController _pageController;
  late final PageController _thumbnailController;
  final GlobalKey<ExtendedImageSlidePageState> _slidePageKey =
      GlobalKey<ExtendedImageSlidePageState>();
  bool _isSaving = false;
  bool _showChrome = true;
  bool _thumbnailUserScrolling = false;
  bool _thumbnailSettling = false;
  int _thumbnailSyncEpoch = 0;

  // Live Photo Controller Cache
  final Map<int, VideoPlayerController> _liveControllers = {};
  final Map<int, bool> _liveInitialized = {};
  bool _isPlayingLive = false;
  bool _pendingLivePlay = false;

  late final AnimationController _doubleTapAnimationController;
  Animation<double>? _doubleTapAnimation;
  Function()? _doubleTapListener;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _activeMediaIndex = ValueNotifier(widget.initialIndex);
    _pageController = ExtendedPageController(initialPage: widget.initialIndex);
    _thumbnailController = PageController(
        initialPage: widget.initialIndex, viewportFraction: 0.16);
    _thumbnailController.addListener(_syncMainPageToThumbnail);
    _doubleTapAnimationController = AnimationController(
      duration: const Duration(milliseconds: 260),
      vsync: this,
    );
    _initLiveControllerForIndex(_currentIndex);
  }

  @override
  void dispose() {
    _restoreSystemUi();
    _doubleTapAnimationController.dispose();
    _pageController.dispose();
    _thumbnailController.removeListener(_syncMainPageToThumbnail);
    _thumbnailController.dispose();
    _activeMediaIndex.dispose();
    for (final controller in _liveControllers.values) {
      controller.dispose();
    }
    _liveControllers.clear();
    super.dispose();
  }

  void _restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _setNativeStatusBarVisible(true);
  }

  void _setSystemStatusBarVisible(bool visible) {
    _setNativeStatusBarVisible(visible);
  }

  void _setNativeStatusBarVisible(bool visible) {
    unawaited(
      _mediaChannel.invokeMethod<void>(
        'setImageGalleryStatusBarVisible',
        {'visible': visible},
      ).catchError((_) {}),
    );
  }

  void _initLiveControllerForIndex(int index) {
    if (index < 0 || index >= widget.pics.length) return;
    final pic = widget.pics[index];
    if (pic.isLivePhoto &&
        pic.livePhotoVideoUrl != null &&
        pic.livePhotoVideoUrl!.isNotEmpty) {
      if (_liveControllers.containsKey(index)) return;

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(pic.livePhotoVideoUrl!),
        httpHeaders: ApiConstants.imageHeaders,
      );

      _liveControllers[index] = controller;
      controller.initialize().then((_) {
        if (mounted) {
          setState(() {
            _liveInitialized[index] = true;
            if (_pendingLivePlay && _currentIndex == index) {
              _pendingLivePlay = false;
              _isPlayingLive = true;
            }
          });
          controller.setLooping(true);
          if (_isPlayingLive && _currentIndex == index) {
            controller.play();
          }
        }
      }).catchError((e) {
        debugPrint('Live Photo init error: $e');
      });
    }
  }

  void _toggleLivePlay() {
    // 该按钮使用普通 InkSplash，并在动作入口只触发一次轻触。
    // 普通水波纹不提供业务触感，动作入口只触发一次反馈。
    HapticFeedbackUtil.light();
    final controller = _liveControllers[_currentIndex];
    if (controller == null || !(_liveInitialized[_currentIndex] ?? false)) {
      // 初始化尚未完成时记录播放意图，避免首次点击只有震动而没有动作。
      _pendingLivePlay = !_pendingLivePlay;
      _initLiveControllerForIndex(_currentIndex);
      return;
    }

    // 播放/暂停只由本方法负责触感，避免同一手势重复震动。
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _isPlayingLive = false;
      } else {
        controller.play();
        _isPlayingLive = true;
      }
    });
  }

  Future<void> _saveCurrentImage() async {
    if (_isSaving) return;
    HapticFeedbackUtil.light();

    final pic = widget.pics[_currentIndex];
    if (pic.isVideo) {
      await _performSaveMedia(isVideo: true);
      return;
    }
    if (pic.isLivePhoto &&
        pic.livePhotoVideoUrl != null &&
        pic.livePhotoVideoUrl!.isNotEmpty) {
      // Show choice dialog for Live Photo
      final choice = await showModalBottomSheet<int>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  const Text('保存实况照片',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('保存静态高清大图'),
                    onTap: () => Navigator.pop(ctx, 1),
                  ),
                  ListTile(
                    leading: const Icon(Icons.motion_photos_on_rounded),
                    title: const Text('保存 Live 动图 / 视频'),
                    onTap: () => Navigator.pop(ctx, 2),
                  ),
                  ListTile(
                    leading: const Icon(Icons.download_for_offline_outlined),
                    title: const Text('全部保存 (高清大图 + Live 视频)'),
                    onTap: () => Navigator.pop(ctx, 3),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (choice == null) return;
      if (choice == 1) {
        await _performSaveMedia(isVideo: false);
      } else if (choice == 2) {
        await _performSaveMedia(isVideo: true);
      } else if (choice == 3) {
        await _performSaveMedia(isVideo: false);
        await _performSaveMedia(isVideo: true);
      }
    } else {
      await _performSaveMedia(isVideo: false);
    }
  }

  Future<void> _performSaveMedia({required bool isVideo}) async {
    setState(() => _isSaving = true);

    try {
      final pic = widget.pics[_currentIndex];
      final url = isVideo
          ? (pic.isVideo
              ? pic.videoUrl ?? ''
              : pic.livePhotoVideoUrl ?? pic.largeUrl)
          : (pic.largeUrl.isNotEmpty ? pic.largeUrl : pic.bmiddleUrl);

      // 1. Download bytes
      final dio = Dio();
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: ApiConstants.imageHeaders,
        ),
      );

      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('下载媒体数据为空');
      }

      // 2. Resolve sub folder based on user settings
      final storage = ref.read(storageServiceProvider);
      final pathType = storage.getImageSavePathType();
      String relativeSubDir = 'Review';

      if (pathType == 1) {
        final myNick = ref.read(authProvider).nickname ?? '我的微博';
        relativeSubDir = 'Review/$myNick';
      } else if (pathType == 2) {
        final author =
            (widget.authorName != null && widget.authorName!.isNotEmpty)
                ? widget.authorName!
                : '微博博主';
        relativeSubDir = 'Review/$author';
      }

      final isGif = url.toLowerCase().contains('.gif') || pic.isGif;
      final ext = isVideo ? '.mp4' : (isGif ? '.gif' : '.jpg');
      final fileName =
          'wb_${widget.statusId}_${_currentIndex}_${DateTime.now().millisecondsSinceEpoch}$ext';

      // 3. Save to System MediaStore / Gallery
      final savedPath = await _mediaChannel.invokeMethod<String>(
        'saveMediaToGallery',
        {
          'bytes': Uint8List.fromList(bytes),
          'fileName': fileName,
          'relativeSubDir': relativeSubDir,
          'isVideo': isVideo,
          'mimeType':
              isVideo ? 'video/mp4' : (isGif ? 'image/gif' : 'image/jpeg'),
        },
      );

      HapticFeedbackUtil.medium();
      if (mounted) {
        AppToast.show(
          context,
          '🎉 ${isVideo ? "Live 视频" : "图片"}已成功保存至相册：${savedPath ?? "Pictures/$relativeSubDir"}',
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '保存失败: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _toggleChrome() {
    if (!mounted) return;
    final showChrome = !_showChrome;
    setState(() => _showChrome = showChrome);
    _setSystemStatusBarVisible(showChrome);
  }

  void _handleGalleryTap(TapUpDetails details) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final x = details.globalPosition.dx;
    final isMiddleThird = x >= screenWidth / 3 && x < screenWidth * 2 / 3;

    if (isMiddleThird) {
      _toggleChrome();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _selectThumbnail(int index) {
    if (index == _currentIndex || !_pageController.hasClients) return;
    _pageController.jumpToPage(index);
  }

  void _syncMainPageToThumbnail() {
    if (!_thumbnailUserScrolling ||
        !_thumbnailController.hasClients ||
        !_pageController.hasClients) {
      return;
    }

    final page = (_thumbnailController.page ?? _currentIndex.toDouble())
        .clamp(0.0, (widget.pics.length - 1).toDouble());
    final mainPosition = _pageController.position;
    final targetPixels =
        (mainPosition.minScrollExtent + page * mainPosition.viewportDimension)
            .clamp(mainPosition.minScrollExtent, mainPosition.maxScrollExtent)
            .toDouble();
    if ((mainPosition.pixels - targetPixels).abs() > 0.5) {
      // Mirror the reel's fractional page position directly. A queued series
      // of animateToPage calls falls behind a fast fling by design.
      mainPosition.jumpTo(targetPixels);
    }
  }

  void _activateCurrentMedia() {
    if (!mounted) return;
    _activeMediaIndex.value = _currentIndex;
    _initLiveControllerForIndex(_currentIndex);
  }

  void _settleThumbnailScroll() {
    if (_thumbnailSettling ||
        !_thumbnailController.hasClients ||
        !_pageController.hasClients) {
      return;
    }

    final target = (_thumbnailController.page ?? _currentIndex.toDouble())
        .round()
        .clamp(0, widget.pics.length - 1);
    final epoch = ++_thumbnailSyncEpoch;
    _thumbnailUserScrolling = false;
    _thumbnailSettling = true;
    const duration = Duration(milliseconds: 120);
    unawaited(Future.wait<void>([
      _thumbnailController.animateToPage(target,
          duration: duration, curve: Curves.easeOutCubic),
      _pageController.animateToPage(target,
          duration: duration, curve: Curves.easeOutCubic),
    ]).whenComplete(() {
      if (!mounted || epoch != _thumbnailSyncEpoch) return;
      _thumbnailSettling = false;
      _activateCurrentMedia();
    }));
  }

  Widget _withGalleryHero(int index, WeiboPicModel pic, Widget child) {
    final scope = widget.heroScope;
    if (scope == null || pic.isVideo) return child;
    return Hero(
      tag: ImageGalleryHeroTag.forPic(
        scope: scope,
        index: index,
        pic: pic,
      ),
      child: child,
    );
  }

  bool _handleThumbnailScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _thumbnailSyncEpoch++;
      _thumbnailSettling = false;
      _thumbnailUserScrolling = true;
      _activeMediaIndex.value = -1;
      _isPlayingLive = false;
      _pendingLivePlay = false;
      for (final controller in _liveControllers.values) {
        if (controller.value.isPlaying) controller.pause();
      }
      setState(() {});
    } else if (notification is ScrollEndNotification &&
        _thumbnailUserScrolling) {
      _settleThumbnailScroll();
    }
    return false;
  }

  Widget _buildThumbnailStrip() {
    return SizedBox(
      key: const ValueKey('gallery-thumbnail-strip'),
      height: 64,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleThumbnailScroll,
        child: PageView.builder(
          controller: _thumbnailController,
          physics: const ClampingScrollPhysics(),
          pageSnapping: false,
          itemCount: widget.pics.length,
          itemBuilder: (context, index) {
            final selected = index == _currentIndex;
            return Semantics(
              label: '第 ${index + 1} 张图片',
              selected: selected,
              button: true,
              child: GestureDetector(
                key: ValueKey('gallery-thumbnail-$index'),
                onTap: () {
                  HapticFeedbackUtil.light();
                  _thumbnailSyncEpoch++;
                  _thumbnailUserScrolling = false;
                  _thumbnailSettling = false;
                  _thumbnailController.jumpToPage(index);
                  _selectThumbnail(index);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: selected ? Colors.white : Colors.transparent,
                          width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(fit: StackFit.expand, children: [
                        ExtendedImage.network(widget.pics[index].previewUrl,
                            headers: ApiConstants.imageHeaders,
                            fit: BoxFit.cover,
                            cacheWidth: 160,
                            cache: true),
                        if (!selected)
                          ColoredBox(
                              color: Colors.white.withValues(alpha: 0.5)),
                        if (widget.pics[index].isVideo)
                          const Center(
                              child: Icon(Icons.play_circle_fill_rounded,
                                  color: Colors.white, size: 20)),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPic =
        widget.pics.isNotEmpty ? widget.pics[_currentIndex] : null;
    final isCurrentLive = currentPic?.isLivePhoto == true &&
        currentPic?.livePhotoVideoUrl != null;

    return ExtendedImageSlidePage(
      key: _slidePageKey,
      // 图片画廊的主手势是左右翻页；限制退出手势为水平轴，避免
      // 不够水平的滑动被外层 SlidePage 接管后产生斜向拖拽和卡顿感。
      slideAxis: SlideAxis.horizontal,
      slideType: SlideType.onlyImage,
      slidePageBackgroundHandler: (Offset offset, Size pageSize) {
        double opacity = offset.dx.abs() / (pageSize.width / 2.0);
        return Colors.black.withValues(alpha: math.max(0.0, 1.0 - opacity));
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Gesture PageView with Physics-based Spring Morphing
            Padding(
              padding: EdgeInsets.only(
                  bottom: _showChrome && widget.pics.length > 1
                      ? MediaQuery.paddingOf(context).bottom + 120
                      : 0),
              child: GestureDetector(
                onTapUp: _handleGalleryTap,
                child: NotificationListener<ScrollStartNotification>(
                  onNotification: (notification) {
                    if (notification.depth == 0 &&
                        notification.dragDetails != null) {
                      _thumbnailSyncEpoch++;
                      _thumbnailUserScrolling = false;
                      _thumbnailSettling = false;
                    }
                    return false;
                  },
                  child: ExtendedImageGesturePageView.builder(
                    controller: _pageController,
                    // 显式启用分页滚动物理，避免关闭滑出手势后部分横向拖动
                    // 只被图片手势识别器消费，却没有推动 PageView。
                    physics: const ClampingScrollPhysics(),
                    itemCount: widget.pics.length,
                    onPageChanged: (index) {
                      final didChange = index != _currentIndex;
                      if (didChange && _thumbnailUserScrolling) {
                        HapticFeedbackUtil.selectionTick();
                      } else if (!_thumbnailUserScrolling &&
                          !_thumbnailSettling) {
                        _activeMediaIndex.value = index;
                        _initLiveControllerForIndex(index);
                      }
                      setState(() {
                        _currentIndex = index;
                        _isPlayingLive = false;
                        _pendingLivePlay = false;
                      });
                      // Pause previous live videos
                      for (final entry in _liveControllers.entries) {
                        if (entry.key != index && entry.value.value.isPlaying) {
                          entry.value.pause();
                        }
                      }
                      if (!_thumbnailUserScrolling &&
                          !_thumbnailSettling &&
                          _thumbnailController.hasClients) {
                        // A main-image gesture takes ownership, cancelling any
                        // old thumbnail inertia without feeding selection back.
                        _thumbnailController.jumpToPage(index);
                      }
                    },
                    itemBuilder: (context, index) {
                      final pic = widget.pics[index];
                      if (pic.isVideo) {
                        // PageView may retain offscreen children. An explicit
                        // active-index signal tears down hidden players too.
                        return ValueListenableBuilder<int>(
                          valueListenable: _activeMediaIndex,
                          builder: (context, activeIndex, _) =>
                              activeIndex == index
                                  ? WeiboVideoPlayerPage(
                                      key: ValueKey('gallery-video-$index'),
                                      videoUrl: pic.videoUrl ?? '',
                                      statusId: widget.statusId,
                                      coverUrl: pic.previewUrl,
                                      title: pic.videoTitle,
                                      authorName: widget.authorName,
                                      embedded: true,
                                      onToggleChrome: _toggleChrome,
                                    )
                                  : ExtendedImage.network(pic.previewUrl,
                                      headers: ApiConstants.imageHeaders,
                                      fit: BoxFit.contain,
                                      cache: true),
                        );
                      }
                      final controller = _liveControllers[index];
                      final isInitialized = _liveInitialized[index] ?? false;

                      final isLongPic = pic.isLong ||
                          (pic.height > 0 &&
                              pic.width > 0 &&
                              pic.height / pic.width > 2.0);

                      final foregroundImage = ExtendedImage.network(
                        pic.originalUrl.isNotEmpty
                            ? pic.originalUrl
                            : (pic.largeUrl.isNotEmpty
                                ? pic.largeUrl
                                : pic.bmiddleUrl),
                        width: double.infinity,
                        height: double.infinity,
                        headers: ApiConstants.imageHeaders,
                        cache: true,
                        fit: BoxFit.contain,
                        mode: ExtendedImageMode.gesture,
                        // 浏览多图时由横向 PageView 统一处理单指拖动；否则
                        // 斜向拖动可能被识别为滑出并直接销毁画廊页面。
                        enableSlideOutPage: false,
                        onDoubleTap: (ExtendedImageGestureState state) {
                          final pointerDownPosition = state.pointerDownPosition;
                          final begin = state.gestureDetails!.totalScale ?? 1.0;
                          double end = 1.0;
                          if (begin <= 1.05) {
                            end = isLongPic ? 3.5 : 2.5;
                          } else if (begin <= 3.6) {
                            end = 6.0;
                          } else {
                            end = 1.0;
                          }

                          _doubleTapAnimationController.stop();
                          _doubleTapAnimationController.reset();

                          if (_doubleTapListener != null) {
                            _doubleTapAnimation
                                ?.removeListener(_doubleTapListener!);
                          }

                          _doubleTapAnimation =
                              Tween<double>(begin: begin, end: end).animate(
                            CurvedAnimation(
                              parent: _doubleTapAnimationController,
                              curve: Curves.easeOutCubic,
                            ),
                          );

                          _doubleTapListener = () {
                            state.handleDoubleTap(
                              scale: _doubleTapAnimation!.value,
                              doubleTapPosition: pointerDownPosition,
                            );
                          };
                          _doubleTapAnimation!.addListener(_doubleTapListener!);

                          _doubleTapAnimationController.forward();
                        },
                        initGestureConfigHandler: (state) {
                          return GestureConfig(
                            minScale: 0.8,
                            animationMinScale: 0.6,
                            maxScale: 8.0,
                            animationMaxScale: 9.0,
                            speed: 1.0,
                            inertialSpeed: 120.0,
                            initialScale: 1.0,
                            inPageView: true,
                            initialAlignment: isLongPic
                                ? InitialAlignment.topCenter
                                : InitialAlignment.center,
                          );
                        },
                      );
                      final backgroundUrl =
                          pic.webpageCardBackgroundUrl?.trim();
                      final hasBackground = backgroundUrl != null &&
                          backgroundUrl.isNotEmpty &&
                          backgroundUrl != pic.originalUrl &&
                          backgroundUrl != pic.largeUrl;

                      final imageWidget = ColoredBox(
                        color: pic.isWebpageCard
                            ? Colors.white
                            : Colors.transparent,
                        child: hasBackground
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  IgnorePointer(
                                    child: ExtendedImage.network(
                                      backgroundUrl,
                                      width: double.infinity,
                                      height: double.infinity,
                                      headers: ApiConstants.imageHeaders,
                                      fit: BoxFit.contain,
                                      cache: true,
                                    ),
                                  ),
                                  foregroundImage,
                                ],
                              )
                            : foregroundImage,
                      );

                      return _withGalleryHero(
                        index,
                        pic,
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            imageWidget,
                            // Live Photo Video Overlay when active
                            if (pic.isLivePhoto &&
                                controller != null &&
                                isInitialized &&
                                _isPlayingLive &&
                                _currentIndex == index)
                              Positioned.fill(
                                child: Center(
                                  child: AspectRatio(
                                    aspectRatio:
                                        controller.value.aspectRatio > 0
                                            ? controller.value.aspectRatio
                                            : 1.0,
                                    child: VideoPlayer(controller),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            if (widget.pics.length > 1)
              Positioned(
                left: 12,
                right: 12,
                bottom: MediaQuery.paddingOf(context).bottom + 32,
                child: Visibility(
                  visible: _showChrome,
                  maintainState: true,
                  child: _buildThumbnailStrip(),
                ),
              ),

            // Top Bar: Back, Counter, Live Pill, Save
            if (_showChrome)
              SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black45),
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        // 返回动作不再依赖水波纹触感。
                        onPressed: () => Navigator.of(context).pop(),
                      ),

                      // Counter or Live Photo Switcher Pill
                      if (isCurrentLive)
                        InkWell(
                          // 使用普通水波纹；触感由 _toggleLivePlay 单独提供一次。
                          splashFactory: InkSplash.splashFactory,
                          enableFeedback: false,
                          onTap: _toggleLivePlay,
                          borderRadius: BorderRadius.circular(20),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: _isPlayingLive
                                  ? Colors.white
                                  : Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _isPlayingLive
                                    ? Colors.white
                                    : Colors.white24,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isPlayingLive
                                      ? Icons.pause_circle_outline_rounded
                                      : Icons.play_circle_outline_rounded,
                                  size: 16,
                                  color: _isPlayingLive
                                      ? Colors.black
                                      : Colors.white,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _isPlayingLive ? '暂停 Live 图' : '播放 Live 图',
                                  style: TextStyle(
                                    color: _isPlayingLive
                                        ? Colors.black
                                        : Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${_currentIndex + 1} / ${widget.pics.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                      IconButton(
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black45),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.download_rounded,
                                color: Colors.white),
                        tooltip: '保存高清大图 / 实况到相册',
                        onPressed: _isSaving ? null : _saveCurrentImage,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
