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

/// Fullscreen Interactive Image & Live Photo Gallery with Physics Spring Transitions & Real-time Live Video Playback
class ImageGalleryPage extends ConsumerStatefulWidget {
  final List<WeiboPicModel> pics;
  final int initialIndex;
  final String statusId;
  final bool isDetail;
  final String? authorName;

  const ImageGalleryPage({
    super.key,
    required this.pics,
    required this.initialIndex,
    required this.statusId,
    this.isDetail = false,
    this.authorName,
  });

  @override
  ConsumerState<ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends ConsumerState<ImageGalleryPage> with SingleTickerProviderStateMixin {
  static const MethodChannel _mediaChannel = MethodChannel('com.sharelite/cookies');
  late int _currentIndex;
  late final ExtendedPageController _pageController;
  final GlobalKey<ExtendedImageSlidePageState> _slidePageKey = GlobalKey<ExtendedImageSlidePageState>();
  bool _isSaving = false;

  // Live Photo Controller Cache
  final Map<int, VideoPlayerController> _liveControllers = {};
  final Map<int, bool> _liveInitialized = {};
  bool _isPlayingLive = false;

  late final AnimationController _doubleTapAnimationController;
  Animation<double>? _doubleTapAnimation;
  Function()? _doubleTapListener;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = ExtendedPageController(initialPage: widget.initialIndex);
    _doubleTapAnimationController = AnimationController(
      duration: const Duration(milliseconds: 260),
      vsync: this,
    );
    _initLiveControllerForIndex(_currentIndex);
  }

  @override
  void dispose() {
    _doubleTapAnimationController.dispose();
    _pageController.dispose();
    for (final controller in _liveControllers.values) {
      controller.dispose();
    }
    _liveControllers.clear();
    super.dispose();
  }

  void _initLiveControllerForIndex(int index) {
    if (index < 0 || index >= widget.pics.length) return;
    final pic = widget.pics[index];
    if (pic.isLivePhoto && pic.livePhotoVideoUrl != null && pic.livePhotoVideoUrl!.isNotEmpty) {
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
          });
          controller.setLooping(true);
        }
      }).catchError((e) {
        debugPrint('Live Photo init error: $e');
      });
    }
  }

  void _toggleLivePlay() {
    final controller = _liveControllers[_currentIndex];
    if (controller == null || !(_liveInitialized[_currentIndex] ?? false)) {
      _initLiveControllerForIndex(_currentIndex);
      return;
    }

    HapticFeedbackUtil.light();
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
    if (pic.isLivePhoto && pic.livePhotoVideoUrl != null && pic.livePhotoVideoUrl!.isNotEmpty) {
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
                  const Text('保存实况照片', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
          ? (pic.livePhotoVideoUrl ?? pic.largeUrl)
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
        final author = (widget.authorName != null && widget.authorName!.isNotEmpty)
            ? widget.authorName!
            : '微博博主';
        relativeSubDir = 'Review/$author';
      }

      final isGif = url.toLowerCase().contains('.gif') || pic.isGif;
      final ext = isVideo ? '.mp4' : (isGif ? '.gif' : '.jpg');
      final fileName = 'wb_${widget.statusId}_${_currentIndex}_${DateTime.now().millisecondsSinceEpoch}$ext';

      // 3. Save to System MediaStore / Gallery
      final savedPath = await _mediaChannel.invokeMethod<String>(
        'saveMediaToGallery',
        {
          'bytes': Uint8List.fromList(bytes),
          'fileName': fileName,
          'relativeSubDir': relativeSubDir,
          'isVideo': isVideo,
          'mimeType': isVideo ? 'video/mp4' : (isGif ? 'image/gif' : 'image/jpeg'),
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

  @override
  Widget build(BuildContext context) {
    final currentPic = widget.pics.isNotEmpty ? widget.pics[_currentIndex] : null;
    final isCurrentLive = currentPic?.isLivePhoto == true && currentPic?.livePhotoVideoUrl != null;

    return ExtendedImageSlidePage(
      key: _slidePageKey,
      slideAxis: SlideAxis.both,
      slideType: SlideType.onlyImage,
      slidePageBackgroundHandler: (Offset offset, Size pageSize) {
        double opacity = offset.distance / (pageSize.height / 2.0);
        return Colors.black.withValues(alpha: math.max(0.0, 1.0 - opacity));
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Gesture PageView with Physics-based Spring Morphing
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: ExtendedImageGesturePageView.builder(
                controller: _pageController,
                itemCount: widget.pics.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                    _isPlayingLive = false;
                  });
                  // Pause previous live videos
                  for (final entry in _liveControllers.entries) {
                    if (entry.key != index && entry.value.value.isPlaying) {
                      entry.value.pause();
                    }
                  }
                  _initLiveControllerForIndex(index);
                },
                itemBuilder: (context, index) {
                  final pic = widget.pics[index];
                  final controller = _liveControllers[index];
                  final isInitialized = _liveInitialized[index] ?? false;

                  final isLongPic = pic.isLong || (pic.height > 0 && pic.width > 0 && pic.height / pic.width > 2.0);

                  final imageWidget = ExtendedImage.network(
                    pic.originalUrl.isNotEmpty ? pic.originalUrl : (pic.largeUrl.isNotEmpty ? pic.largeUrl : pic.bmiddleUrl),
                    width: double.infinity,
                    height: double.infinity,
                    headers: ApiConstants.imageHeaders,
                    fit: BoxFit.contain,
                    mode: ExtendedImageMode.gesture,
                    enableSlideOutPage: true,
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
                        _doubleTapAnimation?.removeListener(_doubleTapListener!);
                      }

                      _doubleTapAnimation = Tween<double>(begin: begin, end: end).animate(
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
                        initialAlignment: isLongPic ? InitialAlignment.topCenter : InitialAlignment.center,
                      );
                    },
                  );

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      imageWidget,
                      // Live Photo Video Overlay when active
                      if (pic.isLivePhoto && controller != null && isInitialized && _isPlayingLive && _currentIndex == index)
                        Positioned.fill(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 1.0,
                              child: VideoPlayer(controller),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // Top Bar: Back, Counter, Live Pill, Save
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      style: IconButton.styleFrom(backgroundColor: Colors.black45),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () {
                        HapticFeedbackUtil.light();
                        Navigator.of(context).pop();
                      },
                    ),

                    // Counter or Live Photo Switcher Pill
                    if (isCurrentLive)
                      InkWell(
                        onTap: _toggleLivePlay,
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: _isPlayingLive ? Colors.white : Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _isPlayingLive ? Colors.white : Colors.white24,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isPlayingLive ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                                size: 16,
                                color: _isPlayingLive ? Colors.black : Colors.white,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _isPlayingLive ? '暂停 Live 图' : '播放 Live 图',
                                style: TextStyle(
                                  color: _isPlayingLive ? Colors.black : Colors.white,
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                      style: IconButton.styleFrom(backgroundColor: Colors.black45),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.download_rounded, color: Colors.white),
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
