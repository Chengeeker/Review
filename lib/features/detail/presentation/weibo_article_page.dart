import 'dart:async';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/weibo_dio_client.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/services/link_routing_service.dart';
import '../../../core/utils/spring_page_route.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../feed/data/models/weibo_status_model.dart';
import 'widgets/image_gallery_page.dart';

enum WeiboArticleBlockType { text, heading, image }

class WeiboArticleInline {
  final String text;
  final String? url;

  const WeiboArticleInline(this.text, {this.url});
}

/// A small, source-faithful representation of the official article HTML.
///
/// Weibo's article page is HTML rather than a stable JSON API. Keeping the
/// parsed result in an explicit model makes the native renderer testable and
/// prevents the UI from silently depending on the page's surrounding chrome.
class WeiboArticleBlock {
  final WeiboArticleBlockType type;
  final String value;
  final String? caption;
  final double aspectRatio;
  final List<WeiboArticleInline> inlines;

  const WeiboArticleBlock.text(this.value,
      {this.type = WeiboArticleBlockType.text})
      : caption = null,
        aspectRatio = 1.5,
        inlines = const [];

  const WeiboArticleBlock.richText(
    this.value,
    this.inlines, {
    this.type = WeiboArticleBlockType.text,
  })  : caption = null,
        aspectRatio = 1.5;

  const WeiboArticleBlock.heading(this.value)
      : type = WeiboArticleBlockType.heading,
        caption = null,
        aspectRatio = 1.5,
        inlines = const [];

  const WeiboArticleBlock.image(
    this.value, {
    this.caption,
    this.aspectRatio = 1.5,
  })  : type = WeiboArticleBlockType.image,
        inlines = const [];
}

class WeiboArticleDocument {
  final String title;
  final String author;
  final String authorAvatar;
  final String publishedAt;
  final String readCount;
  final String? coverImage;
  final List<WeiboArticleBlock> blocks;

  const WeiboArticleDocument({
    required this.title,
    required this.author,
    required this.authorAvatar,
    required this.publishedAt,
    required this.readCount,
    required this.coverImage,
    required this.blocks,
  });
}

/// Parses only the article content returned by the official Weibo page.
///
/// The selectors are deliberately anchored to the official article markers
/// (`node-type="articleTitle"` and `node-type="contentBody"`) and use class
/// fallbacks for older article templates. No local article content is added.
class WeiboArticleParser {
  WeiboArticleParser._();

  static WeiboArticleDocument parse(
    String rawHtml, {
    String? fallbackTitle,
  }) {
    final document = html_parser.parse(rawHtml);
    final title = _cleanText(
      document.querySelector('[node-type="articleTitle"]')?.text ?? '',
    ).isNotEmpty
        ? _cleanText(
            document.querySelector('[node-type="articleTitle"]')!.text,
          )
        : _cleanText(
                fallbackTitle ?? document.querySelector('title')?.text ?? '')
            .replaceFirst(
                RegExp(r'\s*[-|｜]\s*微博\s*$', caseSensitive: false), '')
            .trim();

    final authorInfo = document.querySelector('.authorinfo');
    final author = _cleanText(
      authorInfo?.querySelector('a[href*="/u/"] em')?.text ??
          authorInfo?.querySelector('a[href*="/u/"]')?.text ??
          '',
    );
    final avatar = _resolveUrl(
      authorInfo?.querySelector('img.W_face_radius')?.attributes['src'],
    );
    final publishedAt =
        _cleanText(authorInfo?.querySelector('.time')?.text ?? '');
    final readCount = _cleanText(authorInfo?.querySelector('.num')?.text ?? '');
    final coverImage = _imageUrl(
      document.querySelector('[node-type="articleHeaderPic"]'),
    );

    final body = document.querySelector('[node-type="contentBody"]') ??
        document.querySelector('.WB_editor_iframe');
    final blocks = <WeiboArticleBlock>[];
    if (body != null) {
      for (final child in body.children) {
        _appendElement(child, blocks);
      }
    }

    return WeiboArticleDocument(
      title: title.isNotEmpty ? title : (fallbackTitle ?? '微博文章'),
      author: author,
      authorAvatar: avatar ?? '',
      publishedAt: publishedAt,
      readCount: readCount,
      coverImage: coverImage,
      blocks: List.unmodifiable(blocks),
    );
  }

