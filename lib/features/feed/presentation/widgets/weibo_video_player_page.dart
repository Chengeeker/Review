import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/app_toast.dart';
import '../../../../core/utils/haptic_feedback_util.dart';
import '../../../detail/data/detail_repository.dart';

/// 沉浸式原生视频播放器页面 (支持左右长按加速快进、倍速调节、清晰度无缝切换、防盗链穿透)
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
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;

  // 播放倍速控制
  double _playbackSpeed = 1.0;
  bool _isFastForwarding = false;
  static const List<double> _availableSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

  // 清晰度控制
  late Map<String, String> _qualityMap;
  String _currentQuality = '高清';

  @override
  void initState() {
    super.initState();
    _qualityMap = Map.from(widget.videoQualityUrls ?? {});
    if (_qualityMap.isEmpty && widget.videoUrl.isNotEmpty) {
      _qualityMap['高清'] = widget.videoUrl;
    }

    // 默认高亮画质标签
    if (_qualityMap.isNotEmpty) {
      _currentQuality = _qualityMap.entries
          .firstWhere(
            (e) => e.value == widget.videoUrl,
            orElse: () => _qualityMap.entries.first,
          )
          .key;
    }

    _initPlayer();
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
      // If failed and statusId is provided, try dynamic resolution
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
    _controller?.dispose();
    super.dispose();
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
      } else {
        _controller!.play();
      }
    });
  }

  // 长按加速开始
  void _onLongPressStart() {
    if (_controller == null || !_isInitialized) return;
    HapticFeedbackUtil.medium();
    setState(() {
      _isFastForwarding = true;
    });
    _controller?.setPlaybackSpeed(2.0);
  }

  // 长按加速结束
  void _onLongPressEnd() {
    if (!_isFastForwarding) return;
    HapticFeedbackUtil.light();
    setState(() {
      _isFastForwarding = false;
    });
    _controller?.setPlaybackSpeed(_playbackSpeed);
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _showControls = !_showControls;
          });
        },
        onLongPressStart: (_) => _onLongPressStart(),
        onLongPressEnd: (_) => _onLongPressEnd(),
        onLongPressCancel: _onLongPressEnd,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. 视频主体
            if (_isInitialized && _controller != null)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio > 0 ? _controller!.value.aspectRatio : 16 / 9,
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
                child: AnimatedOpacity(
                  opacity: _isFastForwarding ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
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
              ),

            // 3. 顶部导航栏 (返回键、标题)
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 8, 12, 16),
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
                          Navigator.pop(context);
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.title != null && widget.title!.isNotEmpty)
                              Text(
                                widget.title!,
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (widget.authorName != null)
                              Text(
                                '@${widget.authorName}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 4. 中间播放/暂停大图标
            if (_showControls && _isInitialized && _controller != null && !_isFastForwarding)
              Center(
                child: IconButton(
                  iconSize: 64,
                  icon: Icon(
                    _controller!.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  onPressed: _togglePlayPause,
                ),
              ),

            // 5. 底部进度条与控制栏 (含倍速与画质切换)
            if (_showControls && _isInitialized && _controller != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
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
                        ],
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
