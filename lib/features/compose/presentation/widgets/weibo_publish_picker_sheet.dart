import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/widgets/app_avatar.dart';
import '../../../feed/data/models/weibo_status_model.dart';
import '../../../search/data/search_repository.dart';

enum WeiboPublishPickerMode {
  topic,
  superTopic,
  mention,
  place,
  review,
  column
}

class WeiboPublishPickerSelection {
  final String text;
  final String? userId;
  final String? topicId;
  final SearchPlaceItem? place;
  final WeiboMovieItem? movie;
  final WeiboMonographItem? monograph;

  const WeiboPublishPickerSelection({
    required this.text,
    this.userId,
    this.topicId,
    this.place,
    this.movie,
    this.monograph,
  });
}

/// 应用内复刻微博网页发布器的搜索型选择器。
///
/// 选择结果只来自微博接口，不在本地伪造用户、话题或地点数据。
class WeiboPublishPickerSheet extends StatefulWidget {
  final WeiboPublishPickerMode mode;
  final SearchRepository repository;
  final String initialQuery;
  final double? latitude;
  final double? longitude;

  const WeiboPublishPickerSheet({
    super.key,
    required this.mode,
    required this.repository,
    this.initialQuery = '',
    this.latitude,
    this.longitude,
  });

  @override
  State<WeiboPublishPickerSheet> createState() =>
      _WeiboPublishPickerSheetState();
}

class _WeiboPublishPickerSheetState extends State<WeiboPublishPickerSheet> {
  late final TextEditingController _controller;
  Timer? _debounce;
  List<WeiboTopicSuggestion> _topics = const [];
  List<SearchChaohuaItem> _superTopics = const [];
  List<WeiboUserModel> _users = const [];
  List<SearchPlaceItem> _places = const [];
  List<WeiboMovieItem> _movies = const [];
  List<WeiboMonographItem> _monographs = const [];
  bool _loading = false;
  String? _error;

