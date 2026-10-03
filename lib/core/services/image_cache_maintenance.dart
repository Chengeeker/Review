import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Keeps only bounded, reproducible ExtendedImage disk cache files.
class ImageCacheMaintenance {
  ImageCacheMaintenance._();

  static const int maxCacheBytes = 512 * 1024 * 1024;
  static const Duration maxCacheAge = Duration(days: 60);
  static const Duration minEvictionAge = Duration(minutes: 1);
  static final RegExp _cacheFileName = RegExp(r'^[a-f0-9]{32}$');

  /// Runs after app startup; failures must never prevent the app from opening.
  static Future<void> trimOnStartup() async {
    try {
      final temporaryDirectory = await getTemporaryDirectory();
      final cacheDirectory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}cacheimage',
      );
      await trimDirectory(cacheDirectory);
    } catch (_) {
      // Android may remove the temporary directory while the app is running.
    }
  }

  /// Only files with ExtendedImage's MD5 cache names are eligible for removal.
  static Future<void> trimDirectory(
    Directory cacheDirectory, {
    int maxBytes = maxCacheBytes,
    Duration maxAge = maxCacheAge,
    DateTime? now,
  }) async {
    if (!await cacheDirectory.exists()) return;

    final currentTime = now ?? DateTime.now();
    final retained = <_CachedFile>[];
    var totalBytes = 0;

    await for (final entity in cacheDirectory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!_cacheFileName.hasMatch(name)) continue;

      try {
        final stat = await entity.stat();
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
}

class _CachedFile {
  const _CachedFile(this.file, this.modified, this.size);

  final File file;
  final DateTime modified;
  final int size;
}
