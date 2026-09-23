import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/storage/storage_service.dart';

class MessageUnreadCounts {
  final int mentions;
  final int likes;
  final int comments;
  final int directMessages;

  const MessageUnreadCounts({
    required this.mentions,
    required this.likes,
    required this.comments,
    required this.directMessages,
  });

  int get total => mentions + likes + comments + directMessages;
}

/// Shared unread-count and mute-state rules for the drawer, message center,
/// and Android background notification worker.
class MessageUnreadService {
  MessageUnreadService(this.storage);

  final StorageService storage;

  static const _reminderUrl = 'https://weibo.com/ajax/remind/unread';
  static const _contactsUrl =
      'https://api.weibo.com/webim/2/direct_messages/contacts.json';

  static int readCount(dynamic value) {
    if (value is int) return value < 0 ? 0 : value;
    if (value is num) return value.toInt().clamp(0, 0x7fffffff);
    if (value is String) return int.tryParse(value)?.clamp(0, 0x7fffffff) ?? 0;
    if (value is Map) {
      for (final key in const ['unread_count', 'count', 'unread', 'num']) {
        final parsed = readCount(value[key]);
        if (parsed > 0) return parsed;
      }
    }
    return 0;
  }

  static bool isGroupContact(Map<String, dynamic> contact) {
    final user = _asMap(contact['user']);
    final id = (user?['id'] ??
            user?['idstr'] ??
            contact['id'] ??
            contact['user_id'] ??
            '')
        .toString();
    final name = (user?['name'] ?? user?['screen_name'] ?? '').toString();
    final flag = contact['is_group'] ?? contact['isGroup'];
    return flag == true ||
        flag == 1 ||
        flag == '1' ||
        id.length > 12 ||
        name.contains('群') ||
        name.contains('交流');
  }

  static String contactId(Map<String, dynamic> contact) {
    final user = _asMap(contact['user']);
    return (user?['id'] ??
            user?['idstr'] ??
            contact['id'] ??
            contact['user_id'] ??
            '')
        .toString();
  }

  Future<MessageUnreadCounts?> fetchCounts(Dio dio) async {
    Response<dynamic>? reminderResponse;
    Response<dynamic>? contactsResponse;
    await Future.wait([
      dio.get<dynamic>(_reminderUrl).then((value) {
        reminderResponse = value;
      }).catchError((_) {}),
      dio.get<dynamic>(_contactsUrl).then((value) {
        contactsResponse = value;
      }).catchError((_) {}),
    ]);

    if (reminderResponse == null || contactsResponse == null) return null;
    final reminder = _asMap(reminderResponse!.data);
    final contactsData = _asMap(contactsResponse!.data);
    if (reminder == null || contactsData == null) return null;

    final rawMentionStatus = _findCount(reminder, const [
      'mention_status',
      'mentionStatus',
    ]);
    final rawMentionComments = _findCount(reminder, const [
      'mention_cmt',
      'mention_comment',
      'mentionComment',
    ]);
    final rawMentions = rawMentionStatus != null || rawMentionComments != null
        ? (rawMentionStatus ?? 0) + (rawMentionComments ?? 0)
        : _findCount(reminder, const ['mention', 'mentions', 'at_me']) ?? 0;
    final rawLikes = _findCount(
            reminder, const ['like', 'likes', 'attitude', 'attitudes']) ??
        0;
    final rawComments =
        _findCount(reminder, const ['cmt', 'comment', 'comments']) ?? 0;

    final rawContacts = _readContacts(contactsData);
    final effectiveContacts = await applyContactUnreadBaselines(rawContacts);
    var rawDirectMessages = 0;
    for (final contact in effectiveContacts) {
      if (storage.isMessageGroupMuted(contactId(contact))) continue;
      rawDirectMessages += readCount(contact['unread_count']);
    }

    final effective = await _applyCategoryBaselines({
      'mentions': rawMentions,
      'likes': rawLikes,
      'comments': rawComments,
      'directMessages': rawDirectMessages,
    });
    return MessageUnreadCounts(
      mentions: effective['mentions'] ?? 0,
      likes: effective['likes'] ?? 0,
      comments: effective['comments'] ?? 0,
      directMessages: effective['directMessages'] ?? 0,
    );
  }