  bool get _isTopic => widget.mode == WeiboPublishPickerMode.topic;
  bool get _isSuperTopic => widget.mode == WeiboPublishPickerMode.superTopic;
  bool get _isMention => widget.mode == WeiboPublishPickerMode.mention;
  bool get _isReview => widget.mode == WeiboPublishPickerMode.review;
  bool get _isColumn => widget.mode == WeiboPublishPickerMode.column;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    if (widget.initialQuery.trim().isNotEmpty ||
        widget.mode == WeiboPublishPickerMode.place ||
        _isColumn ||
        _isReview) {
      _search(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String get _title {
    if (_isMention) return '@提到某人';
    if (_isSuperTopic) return '选择超话';
    if (_isReview) return '点评';
    if (_isColumn) return '选择专栏';
    if (widget.mode == WeiboPublishPickerMode.place) return '选择地点';
    return '选择话题';
  }

  String get _hint {
    if (_isMention) return '搜索微博好友或其他用户';
    if (_isReview) return '搜索电影';
    if (_isColumn) return '专栏列表';
    if (widget.mode == WeiboPublishPickerMode.place) return '搜索附近地点';
    return '搜索话题、电影、书、歌曲、地点、股票';
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(value));
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    if (query.isEmpty &&
        widget.mode != WeiboPublishPickerMode.place &&
        !_isColumn &&
        !_isReview) {
      if (mounted) {
        setState(() {
          _topics = const [];
          _superTopics = const [];
          _users = const [];
          _places = const [];
          _error = null;
          _loading = false;
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isMention) {
        final result = await widget.repository.getSearchSuggestions(query);
        if (!mounted) return;
        setState(() {
          _users = result.users;
          _loading = false;
        });
      } else if (_isReview) {
        final result = await widget.repository.searchMovies(query);
        if (!mounted) return;
        setState(() {
          _movies = result;
          _loading = false;
        });
      } else if (_isSuperTopic) {
        final result = await widget.repository.searchChaohua(query);
        if (!mounted) return;
        setState(() {
          _superTopics = result;
          _loading = false;
        });
      } else if (_isColumn) {
        final result = await widget.repository.getMonographs();
        if (!mounted) return;
        setState(() {
          _monographs = result;
          _loading = false;
        });
      } else if (widget.mode == WeiboPublishPickerMode.place) {
        final result = await widget.repository.searchPlaces(
          query,
          latitude: widget.latitude,
          longitude: widget.longitude,
        );
        if (!mounted) return;
        setState(() {
          _places = result;
          _loading = false;
        });
      } else {
        final result = await widget.repository.getTopicSuggestions(query);
        if (!mounted) return;
        setState(() {
          _topics = result;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '微博服务器暂时没有返回搜索结果，请稍后重试';
      });
    }
  }

  void _select(WeiboPublishPickerSelection selection) {
    Navigator.of(context).pop(selection);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                Text(_title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: _hint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _controller.clear();
                          _onQueryChanged('');
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _buildResults(colorScheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ColorScheme colorScheme) {
    if (_isMention) {
      if (_users.isEmpty) return _empty('输入昵称搜索微博用户');
      return ListView.separated(
        itemCount: _users.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final user = _users[index];
          return ListTile(
            leading: AppAvatar(
              url: user.avatar,
              size: 42,
              name: user.screenName,
              verified: user.verified,
              verifiedType: user.verifiedType,
            ),
            title: Text(user.screenName),
            subtitle: Text(
              user.description.isNotEmpty ? user.description : '微博用户',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _select(
              WeiboPublishPickerSelection(
                  text: '@${user.screenName} ', userId: user.id),
            ),
          );
        },
      );
    }

    if (_isReview) {
      if (_movies.isEmpty) return _empty('输入电影名称搜索点评对象');
      return ListView.separated(
        itemCount: _movies.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _movies[index];
          return ListTile(
            leading: AppAvatar(url: item.poster, size: 44, name: item.title),
            title: Text(item.title),
            subtitle: Text(item.description,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Text('点评'),
            onTap: () => _select(
                WeiboPublishPickerSelection(text: item.title, movie: item)),
          );
        },
      );
    }

    if (_isSuperTopic) {
      if (_superTopics.isEmpty) return _empty('输入关键词搜索超话');
      return ListView.separated(
        itemCount: _superTopics.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _superTopics[index];
          return ListTile(
            leading: AppAvatar(url: item.image, size: 44, name: item.title),
            title: Text(item.title),
            subtitle: Text(item.description.isEmpty ? '超话' : item.description,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Text('超话'),
            onTap: () => _select(
              WeiboPublishPickerSelection(
                text: '#${item.title}[超话]# ',
                topicId: item.topicId,
              ),
            ),
          );
        },
      );
    }

    if (_isColumn) {
      if (_monographs.isEmpty) return _empty('当前账号没有可用专栏');
      return ListView.separated(
        itemCount: _monographs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _monographs[index];
          return ListTile(
            leading: AppAvatar(url: item.cover, size: 44, name: item.title),
            title: Text(item.title),
            subtitle: Text(item.summary,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Text('专栏'),
            onTap: () => _select(
                WeiboPublishPickerSelection(text: item.title, monograph: item)),
          );
        },
      );
    }

    if (widget.mode == WeiboPublishPickerMode.place) {
      if (_places.isEmpty) return _empty('输入地点名称搜索微博地点');
      return ListView.separated(
        itemCount: _places.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final place = _places[index];
          return ListTile(
            leading:
                Icon(Icons.location_on_outlined, color: colorScheme.primary),
            title: Text(place.title),
            subtitle: Text(
              _placeSubtitle(place),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _select(
              WeiboPublishPickerSelection(text: place.title, place: place),
            ),
          );
        },
      );
    }

    if (_topics.isEmpty) return _empty('输入关键词搜索微博话题');
    return ListView.separated(
      itemCount: _topics.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _topics[index];
        return ListTile(
          leading: Icon(
              item.isSuperTopic ? Icons.diamond_outlined : Icons.tag_rounded,
              color: colorScheme.primary),
          title: Text(item.word),
          subtitle: item.discussionCount > 0
              ? Text('讨论 ${item.discussionCount}')
              : null,
          trailing: Text(item.isSuperTopic ? '超话' : '话题'),
          onTap: () => _select(
            WeiboPublishPickerSelection(
              text:
                  item.isSuperTopic ? '#${item.word}[超话]# ' : '#${item.word}# ',
              topicId: item.isSuperTopic ? item.topicId : null,
            ),
          ),
        );
      },
    );
  }

  String _placeSubtitle(SearchPlaceItem place) {
    final distance = place.distanceMeters;
    if (distance != null && distance.isFinite) {
      final label = distance < 1000
          ? '距你 ${distance.round()} 米'
          : '距你 ${(distance / 1000).toStringAsFixed(1)} 公里';
      final detail =
          place.clientShow.isEmpty ? place.pcTitle : place.clientShow;
      return detail.isEmpty ? label : '$label · $detail';
    }
    return place.clientShow.isEmpty ? place.pcTitle : place.clientShow;
  }

  Widget _empty(String message) => Center(
        child: Text(message,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}
