import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/features/detail/presentation/widgets/image_gallery_page.dart';
import 'package:review/features/feed/data/models/weibo_status_model.dart';

const galleryTestPic = WeiboPicModel(
  pid: 'gallery-test',
  thumbnail: 'https://example.com/gallery-test.jpg',
  large: 'https://example.com/gallery-test.jpg',
  original: 'https://example.com/gallery-test.jpg',
);

class RecordingNavigatorObserver extends NavigatorObserver {
  String? poppedRouteName;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    poppedRouteName = route.settings.name;
    super.didPop(route, previousRoute);
  }
}

void main() {
  testWidgets('center tap toggles image gallery top controls', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ImageGalleryPage(
          pics: [galleryTestPic],
          initialIndex: 0,
          statusId: 'gallery-test',
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump();

    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    expect(find.byIcon(Icons.download_rounded), findsNothing);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump();

    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
  });

  testWidgets('side tap exits image gallery', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = RecordingNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('host page')),
      ),
    );
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'image-gallery-test'),
        builder: (_) => const ImageGalleryPage(
          pics: [galleryTestPic],
          initialIndex: 0,
          statusId: 'gallery-test',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tapAt(const Offset(100, 300));
    await tester.pump(const Duration(milliseconds: 500));

    expect(observer.poppedRouteName, 'image-gallery-test');
  });
}
