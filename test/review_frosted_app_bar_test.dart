import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/design_system/components/review_frosted_app_bar.dart';

void main() {
  testWidgets('bottom hairline can be disabled while tinted material remains', (
    tester,
  ) async {
    const appBarColor = Color(0xff342f48);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          appBarTheme: const AppBarTheme(backgroundColor: appBarColor),
        ),
        home: const Scaffold(
          appBar: ReviewFrostedAppBar(
            title: Text('超话中心'),
            showBottomBorder: false,
          ),
          body: SizedBox.expand(),
        ),
      ),
    );

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final flexibleSpace = find.byWidget(appBar.flexibleSpace!);
    final decoration = tester.widget<DecoratedBox>(
      find.descendant(of: flexibleSpace, matching: find.byType(DecoratedBox)),
    );
    final boxDecoration = decoration.decoration as BoxDecoration;
    final gradient = boxDecoration.gradient! as LinearGradient;
    expect(boxDecoration.border, isNull);
    expect(gradient.begin, Alignment.topCenter);
    expect(gradient.end, Alignment.bottomCenter);
    expect(gradient.colors, [
      appBarColor.withValues(alpha: 0.95),
      appBarColor.withValues(alpha: 0),
    ]);
    final backdropFinder = find.byType(BackdropFilter);
    expect(
      find.descendant(of: backdropFinder, matching: find.byType(DecoratedBox)),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: backdropFinder, matching: find.byType(ShaderMask)),
      findsNothing,
    );
    expect(
      find.ancestor(of: backdropFinder, matching: find.byType(ClipRect)),
      findsWidgets,
    );
    expect(
      tester.widget<BackdropFilter>(backdropFinder).blendMode,
      BlendMode.srcOver,
    );
    expect(
      appBar.backgroundColor,
      appBarColor.withValues(alpha: reviewFrostedMaterialAlpha),
    );
    expect(
      1 - (1 - appBar.backgroundColor!.a) * (1 - gradient.colors.first.a),
      closeTo(0.9725, 0.001),
    );
    expect(appBar.forceMaterialTransparency, isFalse);
  });

  testWidgets('review app bar paints the timeline tint on its Material', (
    tester,
  ) async {
    const appBarColor = Color(0xff342f48);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          appBarTheme: const AppBarTheme(backgroundColor: appBarColor),
        ),
        home: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: const ReviewFrostedAppBar(title: Text('磨砂顶栏')),
          body: ListView(
            children: const [SizedBox(height: 900, child: Text('滚动内容'))],
          ),
        ),
      ),
    );

    expect(find.byType(ReviewFrostedAppBar), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(
      appBar.backgroundColor,
      appBarColor.withValues(alpha: reviewFrostedMaterialAlpha),
    );
    expect(appBar.forceMaterialTransparency, isFalse);
    expect(find.text('磨砂顶栏'), findsOneWidget);
  });
}
