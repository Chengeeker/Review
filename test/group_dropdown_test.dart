import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/features/feed/presentation/feed_controller.dart';
import 'package:review/features/feed/presentation/widgets/group_dropdown_panel.dart';

void main() {
  testWidgets('When customPersonalGroups is empty, fallbacks to default personal groups and has compact height', (tester) async {
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
    expect(find.text('我的分组'), findsOneWidget);
    final panelSize = tester.getSize(find.byType(GroupDropdownPanel));
    print('Rendered panel size with empty input: width=${panelSize.width}, height=${panelSize.height}');
  });
}
