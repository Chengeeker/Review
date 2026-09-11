import 'dart:convert';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../feed/presentation/feed_controller.dart';
import '../../search/data/search_repository.dart';
import '../data/weibo_compose_models.dart';
import 'widgets/weibo_emoji_keyboard.dart';
import 'widgets/weibo_publish_picker_sheet.dart';

/// Compose Tweet Page (发微博 / 编辑微博界面 - 支持图库选图、定位设置、表情键盘与编辑替换)
class ComposeTweetPage extends ConsumerStatefulWidget {
  final String? initialText;
  final String? editMid;

  const ComposeTweetPage({
    super.key,
    this.initialText,
    this.editMid,
  });

  @override
  ConsumerState<ComposeTweetPage> createState() => _ComposeTweetPageState();
}

class _ComposeTweetPageState extends ConsumerState<ComposeTweetPage> {
  static const MethodChannel _locationChannel =
      MethodChannel('com.sharelite/cookies');

  late final TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _selectedImages = [];
  XFile? _selectedVideo;
  bool _isPosting = false;
  bool _showEmojiKeyboard = false;
  WeiboVisibility _visibility = WeiboVisibility.public;
  int _mblogStatement = 0;
  List<WeiboDeclarationOption> _statementOptions = const [];

  // 定位状态：显示已选择的微博 POI；系统定位只用于附近检索，不直接显示城市名。
  String? _selectedLocation;
  String? _selectedPoiId;
  String? _selectedPlacePcTitle;
  String? _selectedPlaceLong;
  String? _selectedPlaceLat;
  int _selectedPlaceSpotType = 0;
  String? _reviewFilmId;
  double? _reviewScore;
  String? _selectedTopicId;
  String? _selectedTopicMarker;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText ?? '');
    _loadComposeConfig();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      if (_selectedVideo != null) {
        AppToast.show(context, '图片和视频不能同时发布，请先移除视频');
        return;
      }
      final remaining = 9 - _selectedImages.length;
      if (remaining <= 0) {
        AppToast.show(context, '最多只能添加 9 张图片');
        return;
      }

      final images = await _picker.pickMultiImage(limit: remaining);
      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images.take(remaining));
        });
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '打开相册异常: $e');
      }
    }
  }

  Future<void> _pickVideo() async {
    if (_selectedImages.isNotEmpty) {
      AppToast.show(context, '图片和视频不能同时发布，请先移除图片');
      return;
    }
    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video != null && mounted) {
        setState(() => _selectedVideo = video);
      }
    } catch (e) {
      if (mounted) AppToast.show(context, '打开相册异常: $e');
    }
  }

  Future<void> _pickMedia() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('选择图片'),
              subtitle: const Text('最多 9 张，不能与视频同时发布'),
              onTap: () => Navigator.of(ctx).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('选择视频'),
              subtitle: const Text('从系统相册选择视频'),
              onTap: () => Navigator.of(ctx).pop('video'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'image') {
      await _pickImages();
    } else if (choice == 'video') {
      await _pickVideo();
    }
  }

  dynamic _findConfigValue(dynamic value, String key) {
    if (value is Map) {
      if (value.containsKey(key)) return value[key];
      for (final nested in value.values) {
        final found = _findConfigValue(nested, key);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final nested in value) {
        final found = _findConfigValue(nested, key);
        if (found != null) return found;
      }
    }
    return null;
  }

  dynamic _decodeConfig(dynamic value) {
    if (value is! String) return value;
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  List<WeiboDeclarationOption> _parseDeclarationOptions(dynamic response) {
    response = _decodeConfig(response);
    final roots = <dynamic>[response];
    if (response is Map) {
      final data = _decodeConfig(response['data']);
      roots.add(data);
      if (data is Map) {
        roots.add(_decodeConfig(data['config']));
      }
    }

    // This is the exact shape used by the web publisher:
    // getSpaConfig().data.flags.statement.mblog_statement_list.
    final directLists = <dynamic>[];
    for (final root in roots) {
      if (root is Map) {
        final flags = _decodeConfig(root['flags']);
        final statement =
            flags is Map ? _decodeConfig(flags['statement']) : null;
        if (statement is Map) {
          directLists.add(statement['mblog_statement_list']);
        }
      }
    }
    final candidates = <dynamic>[
      ...directLists,
      for (final root in roots) _findConfigValue(root, 'mblog_statement_list'),
      for (final root in roots) _findConfigValue(root, 'statement_list'),
      for (final root in roots) _findConfigValue(root, 'declaration_list'),
      for (final root in roots) _findConfigValue(root, 'content_declaration'),
    ];
    final options = <WeiboDeclarationOption>[];
    for (final raw in candidates) {
      final decodedRaw = _decodeConfig(raw);
      if (decodedRaw is List) {
        for (final item in decodedRaw) {
          if (item is! Map) continue;
          final value = int.tryParse(
            (item['type'] ?? item['value'] ?? item['id'] ?? item['code'])
                    ?.toString() ??
                '',
          );
          final label = (item['name'] ??
                      item['text'] ??
                      item['label'] ??
                      item['title'] ??
                      item['desc'])
                  ?.toString()
                  .trim() ??
              '';
          if (value != null && value != 0 && label.isNotEmpty) {
            if (!options.any((option) => option.value == value)) {
              options.add(WeiboDeclarationOption(value: value, label: label));
            }
          }
        }
      } else if (decodedRaw is Map) {
        for (final entry in decodedRaw.entries) {
          final value = int.tryParse(entry.key.toString());
          final label = entry.value?.toString().trim() ?? '';
          if (value != null && value != 0 && label.isNotEmpty) {
            if (!options.any((option) => option.value == value)) {
              options.add(WeiboDeclarationOption(value: value, label: label));
            }
          }
        }
      }
      if (options.isNotEmpty) return options;
    }
    return options;
  }

  Future<void> _loadComposeConfig() async {
    try {
      final client = ref.read(weiboDioClientProvider);
      // 网页端启动时先读取 getSpaConfig，发布器使用其中的
      // data.flags.statement.mblog_statement_list。
      final requests = const [
        (
          path: '/ajax/getSpaConfig',
          query: <String, dynamic>{},
        ),
        (
          path: '/ajax/statuses/config',
          query: <String, dynamic>{},
        ),
        (
          path: '/ajax/statuses/config',
          query: <String, dynamic>{'type': 'push_active'},
        ),
      ];
      for (final request in requests) {
        try {
          final response = await client.dio.get(
            request.path,
            queryParameters: request.query,
          );
          final options = _parseDeclarationOptions(response.data);
          if (options.isNotEmpty) {
            if (mounted) setState(() => _statementOptions = options);
            return;
          }
        } catch (_) {}
      }
      if (mounted && _statementOptions.isEmpty) {
        debugPrint('Weibo compose config has no content declaration options');
      }
    } catch (e) {
      debugPrint('Unable to load Weibo compose config: $e');
    }
  }

  void _insertEmoji(String emoji) {
    final text = _textController.text;
    final selection = _textController.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;

    final newText = text.replaceRange(start, end, emoji);
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  void _handleBackspace() {
    final text = _textController.text;
    final selection = _textController.selection;
    if (text.isEmpty) return;

    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;

    if (start != end) {
      final newText = text.replaceRange(start, end, '');
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start),
      );
    } else if (start > 0) {
      // Check if deleting a [xxx] emoji bracket
      if (text.endsWith(']') || (start > 1 && text[start - 1] == ']')) {
        final lastOpen = text.lastIndexOf('[', start - 1);
        if (lastOpen != -1 && (start - lastOpen) <= 8) {
          final newText = text.replaceRange(lastOpen, start, '');
          _textController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: lastOpen),
          );
          return;
        }
      }

      final newText = text.replaceRange(start - 1, start, '');
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start - 1),
      );
    }
  }

  // 微博网页端地点选择器：系统定位只作为附近 POI 检索和距离排序依据，
  // 不把地级市预填进搜索框。
  Future<void> _pickOrDetectLocation() async {
    double? latitude;
    double? longitude;
    try {
      final location =
          await _locationChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getSystemLocation',
      );
      final rawLatitude = location?['latitude'];
      final rawLongitude = location?['longitude'];
      latitude = rawLatitude is num
          ? rawLatitude.toDouble()
          : double.tryParse(rawLatitude?.toString() ?? '');
      longitude = rawLongitude is num
          ? rawLongitude.toDouble()
          : double.tryParse(rawLongitude?.toString() ?? '');
    } catch (_) {
      // 没有定位权限时仍允许手动搜索微博地点。
    }

    if (!mounted) return;
    final selection = await showModalBottomSheet<WeiboPublishPickerSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: WeiboPublishPickerSheet(
          mode: WeiboPublishPickerMode.place,
          repository: ref.read(searchRepositoryProvider),
          initialQuery: '',
          latitude: latitude,
          longitude: longitude,
        ),
      ),
    );
    if (selection?.place == null || !mounted) return;
    final place = selection!.place!;
    setState(() {
      _selectedLocation = place.title;
      _selectedPoiId = place.poiid;
      _selectedPlacePcTitle = place.pcTitle;
      _selectedPlaceLong = place.longitude;
      _selectedPlaceLat = place.latitude;
      _selectedPlaceSpotType = place.spotType;
    });
    HapticFeedbackUtil.medium();
  }

  void _clearLocation() {
    setState(() {
      _selectedLocation = null;
      _selectedPoiId = null;
      _selectedPlacePcTitle = null;
      _selectedPlaceLong = null;
      _selectedPlaceLat = null;
      _selectedPlaceSpotType = 0;
    });
  }

  String _mimeTypeForFile(XFile file) {
    final ext = file.name.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<String?> _uploadSingleImage(WeiboDioClient client, XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final webResponse = await client.dio.post(
        'https://picupload.weibo.com/interface/pic_upload.php?app=miniblog&s=json&p=1&data=1',
        data: bytes,
        options: Options(
          contentType: 'application/octet-stream',
          responseType: ResponseType.json,
          headers: {'Referer': 'https://weibo.com/'},
        ),
      );
      final webPid = _extractMediaId(webResponse.data);
      if (webPid != null && webPid.isNotEmpty) return webPid;
    } catch (e) {
      debugPrint('Web image upload failed, trying legacy uploader: $e');
    }

    try {
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      final mime = _mimeTypeForFile(file);

      final res = await client.dio.post(
        'https://picupload.weibo.com/interface/pic_upload.php?mime=${Uri.encodeQueryComponent(mime)}&data=base64&url=0&markpos=1&logo=&nick=0&marks=0&app=miniblog',
        data: 'b64_data=${Uri.encodeQueryComponent(b64)}',
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          headers: {
            'Referer': 'https://weibo.com/',
            'Origin': 'https://weibo.com',
          },
        ),
      );

      final body = res.data.toString();
      // 1. Direct pid match
      final directPidMatch = RegExp(r'"pid"\s*:\s*"([^"]+)"').firstMatch(body);
      if (directPidMatch != null) {
        return directPidMatch.group(1);
      }

      // 2. Base64 nested payload inside "data":"..."
      final dataMatch = RegExp(r'"data"\s*:\s*"([^"]+)"').firstMatch(body);
      if (dataMatch != null) {
        final b64Str = dataMatch.group(1)!;
        try {
          final decoded = utf8.decode(base64Decode(b64Str));
          final pidMatch = RegExp(r'"pid"\s*:\s*"([^"]+)"').firstMatch(decoded);
          if (pidMatch != null) {
            return pidMatch.group(1);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error uploading image to Weibo pic_upload: $e');
    }
    return null;
  }

  Future<Map<String, String>?> _uploadSingleVideo(
    WeiboDioClient client,
    XFile file,
  ) async {
    final size = await file.length();
    if (size <= 0) return null;
    if (size > 15 * 1024 * 1024 * 1024) {
      AppToast.show(context, '视频不能超过 15GB');
      return null;
    }

    try {
      final groupResponse =
          await client.dio.get('/ajax/multimedia/mediaGroupInit');
      final mediaGroupId =
          _findConfigValue(groupResponse.data, 'media_group_id')?.toString() ??
              '';
      if (mediaGroupId.isEmpty) return null;

      final dispatchResponse = await client.dio.post(
        '/ajax/multimedia/dispatch',
        data: {
          'source': 339644097,
          'types': 'video',
          'version': 4,
          'auth_accept': 'video',
          // 网页端 dispatch() 会用当前文件大小覆盖默认 chunk size。
          'size': size,
          'timeout': 180000,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Referer': 'https://weibo.com/'},
        ),
      );
      final videoDispatch = _findConfigValue(dispatchResponse.data, 'video');
      if (videoDispatch is! Map) return null;
      final initUrl = videoDispatch['init_url']?.toString() ?? '';
      final uploadUrl = videoDispatch['upload_url']?.toString() ?? '';
      final checkUrl = videoDispatch['check_url']?.toString() ?? '';
      if (initUrl.isEmpty || uploadUrl.isEmpty || checkUrl.isEmpty) return null;

      final fileName = file.name.isEmpty ? 'video.mp4' : file.name;
      final sessionId = '${DateTime.now().millisecondsSinceEpoch}-$size';
      final initBody = jsonEncode({
        'mediaprops': jsonEncode({
          'screenshot': 1,
          'media_group_id': mediaGroupId,
        }),
      });
      final boundary =
          '2067456weiboPro${DateTime.now().millisecondsSinceEpoch}';
      final multipartBody = utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="biz_file"\r\n'
        '\r\n'
        '$initBody\r\n'
        '--$boundary--\r\n',
      );

      final initResponse = await client.dio.post(
        initUrl,
        queryParameters: {
          'source': 339644097,
          'size': size,
          'name': fileName,
          'type': 'video',
          'client': 'web',
          'session_id': sessionId,
        },
        data: multipartBody,
        options: Options(
          contentType: 'multipart/mixed; boundary=$boundary',
          responseType: ResponseType.json,
          headers: {'Referer': 'https://weibo.com/'},
        ),
      );
      final initData =
          initResponse.data is Map && initResponse.data['data'] is Map
              ? initResponse.data['data']
              : initResponse.data;
      if (initData is! Map) return null;
      final uploadId = initData['upload_id']?.toString() ?? '';
      final mediaId = initData['media_id']?.toString() ?? '';
      final auth = initData['auth']?.toString() ?? '';
      final strategy = initData['strategy'];
      final chunkSize = strategy is Map
          ? (int.tryParse(strategy['chunk_size']?.toString() ?? '') ?? 8192) *
              1024
          : 8192 * 1024;
      if (uploadId.isEmpty || mediaId.isEmpty || auth.isEmpty) return null;

      final input = await File(file.path).open(mode: FileMode.read);
      try {
        final chunkCount = (size + chunkSize - 1) ~/ chunkSize;
        for (var index = 0; index < chunkCount; index++) {
          final start = index * chunkSize;
          final length = (size - start) > chunkSize ? chunkSize : size - start;
          await input.setPosition(start);
          final chunk = await input.read(length);
          final chunkMd5 = md5.convert(chunk).toString();
          await client.dio.post(
            uploadUrl,
            queryParameters: {
              'source': 339644097,
              'upload_id': uploadId,
              'media_id': mediaId,
              'upload_protocol': 'binary',
              'type': 'video',
              'client': 'web',
              'check': chunkMd5,
              'index': index,
              'size': length,
              'start_loc': start,
              'count': chunkCount,
            },
            data: chunk,
            options: Options(
              contentType: 'application/octet-stream',
              headers: {
                'Referer': 'https://weibo.com/',
                'X-Up-Auth': auth,
              },
              sendTimeout: const Duration(minutes: 3),
              receiveTimeout: const Duration(minutes: 3),
            ),
          );
        }
      } finally {
        await input.close();
      }

      final checkResponse = await client.dio.post(
        checkUrl,
        data: {
          'source': 339644097,
          'upload_id': uploadId,
          'media_id': mediaId,
          'upload_protocol': 'binary',
          'count': (size + chunkSize - 1) ~/ chunkSize,
          'action': 'finish',
          'size': size,
          'client': 'web',
          'status': '',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Referer': 'https://weibo.com/', 'X-Up-Auth': auth},
        ),
      );
      final checkData = checkResponse.data;
      final resultValue = checkData is Map ? checkData['result'] : null;
      final successful = resultValue == true ||
          resultValue == 1 ||
          resultValue?.toString().toLowerCase() == 'true' ||
          resultValue?.toString() == '1';
      if (!successful) return null;

      return {
        'mediaId': mediaId,
        'mediaGroupId': mediaGroupId,
        'pid': '',
      };
    } catch (e) {
      debugPrint('Web video upload failed: $e');
      return null;
    }
  }

  String? _extractMediaId(dynamic value) {
    if (value is String) {
      final match = RegExp(r'"pid"\s*:\s*"([^"]+)"').firstMatch(value);
      return match?.group(1);
    }
    if (value is Map) {
      for (final key in const [
        'pic_id',
        'picId',
        'image_id',
        'imageId',
        'media_id',
        'mediaId',
      ]) {
        final candidate = value[key]?.toString();
        if (candidate != null && candidate.isNotEmpty) return candidate;
      }

      for (final key in const ['data', 'result', 'resource', 'upload']) {
        final nested = _extractMediaId(value[key]);
        if (nested != null && nested.isNotEmpty) return nested;
      }

      for (final nested in value.values) {
        final id = _extractMediaId(nested);
        if (id != null && id.isNotEmpty) return id;
      }
    } else if (value is List) {
      for (final item in value) {
        final nested = _extractMediaId(item);
        if (nested != null && nested.isNotEmpty) return nested;
      }
    }
    return null;
  }

  Future<void> _showVisibilityPicker() async {
    final selected = await showModalBottomSheet<WeiboVisibility>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: WeiboVisibility.values
              .map(
                (value) => ListTile(
                  title: Text(value.label),
                  trailing: value == _visibility
                      ? Icon(Icons.check_rounded,
                          color: Theme.of(ctx).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(value),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _visibility = selected);
    }
  }

  Future<void> _showContentDeclarationPicker() async {
    if (_statementOptions.isEmpty) {
      await _loadComposeConfig();
    }
    if (!mounted) return;
    if (_statementOptions.isEmpty) {
      AppToast.show(context, '微博服务器暂未返回内容声明选项，请稍后重试');
      return;
    }

    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('无'),
              trailing: _mblogStatement == 0
                  ? Icon(Icons.check_rounded,
                      color: Theme.of(ctx).colorScheme.primary)
                  : null,
              onTap: () => Navigator.of(ctx).pop(0),
            ),
            ..._statementOptions.map(
              (value) => ListTile(
                title: Text(value.label),
                trailing: value.value == _mblogStatement
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(value.value),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _mblogStatement = selected);
    }
  }

  Future<void> _showScheduleInfo() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('定时微博'),
        content:
            const Text('定时发布由微博网页端的独立流程处理。当前账号的网页端入口需要开通会员，应用不会伪造一个本地定时发布。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<WeiboPublishPickerSelection?> _showPublishPicker(
    WeiboPublishPickerMode mode, {
    String initialQuery = '',
  }) {
    return showModalBottomSheet<WeiboPublishPickerSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: WeiboPublishPickerSheet(
          mode: mode,
          repository: ref.read(searchRepositoryProvider),
          initialQuery: initialQuery,
        ),
      ),
    );
  }

  Future<void> _showMentionPicker() async {
    final selection = await _showPublishPicker(WeiboPublishPickerMode.mention);
    if (selection != null && mounted) _insertTextAtCursor(selection.text);
  }

  Future<void> _showTopicPicker() async {
    final selection = await _showPublishPicker(WeiboPublishPickerMode.topic);
    if (selection != null && mounted) {
      setState(() {
        _selectedTopicId =
            selection.topicId?.isNotEmpty == true ? selection.topicId : null;
        _selectedTopicMarker = selection.topicId?.isNotEmpty == true
            ? selection.text.trim()
            : null;
      });
      _insertTextAtCursor(selection.text);
    }
  }

  Future<void> _showSuperTopicPicker() async {
    final selection =
        await _showPublishPicker(WeiboPublishPickerMode.superTopic);
    if (selection != null && mounted) {
      setState(() {
        _selectedTopicId =
            selection.topicId?.isNotEmpty == true ? selection.topicId : null;
        _selectedTopicMarker = selection.topicId?.isNotEmpty == true
            ? selection.text.trim()
            : null;
      });
      _insertTextAtCursor(selection.text);
    }
  }

  Future<void> _showReviewPicker() async {
    final selection = await _showPublishPicker(WeiboPublishPickerMode.review);
    final movie = selection?.movie;
    if (movie == null || !mounted) return;
    final score = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('点评《${movie.title}》')),
            for (var value = 1; value <= 5; value++)
              ListTile(
                leading: const Icon(Icons.star_rounded, color: Colors.amber),
                title: Text(['很差', '一般', '还行', '不错', '超赞'][value - 1]),
                onTap: () => Navigator.of(ctx).pop(value.toDouble()),
              ),
          ],
        ),
      ),
    );
    if (score != null && mounted) {
      setState(() {
        _reviewFilmId = movie.filmId;
        _reviewScore = score;
      });
      _insertTextAtCursor('《${movie.title}》');
    }
  }

  void _insertTextAtCursor(String value) {
    final text = _textController.text;
    final selection = _textController.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final updated = text.replaceRange(start, end, value);
    _textController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
  }

  bool _isPublishSuccess(dynamic data) {
    if (data is! Map) return false;
    final ok = int.tryParse(data['ok']?.toString() ?? '');
    return (ok != null && ok > 0) || data['id'] != null;
  }

  String get _visibilityShortLabel {
    switch (_visibility) {
      case WeiboVisibility.public:
        return '公开';
      case WeiboVisibility.fans:
        return '粉丝';
      case WeiboVisibility.friends:
        return '好友';
      case WeiboVisibility.self:
        return '私密';
      case WeiboVisibility.group:
        return '群友';
    }
  }

  String get _contentDeclarationShortLabel {
    if (_mblogStatement == 0) return '无声明';

    final option = _statementOptions.cast<WeiboDeclarationOption?>().firstWhere(
          (value) => value?.value == _mblogStatement,
          orElse: () => null,
        );
    final label = option?.label.trim() ?? '';
    final normalized = label.toLowerCase();
    if (normalized.contains('转载')) return '转载';
    if (normalized.contains('自主创作') ||
        normalized.contains('原创') ||
        normalized == '创作') {
      return '创作';
    }
    if (normalized.contains('ai') ||
        normalized.contains('人工智能') ||
        normalized.contains('生成式')) {
      return 'AI';
    }
    if (normalized.contains('虚构') || normalized.contains('演绎')) {
      return '虚构';
    }
    return label.isEmpty ? '无声明' : label;
  }

  Widget _publishSettingChip({
    required String label,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: ActionChip(
        label: Text(label),
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        labelStyle: TextStyle(
          fontSize: 11,
          color: colorScheme.onSurfaceVariant,
        ),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: .7),
        ),
        shape: const StadiumBorder(),
      ),
    );
  }

  Widget _toolbarAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool active = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color:
                  active ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color:
                    active ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addTopic() {
    _showTopicPicker();
  }

  Future<void> _postTweet() async {
    final content = _textController.text.trim();
    if (content.isEmpty && _selectedImages.isEmpty && _selectedVideo == null) {
      AppToast.show(context, '请输入微博内容或添加图片/视频');
      return;
    }

    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      AppToast.show(context, '请先登录微博账号');
      return;
    }

    setState(() => _isPosting = true);

    try {
      final client = ref.read(weiboDioClientProvider);

      // 微博网页端只在有真实 POI 时提交位置字段；只有城市名时保留兼容性的文本标记。
      String finalContent = content;
      Map<String, dynamic>? position;
      if (_selectedPoiId != null && _selectedPoiId!.isNotEmpty) {
        position = {
          'poiid': _selectedPoiId,
          'poititle': _selectedLocation ?? '',
          'pc_title': _selectedPlacePcTitle ?? '',
          'long': _selectedPlaceLong ?? '',
          'lat': _selectedPlaceLat ?? '',
          'spot_type': _selectedPlaceSpotType,
        };
        if (_selectedPlacePcTitle != null &&
            _selectedPlacePcTitle!.trim().isNotEmpty &&
            !finalContent.contains(_selectedPlacePcTitle!.trim())) {
          finalContent =
              '$finalContent${finalContent.isEmpty ? '' : '\n'}${_selectedPlacePcTitle!.trim()}';
        }
      } else if (_selectedLocation != null &&
          _selectedLocation!.trim().isNotEmpty) {
        final loc = _selectedLocation!.trim();
        if (!finalContent.contains(loc)) {
          finalContent =
              finalContent.isEmpty ? '📍 $loc' : '$finalContent\n📍 $loc';
        }
      }

      // Upload images if any
      final pids = <String>[];
      if (_selectedImages.isNotEmpty) {
        for (int i = 0; i < _selectedImages.length; i++) {
          final img = _selectedImages[i];
          final pid = await _uploadSingleImage(client, img);
          if (pid != null && pid.isNotEmpty) {
            pids.add(pid);
          } else {
            if (mounted) {
              AppToast.show(context, '第 ${i + 1} 张图片上传失败，请检查网络后重试');
            }
            setState(() => _isPosting = false);
            return;
          }
        }
      }

      Map<String, String>? videoUpload;
      if (_selectedVideo != null) {
        videoUpload = await _uploadSingleVideo(client, _selectedVideo!);
        if (videoUpload == null) {
          if (mounted) AppToast.show(context, '视频上传失败，请稍后重试');
          return;
        }
      }

      // Payload follows the current web publisher contract. The media IDs
      // returned by pic_upload are wrapped as the web publisher's pic_id JSON.
      final selectedTopicId = _selectedTopicId != null &&
              _selectedTopicMarker != null &&
              finalContent.contains(_selectedTopicMarker!)
          ? _selectedTopicId
          : null;
      final postPayload = buildWeiboComposePayload(
        text: finalContent,
        visibility: _visibility,
        imageIds: pids,
        imageTypes: _selectedImages.map(_mimeTypeForFile).toList(),
        videoId: videoUpload?['mediaId'],
        videoPid: videoUpload?['pid'],
        videoMediaGroupId: videoUpload?['mediaGroupId'],
        position: position,
        ratingObjectId:
            _reviewFilmId == null ? null : '1022:100120$_reviewFilmId',
        // 网页端点评弹窗提交的是 0.2 - 1.0 的五分制比例值。
        score: _reviewScore == null ? null : _reviewScore! / 5,
        topicId: selectedTopicId,
        syncMblog: selectedTopicId != null,
        mblogStatement: _mblogStatement,
      );

      // If editing an existing status (widget.editMid != null)
      if (widget.editMid != null && widget.editMid!.isNotEmpty) {
        // 1. Try in-place modify
        bool modifiedSuccess = false;
        try {
          final modifyRes = await client.dio.post(
            '/ajax/statuses/modify',
            data: {'id': widget.editMid, ...postPayload},
            options: Options(
              contentType: Headers.formUrlEncodedContentType,
              headers: {'Referer': 'https://weibo.com/'},
            ),
          );
          if (_isPublishSuccess(modifyRes.data)) {
            modifiedSuccess = true;
          }
        } catch (_) {}

        // 2. If in-place modify is not supported for standard users, post new & delete old to ensure true replacement
        if (!modifiedSuccess) {
          final postRes = await client.dio.post(
            '/ajax/statuses/update',
            data: postPayload,
            options: Options(
              contentType: Headers.formUrlEncodedContentType,
              headers: {'Referer': 'https://weibo.com/'},
            ),
          );

          if (_isPublishSuccess(postRes.data)) {
            // Delete old tweet
            await ref
                .read(feedControllerProvider.notifier)
                .deleteStatus(widget.editMid!);
            modifiedSuccess = true;
          }
        }

        if (modifiedSuccess) {
          if (mounted) {
            AppToast.show(context, '🎉 微博已成功更新！');
            ref.read(feedControllerProvider.notifier).refreshFeed();
            Navigator.of(context).pop(true);
          }
          return;
        }
      } else {
        // Standard new tweet post
        final response = await client.dio.post(
          '/ajax/statuses/update',
          data: postPayload,
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {'Referer': 'https://weibo.com/'},
          ),
        );

        if (_isPublishSuccess(response.data)) {
          if (mounted) {
            AppToast.show(context, '🎉 微博发布成功！');
            ref.read(feedControllerProvider.notifier).refreshFeed();
            Navigator.of(context).pop(true);
          }
          return;
        }
      }

      if (mounted) {
        AppToast.show(context, '微博发布失败，微博服务器未确认写入成功');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '操作异常: $e');
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isEditing = widget.editMid != null && widget.editMid!.isNotEmpty;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (_showEmojiKeyboard) {
          setState(() => _showEmojiKeyboard = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? '编辑微博' : '发微博'),
          actions: [
            _publishSettingChip(
              label: '无定时',
              tooltip: '定时微博',
              onPressed: _showScheduleInfo,
            ),
            _publishSettingChip(
              label: _visibilityShortLabel,
              tooltip: '可见范围',
              onPressed: _showVisibilityPicker,
            ),
            _publishSettingChip(
              label: _contentDeclarationShortLabel,
              tooltip: '内容声明',
              onPressed: _showContentDeclarationPicker,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    // Text Input
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        autofocus: true,
                        style: textTheme.bodyLarge
                            ?.copyWith(fontSize: 16, height: 1.5),
                        decoration: InputDecoration(
                          hintText: isEditing ? '修改你的微博内容...' : '分享新鲜事...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onTap: () {
                          if (_showEmojiKeyboard) {
                            setState(() => _showEmojiKeyboard = false);
                          }
                        },
                      ),
                    ),

                    // Selected Images Preview Grid
                    if (_selectedImages.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        height: 90,
                        alignment: Alignment.centerLeft,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _selectedImages.length +
                              (_selectedImages.length < 9 ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            if (index == _selectedImages.length) {
                              return InkWell(
                                onTap: _pickImages,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: colorScheme.outlineVariant),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                      Icons.add_photo_alternate_outlined,
                                      color: colorScheme.primary),
                                ),
                              );
                            }

                            final file = _selectedImages[index];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(file.path),
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _selectedImages.removeAt(index);
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close,
                                          size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],

                    if (_selectedVideo != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.video_file_outlined,
                                color: colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedVideo!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              tooltip: '移除视频',
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  setState(() => _selectedVideo = null),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 6),

                    if (_reviewFilmId != null) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          children: [
                            if (_reviewFilmId != null)
                              InputChip(
                                avatar:
                                    const Icon(Icons.star_rounded, size: 16),
                                label: Text(
                                    '点评 ${_reviewScore?.toStringAsFixed(0) ?? ''} 星'),
                                onDeleted: () => setState(() {
                                  _reviewFilmId = null;
                                  _reviewScore = null;
                                }),
                              ),
                          ],
                        ),
                      ),
                    ],

                    // 4.2 编辑区域底部栏：左边定位设置（指针图标）+ 右边字数统计
                    Row(
                      children: [
                        // 底部的左边：定位设置（指针罗盘图标 Icons.near_me_outlined）
                        InkWell(
                          onTap: _pickOrDetectLocation,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _selectedLocation != null
                                  ? colorScheme.primaryContainer
                                      .withValues(alpha: 0.6)
                                  : colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _selectedLocation != null
                                    ? colorScheme.primary.withValues(alpha: 0.4)
                                    : Colors.transparent,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.near_me_outlined,
                                  size: 15,
                                  color: _selectedLocation != null
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _selectedLocation != null
                                      ? _selectedLocation!
                                      : '你在哪里',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _selectedLocation != null
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: _selectedLocation != null
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (_selectedLocation != null) ...[
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () {
                                      _clearLocation();
                                    },
                                    child: Icon(Icons.close_rounded,
                                        size: 13, color: colorScheme.primary),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        const Spacer(),

                        // 底部的右边：字数统计
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _textController,
                          builder: (context, value, _) {
                            final count = value.text.length;
                            return Text(
                              '$count 字',
                              style: TextStyle(
                                fontSize: 12,
                                color: count > 2000
                                    ? colorScheme.error
                                    : colorScheme.onSurfaceVariant,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // 4.1 底栏 Action Toolbar (左侧操作项 + 最右侧发送按钮)
            Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                border: Border(
                  top: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _toolbarAction(
                              icon: _showEmojiKeyboard
                                  ? Icons.keyboard_alt_outlined
                                  : Icons.sentiment_satisfied_alt_rounded,
                              label: '表情',
                              active: _showEmojiKeyboard,
                              onPressed: () {
                                setState(() {
                                  _showEmojiKeyboard = !_showEmojiKeyboard;
                                  if (_showEmojiKeyboard) {
                                    _focusNode.unfocus();
                                  } else {
                                    _focusNode.requestFocus();
                                  }
                                });
                              },
                            ),
                            _toolbarAction(
                              icon: Icons.perm_media_outlined,
                              label: '媒体',
                              onPressed: _pickMedia,
                            ),
                            _toolbarAction(
                              icon: Icons.tag_rounded,
                              label: '话题',
                              onPressed: _addTopic,
                            ),
                            _toolbarAction(
                              icon: Icons.forum_outlined,
                              label: '超话',
                              onPressed: _showSuperTopicPicker,
                            ),
                            _toolbarAction(
                              icon: Icons.alternate_email_rounded,
                              label: '提及',
                              onPressed: _showMentionPicker,
                            ),
                            _toolbarAction(
                              icon: Icons.rate_review_outlined,
                              label: '点评',
                              onPressed: _showReviewPicker,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: _isPosting ? null : _postTweet,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: _isPosting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(isEditing ? '保存修改' : '发送'),
                    ),
                  ],
                ),
              ),
            ),

            // Weibo Emoji Keyboard
            if (_showEmojiKeyboard)
              WeiboEmojiKeyboard(
                onEmojiSelected: _insertEmoji,
                onBackspace: _handleBackspace,
              ),
          ],
        ),
      ),
    );
  }
}
