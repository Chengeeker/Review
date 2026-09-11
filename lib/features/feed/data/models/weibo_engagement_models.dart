import 'dart:convert';

/// Structured engagement cards embedded in a Weibo status.
///
/// These models intentionally keep the raw API adapter tolerant of the
/// different shapes returned by the desktop timeline and status-detail APIs.
/// A card is only created when the payload contains a strong poll/hot-topic
/// signal, so an ordinary hashtag or page_info card is not misclassified.

class WeiboPollOption {
  final String id;
  final String text;
  final int votes;
  final double? percent;

  const WeiboPollOption({
    required this.id,
    required this.text,
    this.votes = 0,
    this.percent,
  });

  factory WeiboPollOption.fromJson(Map<String, dynamic> json, int index) {
    final rawPercent = _numberFrom(json, const [
      'percent',
      'percentage',
      'vote_percent',
      'vote_percentage',
      'part_ratio',
    ]);
    final normalizedPercent = rawPercent == null
        ? null
        : (rawPercent <= 1 ? rawPercent * 100 : rawPercent).toDouble();
    return WeiboPollOption(
      id: _stringFrom(json, const ['id', 'option_id', 'oid', 'value']) ??
          '$index',
      text: _stringFrom(json, const [
            'text',
            'title',
            'name',
            'option',
            'option_text',
            'content',
          ]) ??
          '',
      votes: _intFrom(json, const [
            'votes',
            'vote_count',
            'count',
            'num',
            'total',
            'part_num',
          ]) ??
          0,
      percent: normalizedPercent,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'votes': votes,
        'percent': percent,
      };
}

class WeiboPollModel {
  final String id;
  final String title;
  final List<WeiboPollOption> options;
  final int participantCount;
  final String? endDescription;
  final String creatorName;
  final String? voteUrl;
  final bool hasVoted;
  final bool isMultiChoice;
  final bool isEnded;

  const WeiboPollModel({
    required this.id,
    required this.title,
    required this.options,
    this.participantCount = 0,
    this.endDescription,
    this.creatorName = '',
    this.voteUrl,
    this.hasVoted = false,
    this.isMultiChoice = false,
    this.isEnded = false,
  });

