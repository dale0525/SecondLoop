import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/desktop/desktop_tray_popup_layout.dart';

void main() {
  test('compact tray popup height is tightened when no pro usage section', () {
    final compact = resolveTrayPopupWindowSize(reserveProUsageSpace: false);
    expect(compact.width, 288);
    expect(compact.height, 200);
  });

  test('tray popup keeps full height when pro usage section is shown', () {
    final full = resolveTrayPopupWindowSize(reserveProUsageSpace: true);
    expect(full.width, 288);
    expect(full.height, 296);
  });
}