  static void _appendElement(
    dom.Element element,
    List<WeiboArticleBlock> blocks,
  ) {
    final tag = (element.localName ?? '').toLowerCase();
    if (const {'script', 'style', 'noscript', 'iframe', 'button'}
        .contains(tag)) {
      return;
    }

    if (tag == 'figure') {
      _appendImages(element, blocks, includeText: false);
      return;
    }
    if (tag == 'img') {
      _appendImage(element, blocks);
      return;
    }

    if (tag == 'a') {
      final text = _cleanText(element.text);
      final url = _resolveUrl(
        element.attributes['href'] ??
            element.attributes['data-href'] ??
            element.attributes['data-url'],
      );
      if (text.isNotEmpty) {
        blocks.add(
          url == null
              ? WeiboArticleBlock.text(text)
              : WeiboArticleBlock.richText(
                  text,
                  [WeiboArticleInline(text, url: url)],
                ),
        );
      }
      return;
    }

    final isTextBlock = const {
      'p',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'blockquote',
      'li',
    }.contains(tag);
    final images = element.querySelectorAll('img');
    if (isTextBlock) {
      final text = _cleanText(element.text);
      if (text.isNotEmpty) {
        final isHeading = tag.startsWith('h') ||
            (element.querySelector('strong') != null && text.length <= 80);
        final inlines = _extractInlines(element);
        final hasLink = inlines.any((inline) => inline.url != null);
        blocks.add(isHeading
            ? WeiboArticleBlock.heading(text)
            : hasLink
                ? WeiboArticleBlock.richText(text, inlines)
                : WeiboArticleBlock.text(text));
      }
      for (final image in images) {
        _appendImage(image, blocks);
      }
      return;
    }

    if (images.isNotEmpty) {
      final text = _cleanText(element.text);
      if (text.isNotEmpty) blocks.add(WeiboArticleBlock.text(text));
      for (final image in images) {
        _appendImage(image, blocks);
      }
      return;
    }

    // Some older templates add a wrapper div around the actual paragraphs.
    // Walk it instead of flattening the whole article into one text block.
    if (element.children.isNotEmpty) {
      for (final child in element.children) {
        _appendElement(child, blocks);
      }
    } else {
      final text = _cleanText(element.text);
      if (text.isNotEmpty) blocks.add(WeiboArticleBlock.text(text));
    }
  }

  static void _appendImages(
    dom.Element container,
    List<WeiboArticleBlock> blocks, {
    required bool includeText,
  }) {
    if (includeText) {
      final text = _cleanText(container.text);
      if (text.isNotEmpty) blocks.add(WeiboArticleBlock.text(text));
    }
    final caption =
        _cleanText(container.querySelector('figcaption')?.text ?? '');
    for (final image in container.querySelectorAll('img')) {
      _appendImage(image, blocks, caption: caption.isNotEmpty ? caption : null);
    }
  }

  static void _appendImage(
    dom.Element image,
    List<WeiboArticleBlock> blocks, {
    String? caption,
  }) {
    final url = _imageUrl(image);
    if (url == null) return;
    final aspect = double.tryParse(image.attributes['aspect'] ?? '') ?? 1.5;
    blocks.add(
      WeiboArticleBlock.image(
        url,
        caption: caption,
        aspectRatio:
            aspect.isFinite && aspect > 0.15 && aspect < 8 ? aspect : 1.5,
      ),
    );
  }

  static List<WeiboArticleInline> _extractInlines(dom.Element element) {
    final inlines = <WeiboArticleInline>[];

    void appendText(String raw, String? url) {
      final text = raw.replaceAll(RegExp(r'\s+'), ' ');
      if (text.isEmpty) return;
      if (inlines.isNotEmpty && inlines.last.url == url) {
        final previous = inlines.removeLast();
        inlines.add(WeiboArticleInline('${previous.text}$text', url: url));
      } else {
        inlines.add(WeiboArticleInline(text, url: url));
      }
    }

    void walk(dom.Node node, String? activeUrl) {
      if (node is dom.Text) {
        appendText(node.data, activeUrl);
        return;
      }
      if (node is! dom.Element) return;

      final tag = (node.localName ?? '').toLowerCase();
      final nextUrl = tag == 'a'
          ? _resolveUrl(
                node.attributes['href'] ??
                    node.attributes['data-href'] ??
                    node.attributes['data-url'],
              ) ??
              activeUrl
          : activeUrl;
      if (tag == 'br') {
        appendText('\n', activeUrl);
        return;
      }
      for (final child in node.nodes) {
        walk(child, nextUrl);
      }
    }

    for (final child in element.nodes) {
      walk(child, null);
    }
    return List.unmodifiable(inlines);
  }