  /// Finds a poll in the status payload without mistaking video/article
  /// page_info for a poll. Weibo has used several names for this card over
  /// time, so the adapter checks all known containers and option-list keys.
  static WeiboPollModel? fromStatusJson(
    Map<String, dynamic> status, {
    String creatorName = '',
  }) {
    final candidates = <Map<String, dynamic>>[];
    final fallbackVoteUrl = _voteUrlFromStatus(status);

    void addCandidate(Object? value) {
      if (value is Map) candidates.add(Map<String, dynamic>.from(value));
    }

    for (final key in const [
      'vote_info',
      'voteInfo',
      'vote',
      'poll_info',
      'pollInfo',
      'poll',
    ]) {
      addCandidate(status[key]);
    }

    // Current public status responses store native polls at
    // url_objects[*].object.object.vote_object.
    final urlObjects = _listFromAny(status['url_objects']);
    if (urlObjects != null) {
      for (final raw in urlObjects) {
        if (raw is! Map) continue;
        final outer = Map<String, dynamic>.from(raw);
        final outerObject = outer['object'];
        final card = outerObject is Map
            ? Map<String, dynamic>.from(outerObject)
            : <String, dynamic>{};
        final innerObject = card['object'];
        final inner = innerObject is Map
            ? Map<String, dynamic>.from(innerObject)
            : <String, dynamic>{};
        final rawVote = inner['vote_object'];
        if (rawVote is Map) {
          final candidate = Map<String, dynamic>.from(rawVote);
          candidate['title'] ??= inner['content'] ??
              inner['display_name'] ??
              card['display_name'] ??
              outer['url_ori'];
          candidate['vote_url'] ??= inner['url'] ??
              inner['target_url'] ??
              card['target_url'] ??
              outer['target_url'];
          candidate['creator_name'] ??= inner['user_nick'];
          candidate['end_timestamp'] ??= inner['expire_date'];
          candidate['participant_count'] ??= inner['part_info'];
          candidate['is_multi_select'] ??= inner['is_multi_select'];
          candidates.add(candidate);
        }
      }
    }

    final pageInfo = status['page_info'];
    if (pageInfo is Map) {
      final page = Map<String, dynamic>.from(pageInfo);
      final type = (page['type'] ?? page['page_type'] ?? page['object_type'])
          ?.toString()
          .toLowerCase();
      for (final key in const [
        'vote_info',
        'voteInfo',
        'vote',
        'poll_info',
        'pollInfo',
        'poll',
      ]) {
        addCandidate(page[key]);
      }
      if (type != null && (type.contains('vote') || type.contains('poll'))) {
        addCandidate(page);
      }
    }

    // Status detail and some profile responses expose the native poll under
    // card_info.vote_object instead of url_objects.
    final cardInfo = status['card_info'];
    if (cardInfo is Map) {
      final card = Map<String, dynamic>.from(cardInfo);
      final rawVote = card['vote_object'];
      if (rawVote is Map) {
        final candidate = Map<String, dynamic>.from(rawVote);
        candidate['title'] ??= card['title'] ?? card['content'];
        candidate['vote_url'] ??= card['vote_url'] ?? card['url'];
        candidate['creator_name'] ??= card['user_nick'];
        candidate['expire_date'] ??= card['expire_date'];
        candidate['part_info'] ??= card['part_info'];
        candidate['is_multi_select'] ??= card['is_multi_select'];
        candidates.add(candidate);
      }
      addCandidate(card['poll']);
      addCandidate(card);
    }
    addCandidate(status['vote_object']);

    for (final candidate in candidates) {
      final optionList = _firstList(candidate, const [
        'options',
        'vote_options',
        'vote_option',
        'vote_option_list',
        'option_list',
        'vote_list',
        'items',
      ]);
      if (optionList == null || optionList.isEmpty) continue;

      final options = <WeiboPollOption>[];
      for (var i = 0; i < optionList.length; i++) {
        final raw = optionList[i];
        if (raw is Map) {
          final option = WeiboPollOption.fromJson(
            Map<String, dynamic>.from(raw),
            i,
          );
          if (option.text.trim().isNotEmpty) options.add(option);
        } else if (raw != null && raw.toString().trim().isNotEmpty) {
          options.add(WeiboPollOption(id: '$i', text: raw.toString().trim()));
        }
      }
      if (options.isEmpty) continue;

      final title = _stringFrom(candidate, const [
            'title',
            'vote_title',
            'subject',
            'question',
            'name',
            'content',
          ])?.trim() ??
          '';
      if (title.isEmpty) continue;

      final participantCount = _intFrom(candidate, const [
            'participant_count',
            'participants_count',
            'participate_count',
            'vote_count',
            'total_count',
            'join_num',
            'total_votes',
            'part_info',
          ]) ??
          0;
      final endTimestamp = _stringFrom(candidate, const [
        'end_timestamp',
        'end_at',
        'expire_time',
        'expire_date',
      ]);
      final endDescription = _stringFrom(candidate, const [
            'end_description',
            'end_time_desc',
            'end_time_text',
            'expire_desc',
            'endtime',
            'end_time',
          ]) ??
          _remainingDescription(endTimestamp);
      final ended = _boolFrom(candidate, const [
            'is_ended',
            'ended',
            'is_end',
          ]) ||
          _intFrom(candidate, const ['state']) == 0 ||
          (endTimestamp != null && _isPastTimestamp(endTimestamp));

      return WeiboPollModel(
        id: _stringFrom(candidate, const [
              'id',
              'vote_id',
              'poll_id',
            ]) ??
            _voteIdFromUrl(fallbackVoteUrl) ??
            status['id']?.toString() ??
            '',
        title: title,
        options: options,
        participantCount: participantCount,
        endDescription: endDescription,
        creatorName: _stringFrom(candidate, const [
              'creator_name',
              'create_user_name',
            ]) ??
            creatorName,
        voteUrl: _stringFrom(candidate, const [
              'vote_url',
              'voteUrl',
              'page_url',
              'url',
            ]) ??
            fallbackVoteUrl,
        hasVoted: _boolFrom(candidate, const [
              'has_voted',
              'voted',
              'is_voted',
              'parted',
            ]) ||
            (_intFrom(candidate, const ['parted']) ?? 0) > 0 ||
            options.any((option) => _selectedFrom(candidate, option.id)),
        isMultiChoice: _boolFrom(candidate, const [
          'is_multiple',
          'multiple',
          'multi_choice',
          'is_multi_select',
        ]),
        isEnded: ended,
      );
    }
    return null;
  }

