import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../detail/data/detail_repository.dart';
import 'weibo_video_player_page.dart';

/// Resolves a standalone Weibo video component before creating the native
/// player. `h5.video.weibo.com/show/...` is an HTML shell, not a media URL.
class WeiboVideoLinkPage extends ConsumerStatefulWidget {
  final String videoObjectId;
  final String? title;

  const WeiboVideoLinkPage({
    super.key,
    required this.videoObjectId,
    this.title,
  });

  @override
  ConsumerState<WeiboVideoLinkPage> createState() => _WeiboVideoLinkPageState();
}

class _WeiboVideoLinkPageState extends ConsumerState<WeiboVideoLinkPage> {
  WeiboVideoComponent? _video;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    if (mounted) setState(() => _loading = true);
    final video = await ref
        .read(detailRepositoryProvider)
        .resolveVideoComponent(widget.videoObjectId);
    if (!mounted) return;
    setState(() {
      _video = video;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    if (video != null) {
      return WeiboVideoPlayerPage(
        videoUrl: video.primaryUrl,
        coverUrl: video.coverUrl,
        title: widget.title ?? video.title ?? '微博视频',
        authorName: video.authorName,
        videoQualityUrls: video.qualityUrls,
        mediaHeaders: ApiConstants.h5VideoHeaders,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? '微博视频'),
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator(color: Colors.white70)
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.video_library_outlined,
                      color: Colors.white70,
                      size: 48,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '视频加载失败或链接已失效',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: _resolve,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