  Future<List<Map<String, dynamic>>> applyContactUnreadBaselines(
    List<Map<String, dynamic>> contacts,
  ) async {
    final baselines =
        _readIntMap(StorageService.keyMessageContactUnreadBaselines);
    var changed = false;
    final output = <Map<String, dynamic>>[];

    for (final original in contacts) {
      final contact = Map<String, dynamic>.from(original);
      final raw = readCount(
        contact['_review_raw_unread_count'] ?? contact['unread_count'],
      );
      contact['_review_raw_unread_count'] = raw;
      final id = contactId(contact);
      final baseline = id.isEmpty ? 0 : baselines[id] ?? 0;
      if (raw < baseline && id.isNotEmpty) {
        baselines.remove(id);
        changed = true;
        contact['unread_count'] = raw;
      } else {
        contact['unread_count'] = (raw - baseline).clamp(0, raw);
      }
      output.add(contact);
    }
    if (changed) {
      await _writeIntMap(
          StorageService.keyMessageContactUnreadBaselines, baselines);
    }
    return output;
  }

  /// Persist server counters as a local baseline before attempting remote
  /// clear endpoints, so a subsequent contacts refresh cannot resurrect old
  /// unread badges when Weibo's clear endpoint is eventually consistent.
  Future<void> markCurrentAsRead(
    Dio dio,
    List<Map<String, dynamic>> contacts,
  ) async {
    final contactBaselines =
        _readIntMap(StorageService.keyMessageContactUnreadBaselines);
    var rawDirectMessages = 0;
    for (final contact in contacts) {
      final id = contactId(contact);
      if (id.isEmpty) continue;
      final raw = readCount(
        contact['_review_raw_unread_count'] ?? contact['unread_count'],
      );
      contactBaselines[id] = raw;
      if (!storage.isMessageGroupMuted(id)) rawDirectMessages += raw;
    }
    await _writeIntMap(
      StorageService.keyMessageContactUnreadBaselines,
      contactBaselines,
    );
    final lastCounts =
        _readIntMap(StorageService.keyMessageNotificationLastCounts)
          ..['directMessages'] = rawDirectMessages;
    await _writeIntMap(
        StorageService.keyMessageNotificationLastCounts, lastCounts);

    final reminder = await _fetchReminder(dio);
    if (reminder == null) return;
    final baseline = _readIntMap(StorageService.keyMessageUnreadBaselines);
    final updatedLastCounts =
        _readIntMap(StorageService.keyMessageNotificationLastCounts);
    for (final entry in _readNotificationCounts(reminder).entries) {
      baseline[entry.key] = entry.value;
      updatedLastCounts[entry.key] = entry.value;
    }
    await _writeIntMap(StorageService.keyMessageUnreadBaselines, baseline);
    await _writeIntMap(
      StorageService.keyMessageNotificationLastCounts,
      updatedLastCounts,
    );
  }

  /// Marks one notification category as locally read when the user opens it.
  /// The unread endpoint is sampled at entry time so older notifications do
  /// not remain in the drawer badge or get re-notified by the background poller.
  Future<bool> markCategoryAsRead(Dio dio, String category) async {
    if (!const {'mentions', 'likes', 'comments'}.contains(category)) {
      return false;
    }
    final reminder = await _fetchReminder(dio);
    if (reminder == null) return false;
    final count = _readNotificationCounts(reminder)[category];
    if (count == null) return false;

    final baselines = _readIntMap(StorageService.keyMessageUnreadBaselines)
      ..[category] = count;
    final lastCounts =
        _readIntMap(StorageService.keyMessageNotificationLastCounts)
          ..[category] = count;
    await _writeIntMap(StorageService.keyMessageUnreadBaselines, baselines);
    await _writeIntMap(
      StorageService.keyMessageNotificationLastCounts,
      lastCounts,
    );
    return true;
  }

