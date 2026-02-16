import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/desktop/desktop_tray_click_controller.dart';

void main() {
  test('left click opens main window directly', () async {
    var leftCalls = 0;
    var rightCalls = 0;

    final controller = DesktopTrayClickController(
      onLeftClick: () async {
        leftCalls += 1;
      },
      onRightClick: () async {
        rightCalls += 1;
      },
    );

    await controller.handleLeftMouseDown();

    expect(leftCalls, 1);
    expect(rightCalls, 0);
  });

  test('right click opens tray menu', () async {
    var leftCalls = 0;
    var rightCalls = 0;

    final controller = DesktopTrayClickController(
      onLeftClick: () async {
        leftCalls += 1;
      },
      onRightClick: () async {
        rightCalls += 1;
      },
    );

    await controller.handleRightMouseDown();

    expect(leftCalls, 0);
    expect(rightCalls, 1);
  });
}
