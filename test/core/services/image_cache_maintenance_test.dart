import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/services/image_cache_maintenance.dart';

void main() {
  test('only evicts aged or excess image cache files', () async {
    final directory =
        await Directory.systemTemp.createTemp('review-image-cache-');
    addTearDown(() => directory.delete(recursive: true));
    final now = DateTime(2026, 9, 25);

    Future<File> create(String name, int bytes, Duration age) async {
      final file = File('${directory.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(List<int>.filled(bytes, 1));
      await file.setLastModified(now.subtract(age));
      return file;
    }

    final expired = await create('a' * 32, 10, const Duration(days: 61));
    final oldest = await create('b' * 32, 12, const Duration(days: 10));
    final newest = await create('c' * 32, 12, const Duration(days: 2));
    final unrelated = await create('notes.txt', 100, const Duration(days: 90));
    final nested = Directory(
      '${directory.path}${Platform.pathSeparator}nested',
    );
    await nested.create();
    final nestedFile =
        File('${nested.path}${Platform.pathSeparator}${'d' * 32}');
    await nestedFile.writeAsBytes(<int>[1]);

    await ImageCacheMaintenance.trimDirectory(
      directory,
      maxBytes: 15,
      now: now,
    );

    expect(await expired.exists(), isFalse);
    expect(await oldest.exists(), isFalse);
    expect(await newest.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
    expect(await nestedFile.exists(), isTrue);
  });

  test('leaves images still being written for a later pass', () async {
    final directory =
        await Directory.systemTemp.createTemp('review-image-cache-');
    addTearDown(() => directory.delete(recursive: true));
    final recent =
        File('${directory.path}${Platform.pathSeparator}${'e' * 32}');
    await recent.writeAsBytes(List<int>.filled(10, 1));

    await ImageCacheMaintenance.trimDirectory(directory, maxBytes: 1);

    expect(await recent.exists(), isTrue);
  });
}
