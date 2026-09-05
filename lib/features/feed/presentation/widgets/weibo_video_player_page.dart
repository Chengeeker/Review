import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../core/utils/app_toast.dart';
import '../../../../core/utils/haptic_feedback_util.dart';
import '../../../detail/data/detail_repository.dart';

enum _DragMode { none, brightness, volume, seek }
enum _HudType { none, brightness, volume, seek, doubleTapSeek }

/// 沉浸式全功能微博视频播放器页面
/// 支持：
/// 1. 横竖屏一键旋转切换与全沉浸模式
/// 2. 右上方下载与分享原生通道
/// 3. 通用手势：长按左右侧2.0x倍速快进、双击左右侧快进/快退10秒、双击中间播放/暂停
/// 4. 滑动手势：左侧上下滑调节亮度、右侧上下滑调节音量、横屏全域/竖屏底部左右滑动调节进度
class WeiboVideoPlayerPage extends ConsumerStatefulWidget {
  final String videoUrl;
  final String? statusId;
  final String? coverUrl;
  final String? title;
  final String? authorName;
  final Map<String, String>? videoQualityUrls;

  const WeiboVideoPlayerPage({
    super.key,
    required this.videoUrl,
    this.statusId,
    this.coverUrl,
    this.title,
    this.authorName,
    this.videoQualityUrls,
  });

  @override
  ConsumerState<WeiboVideoPlayerPage> createState() => _WeiboVideoPlayerPageState();
}

class _WeiboVideoPlayerPageState extends ConsumerState<WeiboVideoPlayerPage> {
  static const MethodChannel _mediaChannel = MethodChannel('com.sharelite/cookies');

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  // 横竖屏状态
  bool _isLandscape = false;

  // 播放倍速控制
  double _playbackSpeed = 1.0;
  bool _isFastForwarding = false;
  static const List<double> _availableSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

  // 清晰度控制
  late Map<String, String> _qualityMap;
  String _currentQuality = '高清';

  // 下载与分享状态
  bool _isDownloading = false;

  // 手势与 HUD 状态
  _DragMode _dragMode = _DragMode.none;
  _HudType _hudType = _HudType.none;
  double _hudValue = 0.5; // 亮度或音量比例 (0.0 ~ 1.0)
  int _hudSeekDiff = 0; // 进度差异秒数 (+/-)
  Duration _targetSeekPosition = Duration.zero;
  Duration _startPosition = Duration.zero;
  Offset _panStartPos = Offset.zero;
  double _startBrightness = 0.5;
  double _startVolume = 0.5;
  double _currentBrightness = 0.5;
  double _currentVolume = 0.5;
  Timer? _hudDismissTimer;
  Offset _lastTapDownPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _qualityMap = Map.from(widget.videoQualityUrls ?? {});
    if (_qualityMap.isEmpty && widget.videoUrl.isNotEmpty) {
      _qualityMap['高清'] = widget.videoUrl;
    }

    if (_qualityMap.isNotEmpty) {
      _currentQuality = _qualityMap.entries
          .firstWhere(
            (e) => e.value == widget.videoUrl,
            orElse: () => _qualityMap.entries.first,
          )
          .key;
    }

