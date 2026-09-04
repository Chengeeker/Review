import 'package:extended_image/extended_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../constants/api_constants.dart';
import '../services/link_routing_service.dart';
import '../theme/app_theme.dart';
import '../../features/drawer_features/presentation/chaohua_detail_page.dart';
import '../../features/profile/presentation/user_profile_page.dart';
import '../../features/search/presentation/search_results_page.dart';
import 'weibo_emojis.dart';

/// Weibo Rich Text Parser
/// Highlights @Users, #Topics# (with smart Super Topic routing), http(s) Links, and renders authentic [Emotions].
class WeiboTextParser {
  WeiboTextParser._();

  static final RegExp _weiboRegex = RegExp(
    r'(@[\w\u4e00-\u9fa5-]+)|(#([^#]+)#)|(https?:\/\/[^\s]+)|(\[[a-zA-Z0-9\u4e00-\u9fa5]+\])',
  );

  static List<InlineSpan> parse({
    required String rawText,
    required BuildContext context,
    TextStyle? defaultStyle,
    Color? linkColor,
    List<Map<String, dynamic>>? urlStruct,
    Function(String user)? onUserTap,
    Function(String topic)? onTopicTap,
  }) {
    final theme = Theme.of(context);
    final primary = linkColor ?? theme.colorScheme.primary;
    final baseStyle = defaultStyle?.copyWith(letterSpacing: 0.0) ??
        theme.textTheme.bodyMedium?.copyWith(
          fontSize: 15,
          color: theme.colorScheme.onSurface,
          height: 1.45,
          letterSpacing: 0.0,
        ) ??
        TextStyle(
          fontSize: 15,
          color: theme.colorScheme.onSurface,
          height: 1.45,
          letterSpacing: 0.0,
        );
    final highlightStyle = baseStyle.copyWith(
      color: primary,
      fontWeight: context.adjustWeight(FontWeight.w600),
      letterSpacing: 0.0,
    );

    // Clean up HTML tags while preserving image emojis (e.g. <img alt="[doge]" ...>)
    String cleanText = rawText
        .replaceAllMapped(
          RegExp(r'<img[^>]*?(?:alt|title)="(\[[^"]+\])"[^>]*?>', caseSensitive: false),
          (m) => m.group(1) ?? '',
        )
        .replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '');

    final spans = <InlineSpan>[];
    int lastMatchEnd = 0;

