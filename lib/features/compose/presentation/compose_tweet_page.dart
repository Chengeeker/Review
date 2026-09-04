import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../feed/presentation/feed_controller.dart';
import 'widgets/weibo_emoji_keyboard.dart';

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
  static const MethodChannel _locationChannel = MethodChannel('com.sharelite/cookies');

  late final TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _selectedImages = [];
  bool _isPosting = false;
  bool _showEmojiKeyboard = false;

  // 定位状态：显示“你在哪里”或检测到的城市地点
  String? _selectedLocation;
  bool _isSystemLocation = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
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

  // 点击定位设置：申请系统定位或手动选择地点
  Future<void> _pickOrDetectLocation() async {
    HapticFeedbackUtil.light();
    final cities = ['广州', '深圳', '北京', '上海', '佛山', '成都', '杭州', '武汉', '南京', '重庆', '西安', '长沙'];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colorScheme = theme.colorScheme;

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('选择或获取定位', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (_selectedLocation != null)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedLocation = null;
                            _isSystemLocation = false;
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('清除定位'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // 1. 系统定位申请与探测
                ListTile(
                  leading: Icon(Icons.my_location_rounded, color: colorScheme.primary),
                  title: const Text('申请并获取系统精准定位', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('通过系统底层定位权限获取当前所在城市/位置', style: TextStyle(fontSize: 12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: colorScheme.primaryContainer.withValues(alpha: 0.25),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      final String? city = await _locationChannel.invokeMethod<String>('getSystemLocationCity');
                      if (city != null && city.trim().isNotEmpty && mounted) {
                        setState(() {
                          _selectedLocation = city.trim();
                          _isSystemLocation = true;
                        });
                        HapticFeedbackUtil.medium();
                        AppToast.show(context, '📍 已获取定位：$_selectedLocation');
                      }
                    } catch (e) {
                      if (mounted) {
                        AppToast.show(context, '获取定位失败: $e');
                      }
                    }
                  },
                ),
                const SizedBox(height: 14),

                const Text('常用地点快捷选择', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 8),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: cities.map((c) {
                    final isSelected = _selectedLocation == c;
                    return ActionChip(
                      label: Text(c),
                      avatar: Icon(Icons.near_me_outlined, size: 14, color: isSelected ? colorScheme.onPrimary : colorScheme.primary),
                      backgroundColor: isSelected ? colorScheme.primary : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      labelStyle: TextStyle(
                        color: isSelected ? colorScheme.onPrimary : null,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onPressed: () {
                        HapticFeedbackUtil.light();
                        setState(() {
                          _selectedLocation = c;
                          _isSystemLocation = false;
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _uploadSingleImage(WeiboDioClient client, XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      final ext = file.name.split('.').last.toLowerCase();
      String mime = 'image/jpeg';
      if (ext == 'png') {
        mime = 'image/png';
      } else if (ext == 'gif') {
        mime = 'image/gif';
      } else if (ext == 'webp') {
        mime = 'image/webp';
      }

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

  Future<void> _postTweet() async {
    final content = _textController.text.trim();
    if (content.isEmpty && _selectedImages.isEmpty) {
      AppToast.show(context, '请输入微博内容或添加图片');
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

      // Append location if selected
      String finalContent = content;
      if (_selectedLocation != null && _selectedLocation!.trim().isNotEmpty) {
        final loc = _selectedLocation!.trim();
        if (!finalContent.contains(loc)) {
          finalContent = finalContent.isEmpty ? '📍 $loc' : '$finalContent\n📍 $loc';
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

      // Payload map
      final postPayload = <String, dynamic>{
        'content': finalContent,
        if (pids.isNotEmpty) 'pic_id': pids.join(','),
      };

      // If editing an existing status (widget.editMid != null)
      if (widget.editMid != null && widget.editMid!.isNotEmpty) {
        // 1. Try in-place modify
        bool modifiedSuccess = false;
        try {
          final modifyRes = await client.dio.post(
            '/ajax/statuses/modify',
            data: {'id': widget.editMid, ...postPayload},
            options: Options(headers: {'Referer': 'https://weibo.com/'}),
          );
          if (modifyRes.data is Map<String, dynamic> &&
              (modifyRes.data['ok'] == 1 || modifyRes.data['id'] != null)) {
            modifiedSuccess = true;
          }
        } catch (_) {}

        // 2. If in-place modify is not supported for standard users, post new & delete old to ensure true replacement
        if (!modifiedSuccess) {
          final postRes = await client.dio.post(
            '/ajax/statuses/update',
            data: postPayload,
            options: Options(headers: {'Referer': 'https://weibo.com/'}),
          );

          if (postRes.data is Map<String, dynamic> &&
              (postRes.data['ok'] == 1 || postRes.data['id'] != null)) {
            // Delete old tweet
            await ref.read(feedControllerProvider.notifier).deleteStatus(widget.editMid!);
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
          options: Options(headers: {'Referer': 'https://weibo.com/'}),
        );

        if (response.data is Map<String, dynamic> &&
            (response.data['ok'] == 1 || response.data['id'] != null)) {
          if (mounted) {
            AppToast.show(context, '🎉 微博发布成功！');
            ref.read(feedControllerProvider.notifier).refreshFeed();
            Navigator.of(context).pop(true);
          }
          return;
        }
      }

      if (mounted) {
        AppToast.show(context, '发布完成，如未刷新请拉动时间线');
        ref.read(feedControllerProvider.notifier).refreshFeed();
        Navigator.of(context).pop(true);
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
        ),
        body: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        style: textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
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
                          itemCount: _selectedImages.length + (_selectedImages.length < 9 ? 1 : 0),
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
                                    border: Border.all(color: colorScheme.outlineVariant),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.add_photo_alternate_outlined, color: colorScheme.primary),
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
                                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 6),

                    // 4.2 编辑区域底部栏：左边定位设置（指针图标）+ 右边字数统计
                    Row(
                      children: [
                        // 底部的左边：定位设置（指针罗盘图标 Icons.near_me_outlined）
                        InkWell(
                          onTap: _pickOrDetectLocation,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _selectedLocation != null
                                  ? colorScheme.primaryContainer.withValues(alpha: 0.6)
                                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
                                  color: _selectedLocation != null ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _selectedLocation != null
                                      ? (_isSystemLocation ? '$_selectedLocation·系统定位' : _selectedLocation!)
                                      : '你在哪里',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _selectedLocation != null ? FontWeight.bold : FontWeight.normal,
                                    color: _selectedLocation != null ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (_selectedLocation != null) ...[
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedLocation = null;
                                        _isSystemLocation = false;
                                      });
                                    },
                                    child: Icon(Icons.close_rounded, size: 13, color: colorScheme.primary),
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
                                color: count > 2000 ? colorScheme.error : colorScheme.onSurfaceVariant,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.image_outlined),
                      tooltip: '选择图片',
                      onPressed: _pickImages,
                    ),
                    IconButton(
                      icon: const Icon(Icons.tag_rounded),
                      tooltip: '添加话题',
                      onPressed: () {
                        final current = _textController.text;
                        _textController.text = '$current #话题# ';
                        _textController.selection = TextSelection(
                          baseOffset: _textController.text.length - 4,
                          extentOffset: _textController.text.length - 2,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.alternate_email_rounded),
                      tooltip: '@提到某人',
                      onPressed: () {
                        final current = _textController.text;
                        _textController.text = '$current @';
                        _textController.selection =
                            TextSelection.collapsed(offset: _textController.text.length);
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        _showEmojiKeyboard
                            ? Icons.keyboard_alt_outlined
                            : Icons.sentiment_satisfied_alt_rounded,
                        color: _showEmojiKeyboard ? colorScheme.primary : null,
                      ),
                      tooltip: '表情',
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

                    const Spacer(),

                    // 4.1 发送键移到底栏右边
                    FilledButton.icon(
                      onPressed: _isPosting ? null : _postTweet,
                      icon: _isPosting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 16),
                      label: Text(isEditing ? '保存修改' : '发送'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
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
