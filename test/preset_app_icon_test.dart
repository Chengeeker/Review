import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/theme/custom_app_icon_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Preset App Icon Tests', () {
    test('Preset icons list contains exactly 3 non-deletable icons', () {
      expect(kPresetAppIcons.length, 3);
      expect(kPresetAppIcons.first.id, 'default');
      expect(kPresetAppIcons.first.name, '官方默认');
      expect(kPresetAppIcons.first.isDefault, isTrue);

      final alias1 = kPresetAppIcons.firstWhere((e) => e.id == 'alias1');
      expect(alias1.name, '质感经典');
      expect(alias1.alias, 'alias1');

      final alias2 = kPresetAppIcons.firstWhere((e) => e.id == 'alias2');
      expect(alias2.name, '活力新潮');
      expect(alias2.alias, 'alias2');
    });

    test('CustomAppIconState defaults to default icon', () {
      const state = CustomAppIconState();
      expect(state.currentId, 'default');
      expect(state.isDefault, isTrue);
      expect(state.currentDisplayName, '官方默认');
      expect(state.currentAssetPath, 'assets/icons/app_icon_default.png');
    });

    test('CustomAppIconState switching correctly updates active model', () {
      const state = CustomAppIconState();
      final switched = state.copyWith(currentId: 'alias2');
      expect(switched.currentId, 'alias2');
      expect(switched.isDefault, isFalse);
      expect(switched.currentDisplayName, '活力新潮');
      expect(switched.currentAssetPath, 'assets/icons/app_icon_2.png');
    });

    test('All 3 preset icon assets exist in project assets', () {
      for (final item in kPresetAppIcons) {
        final f = File(item.assetPath);
        expect(f.existsSync(), isTrue, reason: '${item.assetPath} must exist on disk');
      }
    });
  });
}