  static String? _imageUrl(dom.Element? image) {
    if (image == null) return null;
    final srcSet = image.attributes['srcset'];
    if (srcSet != null && srcSet.trim().isNotEmpty) {
      final candidates = <({String url, int width})>[];
      for (final item in srcSet.split(',')) {
        final parts = item.trim().split(RegExp(r'\s+'));
        if (parts.isEmpty) continue;
        final url = _resolveUrl(parts.first);
        if (url == null) continue;
        final width = parts.length > 1
            ? int.tryParse(
                    RegExp(r'(\d+)w').firstMatch(parts[1])?.group(1) ?? '') ??
                0
            : 0;
        candidates.add((url: url, width: width));
      }
      if (candidates.isNotEmpty) {
        // 1024px is a useful native-page upper bound. Prefer it when
        // available, otherwise fall back to the largest official candidate.
        final suitable =
            candidates.where((item) => item.width <= 1024 && item.width > 0);
        if (suitable.isNotEmpty) {
          return suitable.reduce((a, b) => a.width >= b.width ? a : b).url;
        }
        return candidates.reduce((a, b) => a.width >= b.width ? a : b).url;
      }
    }

    for (final key in const [
      'data-original',
      'data-src',
      'data-lazy-src',
      'src'
    ]) {
      final url = _resolveUrl(image.attributes[key]);
      if (url != null) return url;
    }
    return null;
  }

  static String? _resolveUrl(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty || value.startsWith('data:')) return null;
    final normalized = value.startsWith('//')
        ? 'https:$value'
        : value.startsWith('/')
            ? 'https://weibo.com$value'
            : value;
    final uri = Uri.tryParse(normalized);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri.scheme == 'http'
        ? uri.replace(scheme: 'https').toString()
        : normalized;
  }

  static String _cleanText(String value) {
    return value
        .replaceAll(RegExp(r'[\u200B\u200C\u200D\uFEFF]'), '')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();
  }
}

/// Native Flutter renderer for official Weibo long-form articles.
class WeiboArticlePage extends ConsumerStatefulWidget {
  final String articleId;
  final String? title;

  const WeiboArticlePage({
    super.key,
    required this.articleId,
    this.title,
  });

  @override
  ConsumerState<WeiboArticlePage> createState() => _WeiboArticlePageState();
}

class _WeiboArticlePageState extends ConsumerState<WeiboArticlePage> {
  WeiboArticleDocument? _document;
  bool _loading = true;

  String get _articleUrl =>
      'https://weibo.com/ttarticle/p/show?id=${Uri.encodeQueryComponent(widget.articleId)}';

  @override
  void initState() {
    super.initState();
    unawaited(_loadArticle());
  }

