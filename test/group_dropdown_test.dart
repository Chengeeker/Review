import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/features/feed/presentation/feed_controller.dart';
import 'package:review/features/feed/presentation/widgets/group_dropdown_panel.dart';

void main() {
  testWidgets('Latest and all-follow groups select and emit independent IDs', (
    tester,
  ) async {
    for (final currentId in ['friends', 'all_follow']) {
      String? selectedId;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupDropdownPanel(
              currentCategoryId: currentId,
              customDefaultGroups: FeedController.defaultInitialGroups,
              customPersonalGroups: const [],
              customHotGroups: const [],
              onSelectGroup: (id, name) => selectedId = id,
              onClose: () {},
            ),
          ),
        ),
      );
      final colors = Theme.of(tester.element(find.text('默认分组'))).colorScheme;
      for (final group in FeedController.defaultInitialGroups.take(2)) {
        final cell = tester.widget<Container>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.child is Text &&
                (widget.child as Text).data == group['name'],
          ),
        );
        expect(
          (cell.decoration as BoxDecoration).color == colors.primaryContainer,
          group['id'] == currentId,
        );
      }
      final nextName = currentId == 'friends' ? '全部关注' : '最新微博';
      await tester.tap(find.text(nextName));
      expect(selectedId, currentId == 'friends' ? 'all_follow' : 'friends');
    }
  });

  testWidgets(
    'When no official personal groups are available, hides the personal group section',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupDropdownPanel(
              currentCategoryId: 'friends',
              customDefaultGroups: FeedController.defaultInitialGroups,
              customPersonalGroups: const [],
              userGroups: const [],
              customHotGroups: const [],
              onSelectGroup: (id, name) {},
              onClose: () {},
            ),
          ),
        ),
      );

      expect(find.text('默认分组'), findsOneWidget);
      expect(find.text('我的分组'), findsNothing);
      final panelSize = tester.getSize(find.byType(GroupDropdownPanel));
      print(
        'Rendered panel size with empty input: width=${panelSize.width}, height=${panelSize.height}',
      );
    },
  );
}
