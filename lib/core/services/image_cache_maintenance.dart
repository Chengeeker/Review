import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Keeps only bounded, reproducible ExtendedImage disk cache files.
class ImageCacheMaintenance {
  ImageCacheMaintenance._();

  static const int maxCacheBytes = 512 * 1024 * 1024;
  static const int defaultAutoClearThresholdMb = 200;
  static const List<int> autoClearThresholdOptions = [
    0,
    50,
    100,
    200,
    500,
    1024,
    2048,
  ];
  static const Duration maxCacheAge = Duration(days: 60);
  static const Duration minEvictionAge = Duration(minutes: 1);
  static final RegExp _cacheFileName = RegExp(r'^[a-f0-9]{32}$');

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var index = 0;
    var value = bytes.toDouble();
    while (value >= 1024 && index < suffixes.length - 1) {
      value /= 1024;
      index++;
    }
    return '${value.toStringAsFixed(index == 0 ? 0 : 2)} ${suffixes[index]}';
  }

  /// Runs after app startup; failures must never prevent the app from opening.
  static Future<void> trimOnStartup({
    int autoClearThresholdMb = defaultAutoClearThresholdMb,
  }) async {
    try {
      final cacheDirectory = await _cacheDirectory();
      await trimDirectory(
        cacheDirectory,
        clearAboveBytes: autoClearThresholdMb > 0
            ? autoClearThresholdMb * 1024 * 1024
            : null,
      );
    } catch (_) {
      // Android may remove the temporary directory while the app is running.
    }
  }

  /// Measures only ExtendedImage's direct, MD5-named disk cache files.
  static Future<int> getDiskCacheSize() async =>
      _getCacheBytes(await _cacheDirectory());

  /// Deletes only recognized image cache files and leaves files written in the
  /// last minute alone because an image request may still be using them.
  static Future<int> clearDiskCache() async {
    final cacheDirectory = await _cacheDirectory();
    if (!await cacheDirectory.exists()) return 0;

    final currentTime = DateTime.now();
    var deletedBytes = 0;
    await for (final entity in cacheDirectory.list(followLinks: false)) {
      if (entity is! File || !_isCacheFile(entity)) continue;
      try {
        final stat = await entity.stat();
        if (currentTime.difference(stat.modified) < minEvictionAge) continue;
        await entity.delete();
        deletedBytes += stat.size;
      } on FileSystemException {
        // A cache file may be replaced or removed while clearing.
      }
    }
    return deletedBytes;
  }

  /// Clears the managed image cache when it reaches the selected threshold.
  static Future<bool> checkAndAutoClearCache(int thresholdMb) async {
    if (thresholdMb <= 0) return false;
    try {
      if (await getDiskCacheSize() < thresholdMb * 1024 * 1024) return false;
      await clearDiskCache();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Only files with ExtendedImage's MD5 cache names are eligible for removal.
  static Future<void> trimDirectory(
    Directory cacheDirectory, {
    int maxBytes = maxCacheBytes,
    int? clearAboveBytes,
    Duration maxAge = maxCacheAge,
    DateTime? now,
  }) async {
    if (!await cacheDirectory.exists()) return;

    final currentTime = now ?? DateTime.now();
    final retained = <_CachedFile>[];
    var totalBytes = 0;
    var scannedBytes = 0;

    await for (final entity in cacheDirectory.list(followLinks: false)) {
      if (entity is! File || !_isCacheFile(entity)) continue;

      try {
        final stat = await entity.stat();
        scannedBytes += stat.size;
        final age = currentTime.difference(stat.modified);
        if (age > maxAge && age > minEvictionAge) {
          await entity.delete();
          continue;
        }
        retained.add(_CachedFile(entity, stat.modified, stat.size));
        totalBytes += stat.size;
      } on FileSystemException {
        // A cache file may be replaced or removed during enumeration.
      }
    }

    if (clearAboveBytes != null && scannedBytes >= clearAboveBytes) {
      for (final cached in retained) {
        if (currentTime.difference(cached.modified) < minEvictionAge) continue;
        try {
          await cached.file.delete();
        } on FileSystemException {
          // Leave an in-use cache file for the next maintenance pass.
        }
      }
      return;
    }

    if (totalBytes <= maxBytes) return;
    retained.sort((a, b) => a.modified.compareTo(b.modified));
    for (final cached in retained) {
      if (totalBytes <= maxBytes) break;
      if (currentTime.difference(cached.modified) < minEvictionAge) continue;
      try {
        await cached.file.delete();
        totalBytes -= cached.size;
      } on FileSystemException {
        // Leave an in-use cache file for the next maintenance pass.
      }
    }
  }

  static Future<Directory> _cacheDirectory() async {
    final temporaryDirectory = await getTemporaryDirectory();
    return Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}cacheimage',
    );
  }

  static Future<int> _getCacheBytes(Directory cacheDirectory) async {
    if (!await cacheDirectory.exists()) return 0;
    var totalBytes = 0;
    await for (final entity in cacheDirectory.list(followLinks: false)) {
      if (entity is! File || !_isCacheFile(entity)) continue;
      try {
        totalBytes += (await entity.stat()).size;
      } on FileSystemException {
        // A cache file may be replaced or removed during enumeration.
      }
    }
    return totalBytes;
  }

  static bool _isCacheFile(File file) {
    final name = file.path.split(Platform.pathSeparator).last;
    return _cacheFileName.hasMatch(name);
  }
}

class _CachedFile {
  const _CachedFile(this.file, this.modified, this.size);

  final File file;
  final DateTime modified;
  final int size;
}