  /// Marks only the tapped conversation as read locally. The unread baseline
  /// stores the server's raw count, while the background notification
  /// watermark remains the raw aggregate expected by its native poller.
  Future<void> markContactAsRead(
    String id,
    List<Map<String, dynamic>> contacts,
  ) async {
    if (id.isEmpty) return;
    final contact = contacts.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item != null && contactId(item) == id,
          orElse: () => null,
        );
    if (contact == null) return;

    final raw = readCount(
      contact['_review_raw_unread_count'] ?? contact['unread_count'],
    );
    final baselines =
        _readIntMap(StorageService.keyMessageContactUnreadBaselines)
          ..[id] = raw;
    await _writeIntMap(
      StorageService.keyMessageContactUnreadBaselines,
      baselines,
    );

    var rawDirectMessages = 0;
    for (final item in contacts) {
      final contactIdValue = contactId(item);
      if (contactIdValue.isEmpty ||
          storage.isMessageGroupMuted(contactIdValue)) {
        continue;
      }
      rawDirectMessages += readCount(
        item['_review_raw_unread_count'] ?? item['unread_count'],
      );
    }
    final lastCounts =
        _readIntMap(StorageService.keyMessageNotificationLastCounts)
          ..['directMessages'] = rawDirectMessages;
    await _writeIntMap(
      StorageService.keyMessageNotificationLastCounts,
      lastCounts,
    );
  }

  Map<String, int> _readNotificationCounts(Map<String, dynamic> reminder) {
    final status =
        _findCount(reminder, const ['mention_status', 'mentionStatus']);
    final mentionComments = _findCount(reminder, const [
      'mention_cmt',
      'mention_comment',
      'mentionComment',
    ]);
    final mentions = status != null || mentionComments != null
        ? (status ?? 0) + (mentionComments ?? 0)
        : _findCount(reminder, const ['mention', 'mentions', 'at_me']);
    final likes = _findCount(reminder, const [
      'like',
      'likes',
      'attitude',
      'attitudes',
    ]);
    final comments = _findCount(reminder, const ['cmt', 'comment', 'comments']);
    return {
      if (mentions != null) 'mentions': mentions,
      if (likes != null) 'likes': likes,
      if (comments != null) 'comments': comments,
    };
  }

  Future<Map<String, int>> _applyCategoryBaselines(
    Map<String, int> rawCounts,
  ) async {
    final baselines = _readIntMap(StorageService.keyMessageUnreadBaselines);
    var changed = false;
    final effective = <String, int>{};
    for (final entry in rawCounts.entries) {
      final baseline = baselines[entry.key] ?? 0;
      if (entry.value < baseline) {
        baselines.remove(entry.key);
        changed = true;
        effective[entry.key] = entry.value;
      } else {
        effective[entry.key] = entry.value - baseline;
      }
    }
    if (changed) {
      await _writeIntMap(StorageService.keyMessageUnreadBaselines, baselines);
    }
    return effective;
  }

  Future<Map<String, dynamic>?> _fetchReminder(Dio dio) async {
    try {
      final response = await dio.get<dynamic>(_reminderUrl);
      return _asMap(response.data);
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>> _readContacts(Map<String, dynamic> data) {
    final raw = data['contacts'] ?? _asMap(data['data'])?['contacts'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static int? _findCount(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (data.containsKey(key)) {
        final value = _optionalCount(data[key]);
        if (value != null) return value;
      }
    }
    for (final value in data.values) {
      final nested = _asMap(value);
      if (nested != null) {
        final count = _findCount(nested, keys);
        if (count != null) return count;
      }
    }
    return null;
  }

  static int? _optionalCount(dynamic value) {
    if (value is int) return value.clamp(0, 0x7fffffff);
    if (value is num) return value.toInt().clamp(0, 0x7fffffff);
    if (value is String) return int.tryParse(value)?.clamp(0, 0x7fffffff);
    if (value is Map) {
      for (final key in const ['unread_count', 'count', 'unread', 'num']) {
        final count = _optionalCount(value[key]);
        if (count != null) return count;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  Map<String, int> _readIntMap(String key) {
    final raw = storage.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded
          .map((key, value) => MapEntry(key.toString(), readCount(value)));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeIntMap(String key, Map<String, int> values) =>
      storage.setString(key, jsonEncode(values));
}