    _initPlayer();
    _initDeviceLevels();
    _resetControlsTimer();
  }

  Future<void> _initDeviceLevels() async {
    try {
      final b = await _mediaChannel.invokeMethod<double>('getBrightness');
      if (b != null) _currentBrightness = b;
      final v = await _mediaChannel.invokeMethod<double>('getVolume');
      if (v != null) _currentVolume = v;
    } catch (_) {}
  }

  Future<void> _initPlayer({
    String? overrideUrl,
    Duration? startPosition,
    bool autoPlay = true,
  }) async {
    final targetUrl = overrideUrl ?? widget.videoUrl;
    if (targetUrl.isEmpty) {
      if (widget.statusId != null && widget.statusId!.isNotEmpty) {
        final success = await _refreshAndPlay();
        if (success) return;
      }
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
      return;
    }

    String cleanUrl = targetUrl.trim();
    if (cleanUrl.startsWith('http://')) {
      cleanUrl = cleanUrl.replaceFirst('http://', 'https://');
    }

    try {
      if (mounted) {
        setState(() {
          _hasError = false;
        });
      }

      await _controller?.dispose();
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(cleanUrl),
        httpHeaders: ApiConstants.imageHeaders,
      );

      await _controller!.initialize();
      _controller!.setLooping(true);
      await _controller!.setPlaybackSpeed(_playbackSpeed);

      if (startPosition != null && startPosition > Duration.zero) {
        await _controller!.seekTo(startPosition);
      }

      if (autoPlay) {
        await _controller!.play();
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
        });
      }

      _controller!.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (widget.statusId != null && widget.statusId!.isNotEmpty && overrideUrl == null) {
        final success = await _refreshAndPlay();
        if (success) return;
      }

      if (mounted) {
        setState(() {
          _hasError = true;
          _isInitialized = false;
        });
      }
    }
  }

  Future<bool> _refreshAndPlay() async {
    if (widget.statusId == null || widget.statusId!.isEmpty) return false;
    try {
      final repo = ref.read(detailRepositoryProvider);
      final detail = await repo.getStatusDetail(widget.statusId!);
      if (detail != null) {
        if (detail.videoQualityUrls != null && detail.videoQualityUrls!.isNotEmpty) {
          setState(() {
            _qualityMap = Map.from(detail.videoQualityUrls!);
            _currentQuality = _qualityMap.keys.first;
          });
        }
        final streamUrl = detail.videoStreamUrl ?? (detail.videoQualityUrls?.values.firstOrNull);
        if (streamUrl != null && streamUrl.isNotEmpty) {
          await _initPlayer(overrideUrl: streamUrl);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _hudDismissTimer?.cancel();
    _restorePortraitAndSystemUI();
    _controller?.dispose();
    super.dispose();
  }

  void _restorePortraitAndSystemUI() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );
  }

  void _toggleOrientation() {
    HapticFeedbackUtil.light();
    setState(() {
      _isLandscape = !_isLandscape;
    });

    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      _restorePortraitAndSystemUI();
    }
    _resetControlsTimer();
  }

  void _resetControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_showControls && _controller != null && _controller!.value.isPlaying) {
      _hideControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _controller != null && _controller!.value.isPlaying) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    HapticFeedbackUtil.light();
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _showControls = true;
      } else {
        _controller!.play();
        _resetControlsTimer();
      }
    });
  }

  // 1(a) 长按左侧或右侧：倍速
  void _onLongPressStart() {
    if (_controller == null || !_isInitialized) return;
    HapticFeedbackUtil.medium();
    setState(() {
      _isFastForwarding = true;
    });
    _controller?.setPlaybackSpeed(2.0);
  }

  void _onLongPressEnd() {
    if (!_isFastForwarding) return;
    HapticFeedbackUtil.light();
    setState(() {
      _isFastForwarding = false;
    });
    _controller?.setPlaybackSpeed(_playbackSpeed);
  }

  // 1(b) 双击左右两侧：快进或快退 10 秒
  void _seekRelative(int deltaSeconds) {
    if (_controller == null || !_isInitialized) return;
    HapticFeedbackUtil.light();
    final curPos = _controller!.value.position;
    final totalDur = _controller!.value.duration;
    final target = Duration(
      seconds: (curPos.inSeconds + deltaSeconds).clamp(0, totalDur.inSeconds),
    );
    _controller!.seekTo(target);

    _showHud(
      type: _HudType.doubleTapSeek,
      value: 0,
      diff: deltaSeconds,
      targetPosition: target,
      autoDismissMs: 800,
    );
  }

  // 滑动调节亮度
  void _setBrightness(double value) {
    _currentBrightness = value;
    _mediaChannel.invokeMethod('setBrightness', {'brightness': value}).catchError((_) {});
  }

  // 滑动调节音量
  void _setVolume(double value) {
    _currentVolume = value;
    _mediaChannel.invokeMethod('setVolume', {'volume': value}).catchError((_) {});
    _controller?.setVolume(value);
  }

  void _showHud({
    required _HudType type,
    double value = 0,
    int diff = 0,
    Duration targetPosition = Duration.zero,
    int autoDismissMs = 600,
  }) {
    _hudDismissTimer?.cancel();
    setState(() {
      _hudType = type;
      _hudValue = value;
      _hudSeekDiff = diff;
      _targetSeekPosition = targetPosition;
    });
    if (autoDismissMs > 0) {
      _hudDismissTimer = Timer(Duration(milliseconds: autoDismissMs), () {
        if (mounted) {
          setState(() {
            _hudType = _HudType.none;
          });
        }
      });
    }
  }

  // 下载当前播放的视频并保存到相册
  Future<void> _performDownloadVideo() async {
    if (_isDownloading) return;
    HapticFeedbackUtil.light();

    final currentUrl = _qualityMap[_currentQuality] ?? widget.videoUrl;
    if (currentUrl.isEmpty) {
      AppToast.show(context, '视频地址无效，无法下载');
      return;
    }

    setState(() => _isDownloading = true);
    AppToast.show(context, '正在下载视频，请稍候...');

    try {
      final dio = Dio();
      final response = await dio.get<List<int>>(
        currentUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: ApiConstants.imageHeaders,
        ),
      );

      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('下载数据为空');
      }

      final storage = ref.read(storageServiceProvider);
      final pathType = storage.getImageSavePathType();
      String relativeSubDir = 'Review';
      if (pathType == 2 && widget.authorName != null && widget.authorName!.isNotEmpty) {
        relativeSubDir = 'Review/${widget.authorName}';
      }

      final fileName = 'wb_video_${widget.statusId ?? DateTime.now().millisecondsSinceEpoch}_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final savedPath = await _mediaChannel.invokeMethod<String>(
        'saveMediaToGallery',
        {
          'bytes': Uint8List.fromList(bytes),
          'fileName': fileName,
          'relativeSubDir': relativeSubDir,
          'isVideo': true,
          'mimeType': 'video/mp4',
        },
      );

      HapticFeedbackUtil.medium();
      if (mounted) {
        AppToast.show(
          context,
          '🎉 视频已成功保存至相册：${savedPath ?? "Movies/$relativeSubDir"}',
        );
      }
    } catch (e) {
      HapticFeedbackUtil.heavy();
      if (mounted) {
        AppToast.show(context, '❌ 视频下载失败，请检查网络后重试');
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  // 分享当前视频
  Future<void> _performShareVideo() async {
    HapticFeedbackUtil.light();
    final shareUrl = (widget.statusId != null && widget.statusId!.isNotEmpty)
        ? 'https://weibo.com/detail/${widget.statusId}'
        : (_qualityMap[_currentQuality] ?? widget.videoUrl);

    final title = widget.title ?? (widget.authorName != null ? '${widget.authorName}的微博视频' : '微博视频');
    final shareText = '$title\n$shareUrl';

    // 1. 复制到剪贴板兜底
    await Clipboard.setData(ClipboardData(text: shareUrl));

    // 2. 调起系统分享
    try {
      await _mediaChannel.invokeMethod('shareText', {
        'text': shareText,
        'title': '分享视频',
      });
      if (mounted) {
        AppToast.show(context, '已复制视频链接并调起分享');
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, '视频链接已复制至剪贴板');
      }
    }
  }

  // 弹出倍速选择菜单
  void _showSpeedMenu() {
    HapticFeedbackUtil.light();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    '播放倍速',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                ..._availableSpeeds.reversed.map((speed) {
                  final isSelected = _playbackSpeed == speed;
                  return ListTile(
                    dense: true,
                    title: Text(
                      '${speed}X',
                      style: TextStyle(
                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 15,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary, size: 20)
                        : null,
                    onTap: () {
                      HapticFeedbackUtil.light();
                      setState(() {
                        _playbackSpeed = speed;
                      });
                      _controller?.setPlaybackSpeed(speed);
                      Navigator.pop(ctx);
                      AppToast.show(context, '已切换至 ${speed}X 倍速');
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  // 弹出画质选择菜单
  void _showQualityMenu() {
    HapticFeedbackUtil.light();
    if (_qualityMap.isEmpty) {
      AppToast.show(context, '暂无其他清晰度可选');
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    '清晰度选择',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                ..._qualityMap.entries.map((entry) {
                  final qName = entry.key;
                  final qUrl = entry.value;
                  final isSelected = _currentQuality == qName;

                  return ListTile(
                    dense: true,
                    title: Text(
                      qName,
                      style: TextStyle(
                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 15,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary, size: 20)
                        : null,
                    onTap: () {
                      HapticFeedbackUtil.light();
                      Navigator.pop(ctx);
                      if (isSelected) return;

                      final savedPos = _controller?.value.position ?? Duration.zero;
                      final wasPlaying = _controller?.value.isPlaying ?? true;

                      setState(() {
                        _currentQuality = qName;
                      });

                      _initPlayer(
                        overrideUrl: qUrl,
                        startPosition: savedPos,
                        autoPlay: wasPlaying,
                      );
                      AppToast.show(context, '已切换至 $qName');
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLandscape,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isLandscape) {
          _toggleOrientation();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                _lastTapDownPosition = details.localPosition;
              },
              onTap: () {
                setState(() {
                  _showControls = !_showControls;
                });
                _resetControlsTimer();
              },
              onDoubleTap: () {
                final x = _lastTapDownPosition.dx;
                // 1(c) 双击中间：播放/暂停
                // 1(b) 双击左右两侧：快退或快进 10 秒
                if (x < screenWidth * 0.35) {
                  _seekRelative(-10);
                } else if (x > screenWidth * 0.65) {
                  _seekRelative(10);
                } else {
                  _togglePlayPause();
                }
              },
              onLongPressStart: (details) {
                final x = details.localPosition.dx;
                // 1(a) 长按左侧或右侧：倍速
                if (x < screenWidth * 0.45 || x > screenWidth * 0.55) {
                  _onLongPressStart();
                }
              },
              onLongPressEnd: (_) => _onLongPressEnd(),
              onLongPressCancel: _onLongPressEnd,
              onPanStart: (details) {
                _panStartPos = details.localPosition;
                _dragMode = _DragMode.none;
                _startBrightness = _currentBrightness;
                _startVolume = _currentVolume;
                _startPosition = _controller?.value.position ?? Duration.zero;
                _targetSeekPosition = _startPosition;
              },
              onPanUpdate: (details) {
                final dx = details.localPosition.dx - _panStartPos.dx;
                final dy = details.localPosition.dy - _panStartPos.dy;

                if (_dragMode == _DragMode.none) {
                  if (dx.abs() > 14 && dx.abs() > dy.abs()) {
                    // 水平滑动判断：
                    // 横屏状态：任意区域左右滑动调整进度 (2.c)
                    // 竖屏状态：底部左右滑动调整进度 (3.c)
                    if (_isLandscape || _panStartPos.dy > screenHeight * 0.55) {
                      _dragMode = _DragMode.seek;
                    }
                  } else if (dy.abs() > 14 && dy.abs() > dx.abs()) {
                    // 垂直滑动判断（以中间为界）：
                    // 左侧上下滑动：调亮度 (2.a, 3.a)
                    // 右侧上下滑动：调音量 (2.b, 3.b)
                    if (_panStartPos.dx < screenWidth / 2) {
                      _dragMode = _DragMode.brightness;
                    } else {
                      _dragMode = _DragMode.volume;
                    }
                  }
                }

                if (_dragMode == _DragMode.brightness) {
                  final delta = -dy / (screenHeight * 0.65);
                  final nextVal = (_startBrightness + delta).clamp(0.01, 1.0);
                  _setBrightness(nextVal);
                  _showHud(type: _HudType.brightness, value: nextVal, autoDismissMs: 0);
                } else if (_dragMode == _DragMode.volume) {
                  final delta = -dy / (screenHeight * 0.65);
                  final nextVal = (_startVolume + delta).clamp(0.0, 1.0);
                  _setVolume(nextVal);
                  _showHud(type: _HudType.volume, value: nextVal, autoDismissMs: 0);
                } else if (_dragMode == _DragMode.seek) {
                  final totalDuration = _controller?.value.duration ?? Duration.zero;
                  if (totalDuration > Duration.zero) {
                    final maxSec = totalDuration.inSeconds;
                    // 滑动满半屏跨度约为 90 秒或全片长度
                    final span = maxSec > 180 ? 90 : (maxSec > 30 ? 60 : maxSec);
                    final diffSec = ((dx / (screenWidth * 0.5)) * span).toInt();
                    final targetSec = (_startPosition.inSeconds + diffSec).clamp(0, maxSec);
                    final target = Duration(seconds: targetSec);
                    _targetSeekPosition = target;
                    _showHud(
                      type: _HudType.seek,
                      diff: diffSec,
                      targetPosition: target,
                      autoDismissMs: 0,
                    );
                  }
                }
              },
              onPanEnd: (_) {
                if (_dragMode == _DragMode.seek) {
                  _controller?.seekTo(_targetSeekPosition);
                }
                _dragMode = _DragMode.none;
                _showHud(
                  type: _hudType,
                  value: _hudValue,
                  diff: _hudSeekDiff,
                  targetPosition: _targetSeekPosition,
                  autoDismissMs: 600,
                );
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 1. 视频主体展示
                  if (_isInitialized && _controller != null)
                    Center(
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio > 0
                            ? _controller!.value.aspectRatio
                            : (_isLandscape ? 16 / 9 : 9 / 16),
                        child: VideoPlayer(_controller!),
                      ),
                    )
                  else if (_hasError)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 48),
                          const SizedBox(height: 12),
                          const Text('视频加载失败或链接已失效', style: TextStyle(color: Colors.white70)),
                          const SizedBox(height: 16),
                          FilledButton.tonal(
                            onPressed: () {
                              setState(() {
                                _hasError = false;
                              });
                              _initPlayer();
                            },
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  else
                    Center(
                      child: widget.coverUrl != null
                          ? Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.network(
                                  widget.coverUrl!,
                                  headers: ApiConstants.imageHeaders,
                                  fit: BoxFit.contain,
                                ),
                                const CircularProgressIndicator(color: Colors.white70),
                              ],
                            )
                          : const CircularProgressIndicator(color: Colors.white70),
                    ),

                  // 2. 长按加速浮动指示胶囊 (居中偏上)
                  if (_isFastForwarding)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 50,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24, width: 0.8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fast_forward_rounded, color: Colors.amberAccent, size: 20),
                            SizedBox(width: 8),
                            Text(
                              '2.0X 倍速快进中',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 3. 全局手势指示器浮层 (亮度 / 音量 / 滑动进度 / 双击快进退)
                  _buildGestureHudOverlay(),

                  // 4. 顶部导航栏 (返回键、标题、下载按钮、分享按钮)
                  if (_showControls)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: EdgeInsets.fromLTRB(
                          _isLandscape ? 24 : 12,
                          MediaQuery.of(context).padding.top + 8,
                          _isLandscape ? 24 : 12,
                          16,
                        ),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black87, Colors.transparent],
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                              onPressed: () {
                                HapticFeedbackUtil.light();
                                if (_isLandscape) {
                                  _toggleOrientation();
                                } else {
                                  Navigator.pop(context);
                                }
                              },
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title != null && widget.title!.isNotEmpty
                                        ? widget.title!
                                        : (widget.authorName != null
                                            ? '${widget.authorName}的微博视频'
                                            : '微博视频'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (widget.authorName != null && !_isLandscape)
                                    Text(
                                      '@${widget.authorName}',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                ],
                              ),
                            ),
                            // 右上方：下载按钮
                            IconButton(
                              tooltip: '下载视频',
                              icon: _isDownloading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.download_rounded, color: Colors.white),
                              onPressed: _performDownloadVideo,
                            ),
                            // 下载右边：分享按钮
                            IconButton(
                              tooltip: '分享视频',
                              icon: const Icon(Icons.share_rounded, color: Colors.white),
                              onPressed: _performShareVideo,
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 5. 中间播放/暂停大图标
                  if (_showControls && _isInitialized && _controller != null && !_isFastForwarding)
                    Center(
                      child: IconButton(
                        iconSize: 64,
                        icon: Icon(
                          _controller!.value.isPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_filled_rounded,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        onPressed: _togglePlayPause,
                      ),
                    ),

                  // 6. 底部进度条与控制栏 (含时间、倍速、画质切换及横屏开关)
                  if (_showControls && _isInitialized && _controller != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: EdgeInsets.fromLTRB(
                          _isLandscape ? 28 : 16,
                          12,
                          _isLandscape ? 28 : 16,
                          MediaQuery.of(context).padding.bottom + 12,
                        ),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black87, Colors.transparent],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 进度滑块
                            VideoProgressIndicator(
                              _controller!,
                              allowScrubbing: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              colors: VideoProgressColors(
                                playedColor: Theme.of(context).colorScheme.primary,
                                bufferedColor: Colors.white30,
                                backgroundColor: Colors.white12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // 进度条下方行：时间、倍速、画质、最右侧横屏开关
                            Row(
                              children: [
                                Text(
                                  _formatDuration(_controller!.value.position),
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                                const Text(' / ', style: TextStyle(color: Colors.white38, fontSize: 12)),
                                Text(
                                  _formatDuration(_controller!.value.duration),
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                                const Spacer(),
                                // 倍速选择按钮
                                InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _showSpeedMenu,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white12,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white24, width: 0.6),
                                    ),
                                    child: Text(
                                      _playbackSpeed == 1.0 ? '倍速' : '${_playbackSpeed}X',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // 画质选择按钮
                                InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _showQualityMenu,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white12,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white24, width: 0.6),
                                    ),
                                    child: Text(
                                      _currentQuality,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // 画质右侧最右边：横屏显示开关 (全屏切换)
                                InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _toggleOrientation,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white12,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white24, width: 0.6),
                                    ),
                                    child: Icon(
                                      _isLandscape ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // 渲染各类手势浮动 HUD (亮度/音量/拖拽进度/双击快进快退)
  Widget _buildGestureHudOverlay() {
    if (_hudType == _HudType.none) return const SizedBox.shrink();

    Widget content;
    switch (_hudType) {
      case _HudType.brightness:
        final pct = (_hudValue * 100).toInt();
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              pct > 50 ? Icons.brightness_7_rounded : Icons.brightness_4_rounded,
              color: Colors.amberAccent,
              size: 26,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _hudValue,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.amberAccent),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$pct%',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        );
        break;

      case _HudType.volume:
        final pct = (_hudValue * 100).toInt();
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              pct == 0
                  ? Icons.volume_off_rounded
                  : (pct > 50 ? Icons.volume_up_rounded : Icons.volume_down_rounded),
              color: Colors.cyanAccent,
              size: 26,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _hudValue,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$pct%',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        );
        break;

      case _HudType.seek:
        final diffStr = _hudSeekDiff >= 0 ? '+${_hudSeekDiff}s' : '${_hudSeekDiff}s';
        final totalDur = _controller?.value.duration ?? Duration.zero;
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _hudSeekDiff >= 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(height: 6),
            Text(
              '${_formatDuration(_targetSeekPosition)} / ${_formatDuration(totalDur)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              '[$diffStr]',
              style: TextStyle(
                color: _hudSeekDiff >= 0 ? Colors.greenAccent : Colors.orangeAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        );
        break;

      case _HudType.doubleTapSeek:
        final diffStr = _hudSeekDiff >= 0 ? '+10s' : '-10s';
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _hudSeekDiff >= 0 ? Icons.forward_10_rounded : Icons.replay_10_rounded,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text(
              diffStr,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        );
        break;

      default:
        return const SizedBox.shrink();
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 16,
            ),
          ],
        ),
        child: content,
      ),
    );
  }
}
