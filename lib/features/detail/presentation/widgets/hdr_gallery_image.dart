import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:extended_image/extended_image.dart';
import 'package:crypto/crypto.dart' show md5;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/api_constants.dart';

/// A cheap hint only; Android must confirm Bitmap.hasGainmap before display.
bool mayContainHdrGainMap(List<int> bytes) {
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) {
    return false;
  }
  final header = latin1.decode(bytes);
  return header.contains('http://ns.adobe.com/hdr-gain-map/1.0/') ||
      header.contains('urn:iso:std:iso:ts:21496:-1');
}

const _hdrProbeByteLimit = 256 * 1024;
final _hdrProbeCache = <String, bool>{};
final _hdrProbePending = <String, Future<bool>>{};
final _hdrProbeDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
    headers: ApiConstants.imageHeaders,
  ),
);

@visibleForTesting
Dio get hdrThumbnailProbeClient => _hdrProbeDio;

Future<bool> probeSinaHdrGainMap(Dio dio, String url) async {
  final uri = Uri.tryParse(url);
  if (kIsWeb ||
      uri == null ||
      uri.scheme != 'https' ||
      !uri.host.endsWith('.sinaimg.cn') ||
      uri.pathSegments.length != 2 ||
      uri.pathSegments.first != 'large') {
    return false;
  }
  final response = await dio.get<ResponseBody>(
    url,
    options: Options(
      responseType: ResponseType.stream,
      headers: {
        ...ApiConstants.imageHeaders,
        'Range': 'bytes=0-${_hdrProbeByteLimit - 1}',
        'Accept-Encoding': 'identity',
      },
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      validateStatus: (status) => status == 200 || status == 206,
    ),
  );
  final bytes = await _readStreamPrefix(
    response.data!.stream,
    _hdrProbeByteLimit,
  );
  return mayContainHdrGainMap(bytes);
}

Future<List<int>> _readStreamPrefix(Stream<List<int>> stream, int limit) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    final remaining = limit - bytes.length;
    bytes.addAll(chunk.take(remaining));
    if (bytes.length == limit) break;
  }
  return bytes;
}

bool isKnownSinaHdrGainMap(String url) => _hdrProbeCache[url] == true;

Future<bool> cachedSinaHdrGainMapProbe(String url) {
  final cached = _hdrProbeCache.remove(url);
  if (cached != null) {
    _hdrProbeCache[url] = cached;
    return Future.value(cached);
  }
  final pending = _hdrProbePending[url];
  if (pending != null) return pending;
  final request = probeSinaHdrGainMap(_hdrProbeDio, url)
      .then((result) {
        _hdrProbeCache[url] = result;
        if (_hdrProbeCache.length > 256) {
          _hdrProbeCache.remove(_hdrProbeCache.keys.first);
        }
        return result;
      }, onError: (Object _, StackTrace __) => false)
      .whenComplete(() {
        // Returning the removed Future would make this request await itself.
        _hdrProbePending.remove(url);
      });
  _hdrProbePending[url] = request;
  return request;
}

class HdrThumbnailBadge extends StatefulWidget {
  const HdrThumbnailBadge({super.key, required this.url});

  final String url;

  @override
  State<HdrThumbnailBadge> createState() => _HdrThumbnailBadgeState();
}

class _HdrThumbnailBadgeState extends State<HdrThumbnailBadge> {
  bool _hasHdrGainMap = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(HdrThumbnailBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _hasHdrGainMap = false;
      _check();
    }
  }

  Future<void> _check() async {
    final url = widget.url;
    final found = await cachedSinaHdrGainMapProbe(url);
    if (mounted && widget.url == url && found) {
      setState(() => _hasHdrGainMap = true);
    }
  }

  @override
  Widget build(BuildContext context) => _hasHdrGainMap
      ? const GalleryHdrBadge(feed: true)
      : const SizedBox.shrink();
}