  Future<void> _loadArticle() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final htmlCandidates = await ref
          .read(weiboDioClientProvider)
          .getArticleHtmlCandidates(widget.articleId);
      WeiboArticleDocument? parsed;
      for (final html in htmlCandidates) {
        final candidate = WeiboArticleParser.parse(
          html,
          fallbackTitle: widget.title,
        );
        if (candidate.blocks.isNotEmpty) {
          parsed = candidate;
          break;
        }
      }
      if (parsed == null) {
        throw StateError('微博文章正文为空');
      }
      if (!mounted) return;
      setState(() {
        _document = parsed;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _openExternalBrowser() async {
    HapticFeedbackUtil.light();
    final launched = await launchUrl(
      Uri.parse(_articleUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      AppToast.show(context, '未找到可用的外部浏览器');
    }
  }

  void _openImage(int index) {
    final document = _document;
    if (document == null) return;
    final images = document.blocks
        .where((block) => block.type == WeiboArticleBlockType.image)
        .map(
          (block) => WeiboPicModel(
            pid: 'article-${widget.articleId}-${block.value.hashCode}',
            thumbnail: block.value,
            large: block.value,
            original: block.value,
            width: block.aspectRatio,
            height: 1,
          ),
        )
        .toList(growable: false);
    if (index < 0 || index >= images.length) return;
    Navigator.of(context).push(
      PhysicsSpringGalleryRoute(
        child: ImageGalleryPage(
          pics: images,
          initialIndex: index,
          statusId: 'article-${widget.articleId}',
          isDetail: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final document = _document;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const BackButtonIcon(),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('文章详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded),
            tooltip: '在外部浏览器打开',
            onPressed: _openExternalBrowser,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : document == null
              ? _buildErrorState(colorScheme)
              : RefreshIndicator(
                  onRefresh: () => HapticFeedbackUtil.refresh(_loadArticle),
                  child: SelectionArea(
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate(
                              _buildDocumentWidgets(document, colorScheme),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme) {
    return RefreshIndicator(
      onRefresh: () => HapticFeedbackUtil.refresh(_loadArticle),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 120),
        children: [
          Icon(Icons.article_outlined, size: 56, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            '文章加载失败',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '请检查网络或登录状态后重试',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _loadArticle,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新加载'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDocumentWidgets(
    WeiboArticleDocument document,
    ColorScheme colorScheme,
  ) {
    final widgets = <Widget>[];
    if (document.coverImage != null) {
      widgets.add(_buildArticleImage(document.coverImage!, -1, 1.78));
    }

    widgets.add(
      Text(
        document.title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
      ),
    );
    if (document.author.isNotEmpty || document.publishedAt.isNotEmpty) {
      widgets.add(const SizedBox(height: 14));
      widgets.add(
        Row(
          children: [
            if (document.author.isNotEmpty)
              AppAvatar(
                url: document.authorAvatar,
                size: 36,
                name: document.author,
              ),
            if (document.author.isNotEmpty) const SizedBox(width: 10),
            Expanded(
              child: Text(
                [document.author, document.publishedAt, document.readCount]
                    .where((value) => value.isNotEmpty)
                    .join('  '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    widgets.add(const SizedBox(height: 22));
    var imageIndex = 0;
    for (final block in document.blocks) {
      switch (block.type) {
        case WeiboArticleBlockType.heading:
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Text(
                block.value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
              ),
            ),
          );
        case WeiboArticleBlockType.text:
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _buildArticleText(block, colorScheme),
            ),
          );
        case WeiboArticleBlockType.image:
          widgets.add(
              _buildArticleImage(block.value, imageIndex, block.aspectRatio));
          if (block.caption != null) {
            widgets.add(
              Padding(
                padding: const EdgeInsets.only(top: 5, bottom: 12),
                child: Text(
                  block.caption!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            );
          }
          imageIndex++;
      }
    }
    return widgets;
  }

  Widget _buildArticleText(
    WeiboArticleBlock block,
    ColorScheme colorScheme,
  ) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontSize: 17,
          height: 1.75,
        );
    if (block.inlines.isEmpty) {
      return Text(block.value, style: style);
    }

    return Text.rich(
      TextSpan(
        children: block.inlines.map((inline) {
          final url = inline.url;
          return TextSpan(
            text: inline.text,
            style: url == null
                ? style
                : style?.copyWith(color: colorScheme.primary),
            recognizer: url == null
                ? null
                : (TapGestureRecognizer()
                  ..onTap = () => LinkRoutingService.openUrl(
                        context,
                        url,
                        title: inline.text.trim(),
                      )),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildArticleImage(String url, int index, double aspectRatio) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: index >= 0 ? () => _openImage(index) : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: ColoredBox(
              color:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              child: ExtendedImage.network(
                url,
                headers: ApiConstants.imageHeaders,
                fit: BoxFit.contain,
                cache: true,
                loadStateChanged: (state) {
                  if (state.extendedImageLoadState == LoadState.loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state.extendedImageLoadState == LoadState.failed) {
                    return Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: colorScheme.outline,
                        size: 36,
                      ),
                    );
                  }
                  return null;
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
