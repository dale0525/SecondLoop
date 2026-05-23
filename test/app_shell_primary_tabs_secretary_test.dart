import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/app/router.dart';

void main() {
  test('agent shell exposes the managed pro primary tabs', () {
    expect(AppTab.values, [
      AppTab.review,
      AppTab.conversation,
      AppTab.notes,
      AppTab.memory,
      AppTab.settings,
    ]);
    expect(AppTab.chat, AppTab.conversation);
  });
}
