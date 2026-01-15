import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/desktop/desktop_quick_capture_service.dart';
import 'package:secondloop/core/quick_capture/quick_capture_controller.dart';

void main() {
  test('Hotkey toggles controller and window', () async {
    final controller = QuickCaptureController();
    final window = _FakeWindow();
    final hotkey = _FakeHotkey();

    final service = DesktopQuickCaptureCoordinator(
      controller: controller,
      window: window,
      hotkey: hotkey,
    );

    await service.init();
    expect(hotkey.registered, true);

    hotkey.trigger();
    await pumpEventQueue();
    expect(controller.visible, true);
    expect(window.showAndFocusCalls, 1);
    expect(window.enterQuickCaptureCalls, 1);

    hotkey.trigger();
    await pumpEventQueue();
    expect(controller.visible, false);
    expect(window.hideCalls, 1);
    expect(window.exitQuickCaptureCalls, 1);
  });

  test('Blur auto-hides when visible', () async {
    final controller = QuickCaptureController();
    final window = _FakeWindow();
    final hotkey = _FakeHotkey();

    final service = DesktopQuickCaptureCoordinator(
      controller: controller,
      window: window,
      hotkey: hotkey,
    );

    await service.init();
    hotkey.trigger();
    await pumpEventQueue();
    expect(controller.visible, true);

    service.onWindowBlur();
    await pumpEventQueue();
    expect(controller.visible, false);
    expect(window.hideCalls, 1);
  });
}

final class _FakeHotkey implements DesktopHotkeyAdapter {
  bool registered = false;
  void Function()? _onPressed;

  @override
  Future<void> register({required void Function() onPressed}) async {
    registered = true;
    _onPressed = onPressed;
  }

  @override
  Future<void> unregister() async {
    registered = false;
    _onPressed = null;
  }

  void trigger() => _onPressed?.call();
}

final class _FakeWindow implements DesktopWindowAdapter {
  int showAndFocusCalls = 0;
  int hideCalls = 0;
  int enterQuickCaptureCalls = 0;
  int exitQuickCaptureCalls = 0;

  @override
  Future<void> showAndFocus() async {
    showAndFocusCalls++;
  }

  @override
  Future<void> hide() async {
    hideCalls++;
  }

  @override
  Future<void> enterQuickCaptureMode() async {
    enterQuickCaptureCalls++;
  }

  @override
  Future<void> exitQuickCaptureMode() async {
    exitQuickCaptureCalls++;
  }
}