  /// Parses the native vote_object returned by the official vote endpoints.
  /// This is also used for the response to setVote, which contains the fresh
  /// vote counts for the card after a successful submission.
  static WeiboPollModel? fromVoteObject(
    Map<String, dynamic> voteObject, {
    String creatorName = '',
    String? fallbackId,
    String? fallbackVoteUrl,
  }) {
    final optionList = _firstList(voteObject, const [
      'vote_list',
      'options',
      'vote_options',
      'vote_option',
      'vote_option_list',
      'option_list',
      'items',
    ]);
    if (optionList == null || optionList.isEmpty) return null;

    final options = <WeiboPollOption>[];
    for (var i = 0; i < optionList.length; i++) {
      final raw = optionList[i];
      if (raw is Map) {
        final option = WeiboPollOption.fromJson(
          Map<String, dynamic>.from(raw),
          i,
        );
        if (option.text.trim().isNotEmpty) options.add(option);
      } else if (raw != null && raw.toString().trim().isNotEmpty) {
        options.add(WeiboPollOption(id: '$i', text: raw.toString().trim()));
      }
    }
    if (options.isEmpty) return null;

    final title = _stringFrom(voteObject, const [
          'title',
          'vote_title',
          'subject',
          'question',
          'name',
          'content',
        ])?.trim() ??
        '';
    if (title.isEmpty) return null;

    final endTimestamp = _stringFrom(voteObject, const [
      'end_timestamp',
      'end_at',
      'expire_time',
      'expire_date',
    ]);
    final ended = _boolFrom(voteObject, const [
          'is_ended',
          'ended',
          'is_end',
        ]) ||
        _intFrom(voteObject, const ['state']) == 0 ||
        (endTimestamp != null && _isPastTimestamp(endTimestamp));

    return WeiboPollModel(
      id: _stringFrom(voteObject, const [
            'id',
            'vote_id',
            'poll_id',
          ]) ??
          fallbackId ??
          '',
      title: title,
      options: options,
      participantCount: _intFrom(voteObject, const [
            'participant_count',
            'participants_count',
            'participate_count',
            'vote_count',
            'total_count',
            'join_num',
            'total_votes',
            'part_info',
          ]) ??
          0,
      endDescription: _stringFrom(voteObject, const [
            'end_description',
            'end_time_desc',
            'end_time_text',
            'expire_desc',
            'endtime',
            'end_time',
          ]) ??
          _remainingDescription(endTimestamp),
      creatorName: _stringFrom(voteObject, const [
            'creator_name',
            'create_user_name',
            'user_nick',
          ]) ??
          creatorName,
      voteUrl: _stringFrom(voteObject, const [
            'vote_url',
            'voteUrl',
            'page_url',
            'target_url',
            'url',
          ]) ??
          fallbackVoteUrl,
      hasVoted: _boolFrom(voteObject, const [
            'has_voted',
            'voted',
            'is_voted',
            'parted',
          ]) ||
          (_intFrom(voteObject, const ['parted']) ?? 0) > 0 ||
          options.any((option) => _selectedFrom(voteObject, option.id)),
      isMultiChoice: _boolFrom(voteObject, const [
        'is_multiple',
        'multiple',
        'multi_choice',
        'is_multi_select',
      ]),
      isEnded: ended,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'options': options.map((item) => item.toJson()).toList(),
        'participant_count': participantCount,
        'end_description': endDescription,
        'creator_name': creatorName,
        'vote_url': voteUrl,
        'has_voted': hasVoted,
        'is_multi_choice': isMultiChoice,
        'is_ended': isEnded,
      };

  static String? _voteUrlFromStatus(Map<String, dynamic> status) {
    final raw = status['url_struct'];
    if (raw is! List) return null;
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      for (final value in [
        map['vote_url'],
        map['long_url'],
        map['ori_url'],
        map['url'],
      ]) {
        final url = value?.toString() ?? '';
        if (url.contains('vote.weibo.com') && url.contains('vote_id=')) {
          return url;
        }
      }
    }
    return null;
  }

