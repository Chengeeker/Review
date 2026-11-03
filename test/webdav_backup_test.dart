import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/settings/presentation/webdav_backup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.review/weibo_auth');
  late StorageService storage;
  final calls = <MethodCall>[];
  final native = jsonEncode({
    'uid': 'owner',
    'gsid': 'native-secret',
    'accessToken': 'native-token',
  });

  setUp(() async {
    calls.clear();
    SharedPreferences.setMockInitialValues({
      StorageService.keyThemeMode: 2,
      StorageService.keyBrowsingHistoryStatuses: ['{"id":"123"}'],
      StorageService.keyBlockedUserIds: ['blocked'],
      StorageService.keyAppTextScale: 1.2,
      StorageService.keySubCookie: 'sub',
      StorageService.keyFullCookie: 'SUB=sub',
      StorageService.keyAccessToken: 'token',
      StorageService.keyUserUid: 'owner',
      StorageService.keyIsLoggedIn: true,
      StorageService.keyWebDavPassword: 'dav-secret',
      'unknown_secret': 'excluded',
    });
    storage = await StorageService.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'exportBackupSession' ? native : true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'safe backup covers local data and never accesses or restores credentials',
    () async {
      final data = await storage.exportAllData();
      final prefs = data['preferences'] as Map<String, dynamic>;
      expect(data['backup_mode'], 'safe');
      expect(data.containsKey('native_session'), isFalse);
      expect(prefs[StorageService.keyBrowsingHistoryStatuses], [
        '{"id":"123"}',
      ]);
      expect(prefs[StorageService.keyBlockedUserIds], ['blocked']);
      expect(prefs[StorageService.keyAppTextScale], 1.2);
      expect(
        prefs.keys.toSet().intersection(StorageService.credentialKeys),
        isEmpty,
      );
      prefs[StorageService.keySubCookie] = 'injected';
      prefs[StorageService.keyWebDavPassword] = 'injected';
      await storage.restoreAllData(data);
      expect(storage.getSubCookie(), 'sub');
      expect(storage.getWebDavPassword(), 'dav-secret');
      expect(calls, isEmpty);
    },
  );

  test(
    'full backup round trips cookies, tokens, password and native session',
    () async {
      final data = jsonDecode(
        jsonEncode(await storage.exportAllData(includeCredentials: true)),
      ) as Map<String, dynamic>;
      expect(data['native_session'], native);
      expect(
        (data['preferences'] as Map).containsKey('unknown_secret'),
        isFalse,
      );
      await storage.setMobileCookie('stale-other-account');
      await storage.setWebDavPassword('changed');
      await storage.restoreAllData(data);
      expect(storage.getFullCookie(), 'SUB=sub');
      expect(storage.getAccessToken(), 'token');
      expect(storage.getWebDavPassword(), 'dav-secret');
      expect(storage.getMobileCookie(), isNull);
      expect(calls.last.method, 'restoreBackupSession');
      expect(calls.last.arguments['session'], native);
    },
  );

  test('legacy safe backups preserve current credentials', () async {
    await storage.restoreAllData({
      'app': 'Review',
      'version': '1.0',
      'preferences': {
        StorageService.keyThemeMode: 1,
        StorageService.keyFullCookie: 'injected',
      },
    });
    expect(storage.getInt(StorageService.keyThemeMode), 1);
    expect(storage.getFullCookie(), 'SUB=sub');
    expect(calls, isEmpty);
  });

  test(
    'invalid backups and mismatched native account fail before writes',
    () async {
      final data = await storage.exportAllData(includeCredentials: true);
      (data['preferences'] as Map)[StorageService.keyUserUid] = 'another';
      await expectLater(storage.restoreAllData(data), throwsFormatException);
      expect(storage.getString(StorageService.keyUserUid), 'owner');
      expect(
        calls.where((call) => call.method == 'restoreBackupSession'),
        isEmpty,
      );
      await expectLater(
        storage.restoreAllData({'app': 'Other', 'preferences': {}}),
        throwsFormatException,
      );
    },
  );

  testWidgets('backup UI defaults to safe and allows explicit full selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const MaterialApp(home: WebDavBackupPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RadioListTile<bool>>(
            find.widgetWithText(RadioListTile<bool>, '全量安全备份'),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>).first)
          .groupValue,
      isFalse,
    );
    await tester.tap(find.text('全量备份'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>).last)
          .groupValue,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('native read/write failures are reported without replacing local preferences', () async {
    final data = await storage.exportAllData(includeCredentials: true);
    await storage.setAccessToken('current-token');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    await expectLater(storage.restoreAllData(data), throwsStateError);
    expect(storage.getAccessToken(), 'current-token');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'read_failed');
        });
    await expectLater(
      storage.exportAllData(includeCredentials: true),
      throwsA(isA<PlatformException>()),
    );
  });

  test('cookie-only full backup clears an old native session and validates setting types', () async {
    final data = await storage.exportAllData(includeCredentials: true);
    data.remove('native_session');
    (data['preferences'] as Map)[StorageService.keyAppTextScale] = 1;
    await storage.restoreAllData(data);
    expect(calls.last.arguments['session'], isNull);
    expect(storage.getAppTextScale(), 1.0);
    (data['preferences'] as Map)[StorageService.keyThemeMode] = 'invalid-type';
    final before = calls.length;
    await expectLater(storage.restoreAllData(data), throwsFormatException);
    expect(calls.length, before);
    expect(storage.getInt(StorageService.keyThemeMode), 2);
  });
}