Matrix4 hdrImageViewTransform(Rect viewport, Rect? imageRect) {
  if (viewport.isEmpty || imageRect == null || imageRect.isEmpty) {
    return Matrix4.identity();
  }
  final fitted = Alignment.center.inscribe(
    applyBoxFit(BoxFit.contain, imageRect.size, viewport.size).destination,
    viewport,
  );
  final scale = imageRect.width / fitted.width;
  return Matrix4.identity()
    ..translateByDouble(
      imageRect.left - fitted.left * scale,
      imageRect.top - fitted.top * scale,
      0,
      1,
    )
    ..scaleByDouble(scale, scale, 1, 1);
}

const hdrGalleryChannel = MethodChannel('com.review/hdr_image');
final _nativeHdrDecodePending = <String, Future<Map<String, dynamic>?>>{};

Future<File?> cachedHdrImageFile(String url) async {
  if (kIsWeb) return null;
  try {
    final temporary = await getTemporaryDirectory();
    final file = File(
      '${temporary.path}${Platform.pathSeparator}$cacheImageFolderName'
      '${Platform.pathSeparator}${md5.convert(utf8.encode(url))}',
    );
    return await file.exists() ? file : null;
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>?> primeCachedSinaHdrImage(String url) async {
  if (!await cachedSinaHdrGainMapProbe(url)) return null;
  final file = await cachedHdrImageFile(url);
  return file == null ? null : decodeCachedHdrImage(file.path);
}

Future<Map<String, dynamic>?> decodeCachedHdrImage(String path) {
  final pending = _nativeHdrDecodePending[path];
  if (pending != null) return pending;
  final request = hdrGalleryChannel.invokeMapMethod<String, dynamic>('decode', {
    'path': path,
  });
  _nativeHdrDecodePending[path] = request;
  return request.whenComplete(() {
    _nativeHdrDecodePending.remove(path);
  });
}

class HdrGalleryImage extends StatefulWidget {
  const HdrGalleryImage({
    super.key,
    required this.url,
    required this.active,
    required this.imageRect,
    required this.onDetected,
    this.visible = true,
    this.displaySupported,
    this.isCandidate = false,
    this.headers,
  });

  final String url;
  final bool active;
  final bool visible;
  final bool? displaySupported;
  final bool isCandidate;
  final ValueListenable<Rect?> imageRect;
  final void Function(bool displaySupported) onDetected;
  final Map<String, String>? headers;

  @override
  State<HdrGalleryImage> createState() => _HdrGalleryImageState();
}

class _HdrGalleryImageState extends State<HdrGalleryImage> {
  String? _path;
  bool _checking = false;
  bool _checked = false;
  bool _hasGainMap = false;
  bool _displaySupported = false;

  @override
  void initState() {
    super.initState();
    _displaySupported = widget.displaySupported ?? false;
    _hasGainMap = widget.isCandidate;
    _check();
  }

  @override
  void didUpdateWidget(HdrGalleryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.displaySupported != null &&
        widget.displaySupported != _displaySupported) {
      _displaySupported = widget.displaySupported!;
    }
    if (widget.isCandidate && !_hasGainMap) {
      _hasGainMap = true;
    }
    if (oldWidget.active && !widget.active && _path != null) {
      _path = null;
      _checked = false;
    }
    _check();
  }

  Future<void> _check() async {
    if (!widget.active ||
        _checking ||
        _checked ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _checking = true;
    try {
      var file = await cachedHdrImageFile(widget.url);
      // A decoded memory-cache entry can outlive Android's temporary file.
      if (file == null) {
        final isProbeHdr = await cachedSinaHdrGainMapProbe(widget.url);
        if (isProbeHdr) {
          if (!mounted) return;
          _hasGainMap = true;
          if (widget.displaySupported == null) {
            try {
              final supported = await hdrGalleryChannel
                  .invokeMethod<bool>('isHdrDisplaySupported');
              if (supported != null) _displaySupported = supported;
            } catch (_) {}
          }
          widget.onDetected(_displaySupported);
          if (mounted) setState(() {});
        }
        _checked = true;
        await ExtendedNetworkImageProvider(
          widget.url,
          headers: widget.headers,
          cache: true,
        ).getNetworkImageData();
        file = await cachedHdrImageFile(widget.url);
      }
      if (file == null) return;
      final path = file.path;
      final input = await file.open();
      late final List<int> header;
      try {
        // shortcut: probe JPEG metadata in the first 256 KiB; expand if a verified source places it later.
        header = await input.read(256 * 1024);
      } finally {
        await input.close();
      }
      if (!mounted) return;
      _checked = true;
      if (!mayContainHdrGainMap(header)) return;
      final result = await decodeCachedHdrImage(path);
      if (!mounted || result?['hasGainMap'] != true) return;
      final supported = result?['displaySupported'] == true;
      _hasGainMap = true;
      _displaySupported = supported;
      widget.onDetected(supported);
      if (supported && widget.active) {
        setState(() => _path = path);
      } else if (supported) {
        _checked = false;
      }
    } catch (_) {
      // Cache removal, old Android, or decode failure keeps the Flutter image.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    final canShow = _displaySupported && (_hasGainMap || _path != null);
    if (!canShow) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: ValueListenableBuilder<Rect?>(
          valueListenable: widget.imageRect,
          child: PlatformViewLink(
            viewType: 'com.review/hdrImage',
            surfaceFactory: (context, controller) => AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers:
                  const <Factory<OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
            ),
            onCreatePlatformView: (params) =>
                PlatformViewsService.initExpensiveAndroidView(
                    id: params.id,
                    viewType: 'com.review/hdrImage',
                    layoutDirection: Directionality.of(context),
                    creationParams: {
                      'url': widget.url,
                      'headers': widget.headers,
                      if (_path != null) 'path': _path,
                    },
                    creationParamsCodec: const StandardMessageCodec(),
                    onFocus: () => params.onFocusChanged(true),
                  )
                  ..addOnPlatformViewCreatedListener(
                    params.onPlatformViewCreated,
                  )
                  ..create(),
          ),
          builder: (context, rect, nativeView) => Transform(
            alignment: Alignment.topLeft,
            transform: hdrImageViewTransform(
              Offset.zero & constraints.biggest,
              rect,
            ),
            child: Opacity(
              opacity: widget.visible ? 1.0 : 0.0,
              child: IgnorePointer(child: nativeView),
            ),
          ),
        ),
      ),
    );
  }
}

class GalleryHdrBadge extends StatelessWidget {
  const GalleryHdrBadge({super.key, this.thumbnail = false, this.feed = false});
  final bool thumbnail;
  final bool feed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'HDR 图片',
    child: Container(
      padding: EdgeInsets.symmetric(
        horizontal: feed
            ? 5
            : thumbnail
            ? 3
            : 8,
        vertical: feed
            ? 2
            : thumbnail
            ? 1
            : 3,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: thumbnail ? 0.75 : 0.72),
        borderRadius: BorderRadius.circular(
          thumbnail
              ? 3
              : feed
              ? 4
              : 6,
        ),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: thumbnail
                ? 0.5
                : feed
                ? 0.45
                : 0.55,
          ),
          width: thumbnail
              ? 0.5
              : feed
              ? 0.8
              : 1,
        ),
        boxShadow: thumbnail || feed
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
      ),
      child: Text(
        'HDR',
        style: TextStyle(
          color: Colors.white,
          fontSize: thumbnail
              ? 7.5
              : feed
              ? 10
              : 11,
          fontWeight: FontWeight.w900,
          letterSpacing: thumbnail
              ? null
              : feed
              ? 0.4
              : 0.6,
        ),
      ),
    ),
  );
}
