import 'package:flutter_test/flutter_test.dart';
import 'package:review/features/feed/presentation/feed_controller.dart';

void main() {
  test('FeedState.copyWith can clear a previous error message', () {
    const state = FeedState(
      statuses: [],
      currentCategory: 'friends',
      errorMessage: '暂无微博内容',
    );

    final cleared = state.copyWith(errorMessage: null);

    expect(cleared.errorMessage, isNull);
  });
}