  static String? _voteIdFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return RegExp(r'[?&]vote_id=([^&#]+)').firstMatch(url)?.group(1);
  }

  static bool _selectedFrom(
    Map<String, dynamic> candidate,
    String optionId,
  ) {
    final list = _firstList(candidate, const [
      'vote_list',
      'options',
      'vote_options',
    ]);
    if (list == null) return false;
    for (final raw in list) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final id = _stringFrom(map, const ['id', 'option_id', 'oid']) ?? '';
      if (id == optionId && _boolFrom(map, const ['selected', 'is_selected'])) {
        return true;
      }
    }
    return false;
  }

  static String? _remainingDescription(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return null;
    final raw = int.tryParse(timestamp);
    if (raw == null) return null;
    final milliseconds = raw < 100000000000 ? raw * 1000 : raw;
    final remaining = DateTime.fromMillisecondsSinceEpoch(milliseconds)
        .difference(DateTime.now());
    if (remaining.isNegative) return '已结束';
    if (remaining.inDays > 0) return '还有${remaining.inDays}天结束';
    if (remaining.inHours > 0) return '还有${remaining.inHours}小时结束';
    return '即将结束';
  }
}

class WeiboHotTopicModel {
  final String word;
  final int? discussionCount;
  final String? discussionDescription;
  final String? targetUrl;

  const WeiboHotTopicModel({
    required this.word,
    this.discussionCount,
    this.discussionDescription,
    this.targetUrl,
  });

  String get discussionText {
    if (discussionDescription != null &&
        discussionDescription!.trim().isNotEmpty) {
      return discussionDescription!.trim();
    }
    final count = discussionCount;
    return count == null ? '' : '$count新讨论';
  }

  /// Parses the embedded orange hot-topic card. A normal #topic# in text is
  /// deliberately not enough to create this model; the official payload must
  /// mark the URL/topic as hot or provide hot-discussion metadata.
  static WeiboHotTopicModel? fromStatusJson(Map<String, dynamic> status) {
    // The desktop timeline does not use one stable container for this card.
    // Depending on the feed and the account, the same metadata can be placed
    // in url_struct, url_objects, page_info, card_info, or a nested object.
    // Walk only known card containers so an ordinary hashtag or unrelated
    // media metadata cannot accidentally become a hot-search card.
    final candidateRoots = <Object?>[
      for (final key in const [
        'hot_topic',
        'hotTopic',
        'hot_topic_info',
        'hotTopicInfo',
        'topic_struct',
        'topicStruct',
        'darwin_tags',
        'hot_weibo_tags',
        'hot_search_topic',
        'url_struct',
        'url_objects',
        'page_info',
        'card_info',
      ])
        status[key],
    ];

    for (final root in candidateRoots) {
      for (final candidate in _walkCandidateMaps(root)) {
        if (!_hasHotSignal(candidate)) continue;
        final topic = _topicFromMap(candidate);
        if (topic != null) return topic;
      }
    }
    return null;
  }

  static const Set<String> _nestedCardKeys = {
    'object',
    'data',
    'payload',
    'result',
    'value',
    'info',
    'metadata',
    'card',
    'card_info',
    'page_info',
    'topic',
    'topic_info',
    'hot_topic',
    'hotTopic',
    'hot_topic_info',
    'hotTopicInfo',
    'hot_search_topic',
    'hot_weibo_tags',
    'darwin_tags',
    'items',
    'list',
  };

