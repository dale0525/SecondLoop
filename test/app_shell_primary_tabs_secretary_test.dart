import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/app/router.dart';

void main() {
  test('secretary access does not add a primary app tab', () {
    expect(AppTab.values.length, 2);
    expect(AppTab.values, [AppTab.chat, AppTab.settings]);
  });
}
