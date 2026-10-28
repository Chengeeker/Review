import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart'
    show
        PointerCancelEvent,
        PointerDownEvent,
        PointerMoveEvent,
        PointerUpEvent,
        kDoubleTapSlop,
        kDoubleTapTimeout,
        kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderImage, RenderClipRRect;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/auth/auth_provider.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/weibo_dio_client.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/utils/app_toast.dart';
import '../../../../core/utils/haptic_feedback_util.dart';
import '../../../../core/utils/spring_page_route.dart';
import '../../../feed/data/models/weibo_status_model.dart';
import '../../../feed/presentation/widgets/weibo_video_player_page.dart';
import 'hdr_gallery_image.dart';

/// Stable matching identity for a thumbnail and its fullscreen gallery image.
/// The scope is unique to the originating gallery widget, so two copies of the
/// same post on one route cannot accidentally claim the same Hero.
@immutable
class ImageGalleryHeroTag {
  const ImageGalleryHeroTag({
    required this.scope,
    required this.index,
    required this.mediaIdentity,
    required this.imageAspectRatio,
    required this.thumbnailUsesCover,
  });

  final Object scope;
  final int index;
  final String mediaIdentity;
  final double imageAspectRatio;
  final bool thumbnailUsesCover;

  factory ImageGalleryHeroTag.forPic({
    required Object scope,
    required int index,
    required WeiboPicModel pic,
  }) => ImageGalleryHeroTag(
    scope: scope,
    index: index,
    mediaIdentity: '${pic.pid}\u0000${pic.previewUrl}',
    imageAspectRatio: pic.width > 0 && pic.height > 0
        ? pic.width / pic.height
        : 1.0,
    thumbnailUsesCover: !pic.isWebpageCard,
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

/// Keeps the gallery image as the flying widget in both directions.
///
/// Flutter's default Hero shuttle always uses the destination child's layout.
/// On pop that is the small feed thumbnail, which can briefly replace the
/// fullscreen image before the reverse flight starts. Keep the fullscreen
/// destination on push, preview its source frame while the original loads, and
/// use the fullscreen source on pop.
Widget imageGalleryHeroFlightShuttleBuilder(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final fromHero = fromHeroContext.widget as Hero;
  final toHero = toHeroContext.widget as Hero;
  final flightTag = fromHero.tag;
  final videoGallery =
      toHeroContext.findAncestorStateOfType<_ImageGalleryPageState>() ??
      fromHeroContext.findAncestorStateOfType<_ImageGalleryPageState>();
  if (flightTag is ImageGalleryHeroTag &&
      videoGallery != null &&
      flightTag.index < videoGallery.widget.pics.length &&
      videoGallery.widget.pics[flightTag.index].isVideo) {
    // Fly the poster; mounting a player in the overlay opens another decoder.
    return flightDirection == HeroFlightDirection.pop
        ? toHero.child
        : fromHero.child;
  }
  if (flightDirection != HeroFlightDirection.pop) {
    final tag = fromHero.tag;
    final source = _HeroImageGeometry.capture(fromHeroContext);
    final gallery = toHeroContext
        .findAncestorStateOfType<_ImageGalleryPageState>();
    if (tag is ImageGalleryHeroTag &&
        source != null &&
        gallery != null &&
        tag.index == gallery.widget.initialIndex) {
      gallery._retainOpeningPreview(source.image);
    }
    return toHero.child;
  }

  final tag = fromHero.tag;
  final targetRenderObject = toHeroContext.findRenderObject();
  if (tag is! ImageGalleryHeroTag ||
      !tag.thumbnailUsesCover ||
      targetRenderObject is! RenderBox ||
      !targetRenderObject.hasSize ||
      targetRenderObject.size.width <= 0 ||
      targetRenderObject.size.height <= 0) {
    return fromHero.child;
  }

  final source = _HeroImageGeometry.capture(fromHeroContext);
  final target = _HeroImageGeometry.capture(toHeroContext);
  if (source == null || target == null) return fromHero.child;
  return _HeroReturnImageMorph(
    animation: animation,
    image: source.image.clone(),
    source: source,
    target: target,
  );
}

/// Snapshot the complete image plane, not just the fitted/cropped viewport.
/// ExtendedImage has its own RenderBox (it is NOT a Flutter RenderImage).
class _HeroImageGeometry {
  const _HeroImageGeometry(this.image, this.rect, this.radius);
  final ui.Image image;
  final Rect rect;
  final BorderRadius radius;

  static _HeroImageGeometry? capture(BuildContext context) {
    final root = context.findRenderObject();
    if (root is! RenderBox || !root.hasSize) return null;
    final direction = Directionality.of(context);
    _HeroImageGeometry? result;
    BorderRadius radius = BorderRadius.zero;
    void visit(RenderObject object) {
      if (result != null) return;
      if (object is RenderClipRRect) {
        radius = object.borderRadius.resolve(direction);
      }
      ui.Image? image;
      BoxFit? fit;
      AlignmentGeometry alignment = Alignment.center;
      Rect? gestureRect;
      if (object is ExtendedRenderImage) {
        image = object.image;
        fit = object.fit;
        alignment = object.alignment;
        // Already painted gesture geometry includes current zoom and pan.
        final gesture = object.gestureDetails;
        // ExtendedImage stores these in the paint canvas coordinate space,
        // including its paint offset. Normalize before mapping to the Hero.
        if (gesture?.destinationRect != null && gesture?.layoutRect != null) {
          gestureRect = gesture!.destinationRect!.shift(
            -gesture.layoutRect!.topLeft,
          );
        }
      } else if (object is RenderImage) {
        image = object.image;
        fit = object.fit;
        alignment = object.alignment;
      }
      if (image != null && object is RenderBox && object.hasSize) {
        final pixels = Size(image.width.toDouble(), image.height.toDouble());
        final align = alignment.resolve(direction);
        final fitted = applyBoxFit(
          fit ?? BoxFit.scaleDown,
          pixels,
          object.size,
        );
        final crop = align.inscribe(fitted.source, Offset.zero & pixels);
        final painted =
            gestureRect ??
            align.inscribe(fitted.destination, Offset.zero & object.size);
        // Expand the cropped source back into the complete pixel plane so
        // interpolation never stretches the image to the viewport aspect ratio.
        final sx = painted.width / crop.width;
        final sy = painted.height / crop.height;
        final full = Rect.fromLTWH(
          painted.left - crop.left * sx,
          painted.top - crop.top * sy,
          pixels.width * sx,
          pixels.height * sy,
        );
        final transform = object.getTransformTo(root);
        result = _HeroImageGeometry(
          image,
          MatrixUtils.transformRect(transform, full),
          radius,
        );
        return;
      }
      object.visitChildren(visit);
    }

    visit(root);
    return result;
  }
}

/// Freeze the decoded image, then move its edges and the clipping viewport
/// independently. Re-layout of a gesture image during flight changes its crop.
class _HeroReturnImageMorph extends StatefulWidget {
  const _HeroReturnImageMorph({
    required this.animation,
    required this.image,
    required this.source,
    required this.target,
  });

  final Animation<double> animation;
  final ui.Image image;
  final _HeroImageGeometry source;
  final _HeroImageGeometry target;

  @override
  State<_HeroReturnImageMorph> createState() => _HeroReturnImageMorphState();
}

class _HeroReturnImageMorphState extends State<_HeroReturnImageMorph> {
  @override
  void dispose() {
    final image = widget.image;
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    key: const ValueKey('gallery-return-image-plane'),
    painter: _HeroReturnPainter(
      widget.image,
      widget.animation,
      widget.source,
      widget.target,
    ),
    child: const SizedBox.expand(),
  );
}

class _HeroReturnPainter extends CustomPainter {
  _HeroReturnPainter(this.image, this.animation, this.source, this.target)
    : super(repaint: animation);
  final ui.Image image;
  final Animation<double> animation;
  final _HeroImageGeometry source;
  final _HeroImageGeometry target;

  @override
  void paint(Canvas canvas, Size size) {
    final t = (1 - animation.value).clamp(0.0, 1.0);
    final rect = Rect.lerp(source.rect, target.rect, t)!;
    final radius = BorderRadius.lerp(source.radius, target.radius, t)!;
    canvas.save();
    canvas.clipRRect(radius.toRRect(Offset.zero & size));
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeroReturnPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.source != source ||
      oldDelegate.target != target ||
      oldDelegate.animation != animation;
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
    tag: ImageGalleryHeroTag.forPic(scope: scope, index: index, pic: pic),
    flightShuttleBuilder: imageGalleryHeroFlightShuttleBuilder,
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
    with TickerProviderStateMixin {
  static final Set<_ImageGalleryPageState> _activeGalleryPages = {};
  static bool _globalCleanupScheduled = false;

  static void _scheduleGlobalCleanup() {
    if (_globalCleanupScheduled) return;
    _globalCleanupScheduled = true;
    PhysicsSpringGalleryRoute.whenAllRoutesIdle(() {
      _globalCleanupScheduled = false;
      if (_activeGalleryPages.isNotEmpty) return;
      hdrGalleryChannel.setMethodCallHandler(null);
      unawaited(
        hdrGalleryChannel
            .invokeMethod<void>('setWindowHdr', {'enabled': false})
            .catchError((_) {}),
      );
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      unawaited(
        _mediaChannel
            .invokeMethod<void>('setImageGalleryStatusBarVisible', {
              'visible': true,
            })
            .catchError((_) {}),
      );
    });
  }

  Map<String, String> _imageHeadersForUrl(String url) =>
      Uri.tryParse(url)?.host == 'upload.api.weibo.com'
      ? ref.read(weiboDioClientProvider).imageHeadersForUrl(url)
      : ApiConstants.imageHeaders;

  static const MethodChannel _mediaChannel = MethodChannel(
    'com.sharelite/cookies',
  );
  late int _currentIndex;
  late final ValueNotifier<int> _activeMediaIndex;
  late final ExtendedPageController _pageController;
  late final PageController _thumbnailController;
  final GlobalKey<ExtendedImageSlidePageState> _slidePageKey =
      GlobalKey<ExtendedImageSlidePageState>();
  bool _isSaving = false;
  bool _showChrome = true;
  bool _chromeRouteVisible = false;
  bool _isReturning = false;
  bool _liquidGlassEnabled = false;
  late final AnimationController _chromeOpacityController;
  Animation<double>? _routeAnimation;
  bool _thumbnailUserScrolling = false;
  bool _thumbnailSettling = false;
  int _thumbnailSyncEpoch = 0;
  final Set<int> _galleryPointers = {};
  int? _galleryTapPointer;
  Offset? _galleryTapDownPosition;
  bool _galleryTapMoved = false;
  Timer? _galleryTapTimer;
  Offset? _pendingGalleryTapPosition;
  double _videoBottomControlsHeight = 0;
  double? _thumbnailScrollBottom;
  bool _mainUserScrolling = false;
  final Expando<ExtendedImageGesture> _pagingImages = Expando();
  final Map<String, ValueNotifier<Rect?>> _hdrRects = {};
  final Set<String> _hdrUrls = {};
  bool _hdrWindowEnabled = false;
  bool _hdrDisplaySupported = false;
  bool? _windowHdrEnabled;

  ValueNotifier<Rect?> _hdrRectFor(String url) =>
      _hdrRects.putIfAbsent(url, () => ValueNotifier<Rect?>(null));

  void _onHdrDetected(String url, bool supported) {
    if (!mounted) return;
    if (_hdrUrls.add(url)) setState(() {});
    if (supported && !_hdrWindowEnabled) {
      _hdrWindowEnabled = true;
      _updateWindowHdr();
    }
  }

  Future<void> _checkHdrDisplaySupport() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final supported = await hdrGalleryChannel.invokeMethod<bool>(
        'isHdrDisplaySupported',
      );
      if (!mounted) return;
      setState(() {
        _hdrDisplaySupported = supported ?? false;
      });
      _updateWindowHdr();
    } catch (_) {}
  }

  Future<void> _handleNativeHdrCall(MethodCall call) async {
    if (call.method != 'hdrImageDecoded') return;
    final args = call.arguments;
    if (args is! Map || args['hasGainMap'] != true) return;
    final url = args['url']?.toString() ?? '';
    if (url.isEmpty || !mounted) return;
    _onHdrDetected(url, true);
  }

  void _updateWindowHdr() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final isCandidate = widget.pics.any((pic) {
      final url = pic.originalUrl;
      return _hdrUrls.contains(url) ||
          isKnownSinaHdrGainMap(url) ||
          url.toLowerCase().contains('gainmap') ||
          url.toLowerCase().contains('hdr');
    });
    final shouldEnable = _hdrDisplaySupported && isCandidate;
    if (_windowHdrEnabled == shouldEnable) return;
    _windowHdrEnabled = shouldEnable;
    unawaited(
      hdrGalleryChannel
          .invokeMethod<void>('setWindowHdr', {'enabled': shouldEnable})
          .catchError((_) {}),
    );
  }

  Future<void> _primeInitialHdrImage() async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        widget.initialIndex < 0 ||
        widget.initialIndex >= widget.pics.length) {
      return;
    }
    final pic = widget.pics[widget.initialIndex];
    if (pic.isVideo || pic.isGif || pic.isWebpageCard) return;
    final url = pic.originalUrl;
    final isHdr = await cachedSinaHdrGainMapProbe(url);
    if (isHdr && mounted) {
      _onHdrDetected(url, _hdrDisplaySupported);
      _updateWindowHdr();
    }
  }

  ui.Image? _openingPreview;

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
    _activeGalleryPages.add(this);
    _chromeOpacityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _currentIndex = widget.initialIndex;
    _activeMediaIndex = ValueNotifier(widget.initialIndex);
    _pageController = ExtendedPageController(initialPage: widget.initialIndex);
    _thumbnailController = PageController(
      initialPage: widget.initialIndex,
      viewportFraction: 0.16,
    );
    _thumbnailController.addListener(_syncMainPageToThumbnail);
    _doubleTapAnimationController = AnimationController(
      duration: const Duration(milliseconds: 260),
      vsync: this,
    );
    _initLiveControllerForIndex(_currentIndex);
    for (final pic in widget.pics) {
      if (pic.isVideo || pic.isGif || pic.isWebpageCard) continue;
      final url = pic.originalUrl;
      if (isKnownSinaHdrGainMap(url)) _hdrUrls.add(url);
      final pending = pendingSinaHdrGainMapProbe(url);
      if (pending != null) {
        unawaited(
          pending.then((found) {
            if (found && mounted) _onHdrDetected(url, _hdrDisplaySupported);
          }),
        );
      }
    }
    hdrGalleryChannel.setMethodCallHandler(_handleNativeHdrCall);
    unawaited(_checkHdrDisplaySupport());
    _updateWindowHdr();
    unawaited(_primeInitialHdrImage());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final routeAnimation = route?.animation;
    if (identical(routeAnimation, _routeAnimation)) return;

    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _routeAnimation = routeAnimation;
    if (routeAnimation == null) {
      _chromeRouteVisible = true;
      _chromeOpacityController.value = 1;
      return;
    }

    // A pushed route can initially report completed before its forward tick.
    // Only a completed first route should show controls immediately.
    _chromeRouteVisible =
        route?.isFirst == true &&
        routeAnimation.status == AnimationStatus.completed;
    _chromeOpacityController.value = _chromeRouteVisible ? 1 : 0;
    routeAnimation.addStatusListener(_handleRouteAnimationStatus);
  }

  void _handleRouteAnimationStatus(AnimationStatus status) {
    final visible = status == AnimationStatus.completed;
    final returning =
        status == AnimationStatus.reverse ||
        (_isReturning && status != AnimationStatus.completed);
    if (!mounted ||
        (visible == _chromeRouteVisible && returning == _isReturning)) {
      return;
    }
    setState(() {
      _chromeRouteVisible = visible;
      _isReturning = returning;
    });
    if (visible) {
      _chromeOpacityController.forward();
    } else {
      if (_liquidGlassEnabled && returning) {
        _chromeOpacityController
          ..stop()
          ..value = 0;
      } else {
        _chromeOpacityController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _activeGalleryPages.remove(this);
    if (_activeGalleryPages.isEmpty) {
      _scheduleGlobalCleanup();
    } else {
      hdrGalleryChannel.setMethodCallHandler(
        _activeGalleryPages.last._handleNativeHdrCall,
      );
    }
    for (final rect in _hdrRects.values) {
      rect.dispose();
    }
    _openingPreview?.dispose();
    _openingPreview = null;
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _galleryTapTimer?.cancel();
    _chromeOpacityController.dispose();
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

  void _retainOpeningPreview(ui.Image image) {
    if (_openingPreview != null) return;
    _openingPreview = image.clone();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _releaseOpeningPreviewAfterFrame() {
    final preview = _openingPreview;
    if (preview == null) return;
    _openingPreview = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => preview.dispose());
  }

  void _setSystemStatusBarVisible(bool visible) {
    _setNativeStatusBarVisible(visible);
  }

  void _setNativeStatusBarVisible(bool visible) {
    unawaited(
      _mediaChannel
          .invokeMethod<void>('setImageGalleryStatusBarVisible', {
            'visible': visible,
          })
          .catchError((_) {}),
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
      controller
          .initialize()
          .then((_) {
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
          })
          .catchError((e) {
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
                  const Text(
                    '保存实况照片',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
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
          headers: _imageHeadersForUrl(url),
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
          'mimeType': isVideo
              ? 'video/mp4'
              : (isGif ? 'image/gif' : 'image/jpeg'),
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
    _setChromeVisible(!_showChrome);
  }

  void _setChromeVisible(bool visible) {
    if (!mounted || _showChrome == visible) return;
    setState(() => _showChrome = visible);
    _setSystemStatusBarVisible(visible);
  }

  double get _thumbnailBottom =>
      _thumbnailScrollBottom ??
      (widget.pics[_currentIndex].isVideo && _videoBottomControlsHeight > 0
          ? _videoBottomControlsHeight + 8
          : MediaQuery.paddingOf(context).bottom + 32);

  void _setVideoBottomControlsHeight(double height) {
    if (!mounted || _videoBottomControlsHeight == height) return;
    setState(() => _videoBottomControlsHeight = height);
  }

  void _handleGalleryTap(Offset position) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final x = position.dx;
    final isMiddleThird = x >= screenWidth / 3 && x < screenWidth * 2 / 3;

    if (isMiddleThird) {
      _toggleChrome();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _handleGalleryPointerDown(PointerDownEvent event) {
    if (_galleryPointers.isEmpty) {
      _galleryTapPointer = event.pointer;
      _galleryTapDownPosition = event.position;
      _galleryTapMoved = false;
    } else {
      _galleryTapMoved = true;
    }
    _galleryPointers.add(event.pointer);
  }

  void _handleGalleryPointerMove(PointerMoveEvent event) {
    final downPosition = _galleryTapDownPosition;
    if (_galleryTapPointer == event.pointer &&
        downPosition != null &&
        (event.position - downPosition).distance > kTouchSlop) {
      _galleryTapMoved = true;
    }
  }

  void _handleGalleryPointerUp(PointerUpEvent event) {
    if (!_galleryPointers.remove(event.pointer)) return;
    if (_galleryTapPointer != event.pointer) {
      if (_galleryPointers.isEmpty) _resetGalleryTapPointer();
      return;
    }

    final isTap = _galleryPointers.isEmpty && !_galleryTapMoved;
    _resetGalleryTapPointer();
    if (isTap) _registerGalleryTap(event.position);
  }

  void _handleGalleryPointerCancel(PointerCancelEvent event) {
    if (!_galleryPointers.remove(event.pointer)) return;
    if (_galleryTapPointer == event.pointer || _galleryPointers.isEmpty) {
      _resetGalleryTapPointer();
    }
  }

  void _resetGalleryTapPointer() {
    _galleryTapPointer = null;
    _galleryTapDownPosition = null;
    _galleryTapMoved = false;
  }

  void _registerGalleryTap(Offset position) {
    final pendingPosition = _pendingGalleryTapPosition;
    if (_galleryTapTimer?.isActive == true &&
        pendingPosition != null &&
        (position - pendingPosition).distance <= kDoubleTapSlop) {
      _galleryTapTimer!.cancel();
      _galleryTapTimer = null;
      _pendingGalleryTapPosition = null;
      return;
    }

    _galleryTapTimer?.cancel();
    if (pendingPosition != null) _handleGalleryTap(pendingPosition);
    _pendingGalleryTapPosition = position;
    _galleryTapTimer = Timer(kDoubleTapTimeout, () {
      final pending = _pendingGalleryTapPosition;
      _galleryTapTimer = null;
      _pendingGalleryTapPosition = null;
      if (pending != null) _handleGalleryTap(pending);
    });
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

    final page = (_thumbnailController.page ?? _currentIndex.toDouble()).clamp(
      0.0,
      (widget.pics.length - 1).toDouble(),
    );
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
    unawaited(
      Future.wait<void>([
        _thumbnailController.animateToPage(
          target,
          duration: duration,
          curve: Curves.easeOutCubic,
        ),
        _pageController.animateToPage(
          target,
          duration: duration,
          curve: Curves.easeOutCubic,
        ),
      ]).whenComplete(() {
        if (!mounted || epoch != _thumbnailSyncEpoch) return;
        _thumbnailSettling = false;
        setState(() => _thumbnailScrollBottom = null);
        _activateCurrentMedia();
      }),
    );
  }

  Widget _withGalleryHero(int index, WeiboPicModel pic, Widget child) {
    final scope = widget.heroScope;
    // PageView keeps neighboring pages alive. If each retained page has a
    // Hero, popping the route can launch multiple flights back to the grid.
    // Disable neighboring flights without replacing the image gesture subtree.
    if (scope == null) return child;
    return HeroMode(
      enabled: index == _currentIndex,
      child: Hero(
        tag: ImageGalleryHeroTag.forPic(scope: scope, index: index, pic: pic),
        flightShuttleBuilder: imageGalleryHeroFlightShuttleBuilder,
        child: child,
      ),
    );
  }

  bool _handleThumbnailScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      // The reel must stay under the finger while paging unloads the player.
      _thumbnailScrollBottom = _thumbnailBottom;
      _thumbnailSyncEpoch++;
      _thumbnailSettling = false;
      _thumbnailUserScrolling = true;
      _mainUserScrolling = false;
      _activeMediaIndex.value = -1;
      _isPlayingLive = false;
      _pendingLivePlay = false;
      for (final controller in _liveControllers.values) {
        if (controller.value.isPlaying) controller.pause();
      }
      setState(() {});
    } else if (notification is ScrollEndNotification &&
        _thumbnailUserScrolling) {
      final epoch = _thumbnailSyncEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            epoch == _thumbnailSyncEpoch &&
            _thumbnailUserScrolling) {
          _settleThumbnailScroll();
        }
      });
    }
    return false;
  }

  bool _handleMainGalleryScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _thumbnailSyncEpoch++;
      _thumbnailUserScrolling = false;
      _thumbnailSettling = false;
      _mainUserScrolling = true;
      _activeMediaIndex.value = -1;
      for (final controller in _liveControllers.values) {
        if (controller.value.isPlaying) controller.pause();
      }
      if (_thumbnailController.hasClients &&
          _thumbnailController.position.isScrollingNotifier.value) {
        final position = _thumbnailController.position;
        // Stop old thumbnail inertia without snapping away from its fractional page.
        position.jumpTo(position.pixels);
      }
      if (_thumbnailScrollBottom != null ||
          _isPlayingLive ||
          _pendingLivePlay) {
        setState(() {
          _thumbnailScrollBottom = null;
          _isPlayingLive = false;
          _pendingLivePlay = false;
        });
      }
    } else if (notification is ScrollEndNotification && _mainUserScrolling) {
      final epoch = _thumbnailSyncEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            epoch != _thumbnailSyncEpoch ||
            !_mainUserScrolling ||
            _pageController.position.isScrollingNotifier.value) {
          return;
        }
        _mainUserScrolling = false;
        _activateCurrentMedia();
      });
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
                  _thumbnailScrollBottom = null;
                  _thumbnailUserScrolling = false;
                  _thumbnailSettling = false;
                  _thumbnailController.jumpToPage(index);
                  _selectThumbnail(index);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 2,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ExtendedImage.network(
                            widget.pics[index].previewUrl,
                            headers: _imageHeadersForUrl(
                              widget.pics[index].previewUrl,
                            ),
                            fit: BoxFit.cover,
                            cacheWidth: 160,
                            cache: true,
                          ),
                          if (!selected)
                            ColoredBox(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          if (widget.pics[index].isVideo)
                            const Center(
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          if (_hdrUrls.contains(widget.pics[index].originalUrl))
                            const Positioned(
                              right: 2,
                              bottom: 2,
                              child: GalleryHdrBadge(thumbnail: true),
                            ),
                        ],
                      ),
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
    final useLiquidGlass = ref.watch(
      themeProvider.select((state) => state.useLiquidGlass),
    );
    _liquidGlassEnabled = useLiquidGlass;
    final hideChromeForReturn = useLiquidGlass && _isReturning;
    final currentPic = widget.pics.isNotEmpty
        ? widget.pics[_currentIndex]
        : null;
    final isCurrentLive =
        currentPic?.isLivePhoto == true &&
        currentPic?.livePhotoVideoUrl != null;

    final galleryPage = ExtendedImageSlidePage(
      key: _slidePageKey,
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
            // Raw pointer tracking avoids competing with ExtendedImage double taps.
            Listener(
              onPointerDown: _handleGalleryPointerDown,
              onPointerMove: _handleGalleryPointerMove,
              onPointerUp: _handleGalleryPointerUp,
              onPointerCancel: _handleGalleryPointerCancel,
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleMainGalleryScroll,
                child: ExtendedImageGesturePageView.builder(
                  controller: _pageController,
                  physics: const BouncingScrollPhysics(),
                  canScrollPage: (details) =>
                      (details?.totalScale ?? 1.0) <= 1.0,
                  shouldAccpetHorizontalOrVerticalDrag: (trackers) =>
                      trackers.length == 1,
                  pageSnapping: !_thumbnailUserScrolling && !_thumbnailSettling,
                  itemCount: widget.pics.length,
                  onPageChanged: (index) {
                    final didChange = index != _currentIndex;
                    if (didChange && _thumbnailUserScrolling) {
                      HapticFeedbackUtil.selectionTick();
                    } else if (!_thumbnailUserScrolling &&
                        !_thumbnailSettling &&
                        !_mainUserScrolling) {
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
                      return _withGalleryHero(
                        index,
                        pic,
                        ValueListenableBuilder<int>(
                          valueListenable: _activeMediaIndex,
                          builder: (context, activeIndex, _) =>
                              activeIndex == index &&
                                  (widget.heroScope == null ||
                                      _chromeRouteVisible)
                              ? WeiboVideoPlayerPage(
                                  key: ValueKey('gallery-video-$index'),
                                  videoUrl: pic.videoUrl ?? '',
                                  mediaHeaders: _imageHeadersForUrl(
                                    pic.videoUrl ?? '',
                                  ),
                                  statusId: widget.statusId,
                                  coverUrl: pic.previewUrl.isEmpty
                                      ? null
                                      : pic.previewUrl,
                                  title: pic.videoTitle,
                                  authorName: widget.authorName,
                                  embedded: true,
                                  onToggleChrome: _toggleChrome,
                                  onFullscreenChanged: (isFullscreen) =>
                                      _setChromeVisible(!isFullscreen),
                                  onBottomControlsHeightChanged:
                                      _setVideoBottomControlsHeight,
                                )
                              : pic.previewUrl.isEmpty
                              ? const ColoredBox(color: Colors.black)
                              : ExtendedImage.network(
                                  pic.previewUrl,
                                  headers: _imageHeadersForUrl(pic.previewUrl),
                                  fit: BoxFit.contain,
                                  cache: true,
                                ),
                        ),
                      );
                    }
                    final controller = _liveControllers[index];
                    final isInitialized = _liveInitialized[index] ?? false;
                    final isLongPic =
                        pic.isLong ||
                        (pic.height > 0 &&
                            pic.width > 0 &&
                            pic.height / pic.width > 2.0);

                    final imageUrl = pic.originalUrl.isNotEmpty
                        ? pic.originalUrl
                        : (pic.largeUrl.isNotEmpty
                              ? pic.largeUrl
                              : pic.bmiddleUrl);
                    final foregroundImage = ExtendedImage.network(
                      imageUrl,
                      width: double.infinity,
                      height: double.infinity,
                      headers: _imageHeadersForUrl(imageUrl),
                      cache: true,
                      fit: BoxFit.contain,
                      mode: ExtendedImageMode.gesture,
                      // Keep slide-out disabled: during image loading the
                      // package installs a scale recognizer that can steal paging.
                      enableSlideOutPage: false,
                      loadStateChanged: (state) {
                        if (state.extendedImageLoadState !=
                            LoadState.completed) {
                          if (index == widget.initialIndex &&
                              state.extendedImageLoadState ==
                                  LoadState.loading &&
                              _openingPreview != null) {
                            return RawImage(
                              key: const ValueKey('gallery-opening-preview'),
                              image: _openingPreview,
                              fit: BoxFit.contain,
                            );
                          }
                          // Keep each page's preview visible while its original loads.
                          if (state.extendedImageLoadState ==
                                  LoadState.loading &&
                              pic.previewUrl.isNotEmpty &&
                              pic.previewUrl != imageUrl) {
                            return ExtendedImage.network(
                              pic.previewUrl,
                              key: ValueKey('gallery-loading-preview-$index'),
                              headers: _imageHeadersForUrl(pic.previewUrl),
                              cache: true,
                              fit: BoxFit.contain,
                            );
                          }
                          return null;
                        }
                        if (index == widget.initialIndex) {
                          _releaseOpeningPreviewAfterFrame();
                        }
                        // Reuse a decoded frame's widget to avoid repeated gesture animation initialization.
                        return _pagingImages[state
                            .extendedImageInfo!] ??= ExtendedImageGesture(
                          state,
                          imageBuilder: (image, {imageGestureState}) {
                            final gestureState = imageGestureState!;
                            final pager = gestureState.context
                                .findAncestorStateOfType<
                                  ExtendedImageGesturePageViewState
                                >();
                            // Hero flights rebuild this image in an overlay without a pager.
                            if (pager == null) return image;
                            // Register paging before the image's scale recognizer sees a fast single-finger move.
                            return Listener(
                              onPointerDown: (_) {
                                pager.extendedImageGestureStates.remove(
                                  gestureState,
                                );
                                pager.extendedImageGestureState = gestureState;
                              },
                              child: RawGestureDetector(
                                gestures: {
                                  ExtendedHorizontalDragGestureRecognizer:
                                      GestureRecognizerFactoryWithHandlers<
                                        ExtendedHorizontalDragGestureRecognizer
                                      >(
                                        () => ExtendedHorizontalDragGestureRecognizer(
                                          canHorizontalOrVerticalDrag: () =>
                                              (gestureState
                                                      .gestureDetails
                                                      ?.totalScale ??
                                                  1) <=
                                              1,
                                          shouldAccpetHorizontalOrVerticalDrag:
                                              (trackers) =>
                                                  trackers.length == 1,
                                        ),
                                        (recognizer) => recognizer
                                          ..onDown = pager.onDragDown
                                          ..onStart = pager.onDragStart
                                          ..onUpdate = pager.onDragUpdate
                                          ..onEnd = pager.onDragEnd
                                          ..onCancel = pager.onDragCancel
                                          ..minFlingDistance = pager
                                              .widget
                                              .physics
                                              .minFlingDistance
                                          ..minFlingVelocity = pager
                                              .widget
                                              .physics
                                              .minFlingVelocity
                                          ..maxFlingVelocity = pager
                                              .widget
                                              .physics
                                              .maxFlingVelocity
                                          ..gestureSettings =
                                              MediaQuery.gestureSettingsOf(
                                                context,
                                              ),
                                      ),
                                },
                                child: image,
                              ),
                            );
                          },
                        );
                      },
                      onDoubleTap: (ExtendedImageGestureState state) {
                        HapticFeedbackUtil.light();
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
                          _doubleTapAnimation?.removeListener(
                            _doubleTapListener!,
                          );
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
                          // Do not let the image shrink below its fitted
                          // size: ExtendedImage recenters sub-1.0 scales,
                          // which otherwise makes pinch focus jump away.
                          minScale: 1.0,
                          animationMinScale: 1.0,
                          maxScale: 8.0,
                          animationMaxScale: 9.0,
                          speed: 1.0,
                          inertialSpeed: 120.0,
                          initialScale: 1.0,
                          inPageView: true,
                          initialAlignment: InitialAlignment.center,
                          gestureDetailsIsChanged: (details) {
                            final rect = details?.destinationRect;
                            final layout = details?.layoutRect;
                            _hdrRectFor(imageUrl).value = rect?.shift(
                              -(layout?.topLeft ?? Offset.zero),
                            );
                          },
                        );
                      },
                    );
                    final backgroundUrl = pic.webpageCardBackgroundUrl?.trim();
                    final hasBackground =
                        backgroundUrl != null &&
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
                                    headers: _imageHeadersForUrl(backgroundUrl),
                                    fit: BoxFit.contain,
                                    cache: true,
                                  ),
                                ),
                                foregroundImage,
                              ],
                            )
                          : foregroundImage,
                    );

                    final heroImage = _withGalleryHero(
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
                                  aspectRatio: controller.value.aspectRatio > 0
                                      ? controller.value.aspectRatio
                                      : 1.0,
                                  child: VideoPlayer(controller),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                    if (pic.isGif || pic.isWebpageCard) return heroImage;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        heroImage,
                        if (!pic.isVideo)
                          ValueListenableBuilder<int>(
                            valueListenable: _activeMediaIndex,
                            builder: (context, activeIndex, _) =>
                                HdrGalleryImage(
                                  key: ValueKey('hdr-$imageUrl'),
                                  url: imageUrl,
                                  headers: _imageHeadersForUrl(imageUrl),
                                  active:
                                      activeIndex == index && !_isPlayingLive,
                                  visible:
                                      activeIndex == index &&
                                      _chromeRouteVisible &&
                                      !_isPlayingLive,
                                  displaySupported: _hdrDisplaySupported,
                                  isCandidate:
                                      _hdrUrls.contains(imageUrl) ||
                                      isKnownSinaHdrGainMap(imageUrl),
                                  imageRect: _hdrRectFor(imageUrl),
                                  onDetected: (supported) =>
                                      _onHdrDetected(imageUrl, supported),
                                ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),

            if (_showChrome &&
                _chromeRouteVisible &&
                currentPic != null &&
                _hdrUrls.contains(currentPic.originalUrl))
              Positioned(
                bottom: widget.pics.length > 1
                    ? _thumbnailBottom + 64 + 14
                    : MediaQuery.paddingOf(context).bottom + 24,
                right: 16,
                child: const GalleryHdrBadge(),
              ),
            if (widget.pics.length > 1 && !hideChromeForReturn)
              Positioned(
                left: 12,
                right: 12,
                bottom: _thumbnailBottom,
                child: Visibility(
                  visible: _showChrome,
                  maintainState: true,
                  child: IgnorePointer(
                    ignoring: !_chromeRouteVisible,
                    child: AnimatedOpacity(
                      key: const ValueKey('gallery-thumbnail-strip-fade'),
                      opacity: _chromeRouteVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOutCubic,
                      child: _buildThumbnailStrip(),
                    ),
                  ),
                ),
              ),

            // Top Bar: Back, Counter, Live Pill, Save
            if (_showChrome && !hideChromeForReturn)
              IgnorePointer(
                key: const ValueKey('gallery-top-controls-pointer-gate'),
                ignoring: !_chromeRouteVisible,
                child: AnimatedBuilder(
                  animation: _chromeOpacityController,
                  builder: (context, _) {
                    final controlsOpacity = _chromeOpacityController.value;
                    return SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _GalleryGlassIconButton(
                              tooltip: '返回',
                              opacity: controlsOpacity,
                              opacityKey: const ValueKey(
                                'gallery-back-button-opacity',
                              ),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                              ),
                              useLiquidGlass: useLiquidGlass,
                              // 返回动作不再依赖水波纹触感。
                              onPressed: () => Navigator.of(context).pop(),
                            ),

                            // Counter or Live Photo Switcher Pill
                            Opacity(
                              key: const ValueKey('gallery-counter-opacity'),
                              opacity: controlsOpacity,
                              child: isCurrentLive
                                  ? InkWell(
                                      // 使用普通水波纹；触感由 _toggleLivePlay 单独提供一次。
                                      splashFactory: InkSplash.splashFactory,
                                      enableFeedback: false,
                                      onTap: _toggleLivePlay,
                                      borderRadius: BorderRadius.circular(20),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _isPlayingLive
                                              ? Colors.white
                                              : Colors.black54,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
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
                                                  ? Icons
                                                        .pause_circle_outline_rounded
                                                  : Icons
                                                        .play_circle_outline_rounded,
                                              size: 16,
                                              color: _isPlayingLive
                                                  ? Colors.black
                                                  : Colors.white,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              _isPlayingLive
                                                  ? '暂停 Live 图'
                                                  : '播放 Live 图',
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
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
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
                            ),

                            _GalleryGlassIconButton(
                              tooltip: '保存高清大图 / 实况到相册',
                              opacity: controlsOpacity,
                              opacityKey: const ValueKey(
                                'gallery-download-button-opacity',
                              ),
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.download_rounded,
                                      color: Colors.white,
                                    ),
                              useLiquidGlass: useLiquidGlass,
                              onPressed: _isSaving ? null : _saveCurrentImage,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
    return galleryPage;
  }
}

class _GalleryGlassIconButton extends StatefulWidget {
  const _GalleryGlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.opacity,
    required this.opacityKey,
    required this.useLiquidGlass,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double opacity;
  final Key opacityKey;
  final bool useLiquidGlass;

  @override
  State<_GalleryGlassIconButton> createState() =>
      _GalleryGlassIconButtonState();
}

class _GalleryGlassIconButtonState extends State<_GalleryGlassIconButton> {
  static Future<ui.FragmentProgram>? _programFuture;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (!widget.useLiquidGlass && ui.ImageFilter.isShaderFilterSupported) {
      _loadShader();
    }
  }

  @override
  void didUpdateWidget(covariant _GalleryGlassIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.useLiquidGlass == widget.useLiquidGlass) return;
    if (widget.useLiquidGlass) {
      _shader?.dispose();
      _shader = null;
    } else if (ui.ImageFilter.isShaderFilterSupported) {
      _loadShader();
    }
  }

  Future<void> _loadShader() async {
    try {
      final program = await (_programFuture ??= ui.FragmentProgram.fromAsset(
        'shaders/gallery_glass_button.frag',
      ));
      final shader = program.fragmentShader();
      if (!mounted || widget.useLiquidGlass) {
        shader.dispose();
        return;
      }
      setState(() => _shader = shader);
    } catch (_) {
      // Blur and the highlight surface remain usable if shader loading fails.
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = widget.opacity;
    if (widget.useLiquidGlass) {
      return GestureDetector(
        excludeFromSemantics: true,
        // Long holds are reserved for exploring the liquid effect.
        onLongPress: () {},
        child: GlassButton(
          label: widget.tooltip,
          width: 48,
          height: 48,
          icon: widget.icon,
          iconSize: 22,
          iconColor: Colors.white,
          onTap: () => widget.onPressed?.call(),
          enabled: widget.onPressed != null,
          useOwnLayer: true,
          stretch: 0.8,
          anchorStretchSettings: const AnchorStretchSettings(
            intensity: 0.8,
            squashFactor: 0.3,
            translationDamping: 0.15,
            bounciness: 0.2,
          ),
          glowColor: const Color(0x20FFFFFF),
          glowOpacity: 1,
          quality: GlassQuality.premium,
          settings: LiquidGlassSettings(
            visibility: opacity,
            glassColor: const Color(0x66000000),
            bodyMode: GlassBodyMode.clear,
            thickness: 32,
            blur: 2,
            lightIntensity: 0.25,
            ambientStrength: 0,
            refractiveIndex: 1.24,
            chromaticAberration: 0.025,
            shadowElevation: 0,
          ),
        ),
      );
    }
    final blur = ui.ImageFilter.blur(
      sigmaX: 2.5 * opacity,
      sigmaY: 2.5 * opacity,
    );
    final shader = _shader;
    final filter = shader == null || opacity < 1
        ? blur
        : ui.ImageFilter.compose(
            outer: ui.ImageFilter.shader(shader),
            inner: blur,
          );

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20 * opacity),
                    blurRadius: 7,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.08 * opacity),
                    blurRadius: 5,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: ClipOval(
                clipBehavior: Clip.antiAlias,
                child: BackdropFilter(
                  filter: filter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.grey.shade200.withValues(
                            alpha: 0.30 * opacity,
                          ),
                          Colors.grey.shade500.withValues(
                            alpha: 0.20 * opacity,
                          ),
                          Colors.grey.shade800.withValues(
                            alpha: 0.36 * opacity,
                          ),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.34 * opacity),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: widget.tooltip,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(48),
              padding: EdgeInsets.zero,
              foregroundColor: Colors.white,
              backgroundColor: Colors.transparent,
              shape: const CircleBorder(),
            ),
            onPressed: widget.onPressed,
            icon: Opacity(
              key: widget.opacityKey,
              opacity: opacity,
              child: widget.icon,
            ),
          ),
        ],
      ),
    );
  }
}
