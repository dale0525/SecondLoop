import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/quick_capture/quick_capture_controller.dart';

void main() {
  test('Hide can request reopening window and switching to Chat', () {
    final controller = QuickCaptureController();
    controller.show();

    controller.hide(reopenMainWindow: true, openChat: true);

    expect(controller.visible, false);
    expect(controller.consumeReopenMainWindowOnHideRequest(), isTrue);
    expect(controller.consumeReopenMainWindowOnHideRequest(), isFalse);
    expect(controller.consumeOpenChatRequest(), isTrue);
    expect(controller.consumeOpenChatRequest(), isFalse);
  });

  test('Hide without flags does not reopen window or switch Chat', () {
    final controller = QuickCaptureController();
    controller.show();

    controller.hide(reopenMainWindow: true, openChat: true);
    expect(controller.consumeReopenMainWindowOnHideRequest(), isTrue);
    expect(controller.consumeOpenChatRequest(), isTrue);

    controller.show();
    controller.hide();

    expect(controller.visible, isFalse);
    expect(controller.consumeReopenMainWindowOnHideRequest(), isFalse);
    expect(controller.consumeOpenChatRequest(), isFalse);
  });
}