    for (final match in _weiboRegex.allMatches(cleanText)) {
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: cleanText.substring(lastMatchEnd, match.start),
            style: baseStyle,
          ),
        );
      }

      final matchedText = match.group(0)!;

      if (matchedText.startsWith('@')) {
        // @User -> Direct to UserProfilePage
        final username = matchedText.substring(1);
        spans.add(
          TextSpan(
            text: matchedText,
            style: highlightStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                if (onUserTap != null) {
                  onUserTap(username);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => UserProfilePage(
                        screenName: username,
                      ),
                    ),
                  );
                }
              },
          ),
        );
      } else if (matchedText.startsWith('#') && matchedText.endsWith('#')) {
        // #Topic# -> Smart routing (Super Topic -> ChaohuaDetailPage, Normal Topic -> SearchResultsPage)
        final topic = match.group(3) ?? matchedText.replaceAll('#', '');
        final cleanTopic = topic.replaceAll('[超话]', '').replaceAll('超话', '').trim();

        Map<String, dynamic>? chaohuaStruct;
        if (urlStruct != null) {
          for (final u in urlStruct) {
            final sUrl = u['short_url']?.toString() ?? '';
            final uTitle = u['url_title']?.toString() ?? '';
            final pageId = u['page_id']?.toString() ?? '';
            final oriUrl = u['ori_url']?.toString() ?? '';
            if (sUrl == matchedText || uTitle.contains(cleanTopic) || oriUrl.contains(cleanTopic)) {
              if (pageId.startsWith('100808') ||
                  oriUrl.contains('containerid=100808') ||
                  u['url_type_pic']?.toString().contains('super') == true) {
                chaohuaStruct = u;
                break;
              }
            }
          }
        }

        final isChaohua = topic.contains('超话') || chaohuaStruct != null;

        spans.add(
          TextSpan(
            text: matchedText,
            style: highlightStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                if (isChaohua) {
                  String containerId = chaohuaStruct?['page_id']?.toString() ?? '';
                  if (containerId.isEmpty && chaohuaStruct?['ori_url'] != null) {
                    final m = RegExp(r'containerid=([^&]+)').firstMatch(chaohuaStruct!['ori_url']!.toString());
                    if (m != null) containerId = m.group(1) ?? '';
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => ChaohuaDetailPage(
                        containerid: containerId,
                        title: cleanTopic,
                      ),
                    ),
                  );
                } else if (onTopicTap != null) {
                  onTopicTap(topic);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => SearchResultsPage(keyword: topic),
                    ),
                  );
                }
              },
          ),
        );
      } else if (matchedText.startsWith('http://') || matchedText.startsWith('https://')) {
        // Web Link / Smart Card Link (e.g. 微博智搜, 专题, 网页链接, 超话直达)
        String linkTitle = '网页链接';
        String targetUrl = matchedText;
        Map<String, dynamic>? matchingStruct;

        if (urlStruct != null) {
          for (final u in urlStruct) {
            final shortUrl = u['short_url']?.toString();
            final oriUrl = u['ori_url']?.toString();
            final longUrl = u['long_url']?.toString();
            final title = u['url_title']?.toString();

            if (matchedText == shortUrl || matchedText == oriUrl || matchedText == longUrl) {
              matchingStruct = u;
              if (title != null && title.trim().isNotEmpty) {
                linkTitle = title.trim();
              }
              targetUrl = longUrl ?? oriUrl ?? shortUrl ?? matchedText;
              break;
            }
          }
        }

        final pageId = matchingStruct?['page_id']?.toString() ?? '';
        final oriUrl = matchingStruct?['ori_url']?.toString() ?? '';
        final isChaohuaLink = pageId.startsWith('100808') || oriUrl.contains('containerid=100808');

        spans.add(
          TextSpan(
            text: isChaohuaLink ? ' 💎 $linkTitle' : ' 🔗 $linkTitle',
            style: highlightStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () async {
                if (isChaohuaLink) {
                  String containerId = pageId;
                  if (containerId.isEmpty) {
                    final m = RegExp(r'containerid=([^&]+)').firstMatch(oriUrl);
                    if (m != null) containerId = m.group(1) ?? '';
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => ChaohuaDetailPage(
                        containerid: containerId,
                        title: linkTitle.replaceAll('超话', '').trim(),
                      ),
                    ),
                  );
                } else {
                  LinkRoutingService.openUrl(context, targetUrl, title: linkTitle);
                }
              },
          ),
        );
      } else if (matchedText.startsWith('[') && matchedText.endsWith(']')) {
        // Weibo Emotion / Emoji Rendering (Official CDN Image + Unicode fallback)
        final emojiUrl = WeiboEmojis.getEmojiUrl(matchedText);
        final emojiChar = WeiboEmojis.getEmoji(matchedText);

        if (emojiUrl != null && emojiUrl.isNotEmpty) {
          final emojiSize = (baseStyle.fontSize ?? 15) * 1.25;
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.0),
                child: ExtendedImage.network(
                  emojiUrl,
                  width: emojiSize,
                  height: emojiSize,
                  fit: BoxFit.contain,
                  cache: true,
                  headers: ApiConstants.imageHeaders,
                  loadStateChanged: (state) {
                    if (state.extendedImageLoadState == LoadState.failed) {
                      if (emojiChar != null) {
                        return Text(emojiChar, style: baseStyle);
                      }
                      return Text(matchedText, style: baseStyle);
                    }
                    return null;
                  },
                ),
              ),
            ),
          );
        } else if (emojiChar != null) {
          spans.add(
            TextSpan(
              text: emojiChar,
              style: baseStyle.copyWith(
                fontSize: (baseStyle.fontSize ?? 15) * 1.15,
              ),
            ),
          );
        } else {
          spans.add(
            TextSpan(
              text: matchedText,
              style: baseStyle,
            ),
          );
        }
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < cleanText.length) {
      spans.add(
        TextSpan(
          text: cleanText.substring(lastMatchEnd),
          style: baseStyle,
        ),
      );
    }

    return spans;
  }
}