  static Iterable<Map<String, dynamic>> _walkCandidateMaps(
    Object? value, {
    int depth = 0,
  }) sync* {
    if (value == null || depth > 5) return;

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map || decoded is List) {
            yield* _walkCandidateMaps(decoded, depth: depth + 1);
          }
        } catch (_) {
          // Some desktop fields are truncated JSON strings. Ignore them.
        }
      }
      return;
    }

    if (value is List) {
      for (final item in value) {
        yield* _walkCandidateMaps(item, depth: depth + 1);
      }
      return;
    }

    if (value is! Map) return;
    final map = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is String) map[entry.key as String] = entry.value;
    }
    if (map.isEmpty) return;

    yield map;
    for (final entry in map.entries) {
      if (_nestedCardKeys.contains(entry.key)) {
        yield* _walkCandidateMaps(entry.value, depth: depth + 1);
      }
    }
  }

  static WeiboHotTopicModel? _topicFromMap(Map<String, dynamic> map) {
    var word = _stringFrom(map, const [
      'word',
      'topic_name',
      'topic_title',
      'hot_topic_name',
      'hot_search_topic_name',
      'name',
      'url_title',
      'title',
      'page_title',
      'display_title',
      'display_name',
    ]);
    if (word == null || word.trim().isEmpty) return null;
    word = word
        .replaceFirst(RegExp(r'^#'), '')
        .replaceFirst(RegExp(r'#$'), '')
        .trim();
    if (word.isEmpty || word == '热搜') return null;

    return WeiboHotTopicModel(
      word: word,
      discussionCount: _intFromNested(map, const [
        'discussion_count',
        'discuss_count',
        'discuss_num',
        'discussion_num',
        'new_discuss',
        'new_discuss_count',
        'new_discuss_num',
        'num',
      ]),
      discussionDescription: _stringFrom(map, const [
        'discussion_description',
        'discuss_desc',
        'desc',
        'description',
        'suffix',
        'right_desc',
      ]),
      targetUrl: _stringFrom(map, const [
        'long_url',
        'ori_url',
        'url',
        'target_url',
      ]),
    );
  }

  static int? _intFromNested(
    Map<String, dynamic> map,
    List<String> keys, {
    int depth = 0,
  }) {
    final direct = _intFrom(map, keys);
    if (direct != null || depth >= 4) return direct;

    for (final entry in map.entries) {
      if (!_nestedCardKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (value is Map) {
        final nested = <String, dynamic>{};
        for (final nestedEntry in value.entries) {
          if (nestedEntry.key is String) {
            nested[nestedEntry.key as String] = nestedEntry.value;
          }
        }
        final found = _intFromNested(nested, keys, depth: depth + 1);
        if (found != null) return found;
      } else if (value is List) {
        for (final item in value) {
          if (item is! Map) continue;
          final nested = <String, dynamic>{};
          for (final nestedEntry in item.entries) {
            if (nestedEntry.key is String) {
              nested[nestedEntry.key as String] = nestedEntry.value;
            }
          }
          final found = _intFromNested(nested, keys, depth: depth + 1);
          if (found != null) return found;
        }
      }
    }
    return null;
  }

  static bool _hasHotSignal(Map<String, dynamic> map) {
    for (final key in const [
      'is_hot',
      'is_hot_topic',
      'is_hot_search',
      'hot',
      'hot_search',
    ]) {
      if (_boolFrom(map, [key])) return true;
    }
    final serialized = map.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(' ')
        .toLowerCase();
    return serialized.contains('热搜') ||
        serialized.contains('hotsearch') ||
        serialized.contains('hot_search') ||
        serialized.contains('hot_weibo_tags') ||
        serialized.contains('is_hot_topic') ||
        serialized.contains('new_discuss') ||
        serialized.contains('discussion_count') ||
        serialized.contains('discussion_num') ||
        serialized.contains('discuss_num');
  }

  Map<String, dynamic> toJson() => {
        'word': word,
        'discussion_count': discussionCount,
        'discussion_description': discussionDescription,
        'target_url': targetUrl,
      };
}

List<dynamic>? _listFromAny(Object? value) {
  if (value is List) return value;
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) return decoded;
    } catch (_) {
      // Optional card JSON can be absent or truncated in desktop responses.
    }
  }
  return null;
}

List<dynamic>? _firstList(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is List) return value;
  }
  return null;
}

String? _stringFrom(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

num? _numberFrom(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value;
    final parsed = num.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return null;
}

int? _intFrom(Map<String, dynamic> map, List<String> keys) {
  final value = _numberFrom(map, keys);
  return value?.round();
}

bool _boolFrom(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == true || value == 1 || value == '1') return true;
    if (value is String && value.toLowerCase() == 'true') return true;
  }
  return false;
}

bool _isPastTimestamp(String value) {
  final number = int.tryParse(value);
  if (number == null) return false;
  final milliseconds = number < 100000000000 ? number * 1000 : number;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds)
      .isBefore(DateTime.now());
}
