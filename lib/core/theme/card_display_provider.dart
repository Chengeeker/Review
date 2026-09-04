import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/storage_service.dart';
import '../utils/weibo_time_formatter.dart';

/// Card Display Settings Provider & Notifier
class CardDisplayNotifier extends StateNotifier<CardDisplaySettings> {
  final StorageService _storage;

  CardDisplayNotifier(this._storage)
      : super(CardDisplaySettings(
          timeDisplayMode: _storage.getTimeDisplayMode(),
          showWeekday: _storage.getShowWeekday(),
          showYear: _storage.getShowYear(),
          showTimezone: _storage.getShowTimezone(),
          showSeconds: _storage.getShowSeconds(),
          showSource: _storage.getShowSource(),
          showRegion: _storage.getShowRegion(),
        ));

  Future<void> setTimeDisplayMode(String mode) async {
    await _storage.setTimeDisplayMode(mode);
    state = state.copyWith(timeDisplayMode: mode);
  }

  Future<void> setShowWeekday(bool val) async {
    await _storage.setShowWeekday(val);
    state = state.copyWith(showWeekday: val);
  }

  Future<void> setShowYear(bool val) async {
    await _storage.setShowYear(val);
    state = state.copyWith(showYear: val);
  }

  Future<void> setShowTimezone(bool val) async {
    await _storage.setShowTimezone(val);
    state = state.copyWith(showTimezone: val);
  }

  Future<void> setShowSeconds(bool val) async {
    await _storage.setShowSeconds(val);
    state = state.copyWith(showSeconds: val);
  }

  Future<void> setShowSource(bool val) async {
    await _storage.setShowSource(val);
    state = state.copyWith(showSource: val);
  }

  Future<void> setShowRegion(bool val) async {
    await _storage.setShowRegion(val);
    state = state.copyWith(showRegion: val);
  }
}

final cardDisplayProvider =
    StateNotifierProvider<CardDisplayNotifier, CardDisplaySettings>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return CardDisplayNotifier(storage);
});
