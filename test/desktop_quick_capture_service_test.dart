import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:secondloop/core/desktop/desktop_quick_capture_service.dart';
import 'package:secondloop/core/quick_capture/quick_capture_controller.dart';

void main() {
  test('Hotkey toggles controller and window', () async {
    final controller = QuickCaptureController();
    final window = _FakeWindow();
    final hotkey = _FakeHotkey();
    final initialHotKey = HotKey(
      key: PhysicalKeyboardKey.keyK,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );

    final service = DesktopQuickCaptureCoordinator(
      controller: controller,
      window: window,
      hotkey: hotkey,
      hotKey: initialHotKey,
    );

    await service.init();
    expect(hotkey.registeredHotKeys, [initialHotKey]);

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

  test('Updating hotkey re-registers', () async {
    final controller = QuickCaptureController();
    final window = _FakeWindow();
    final hotkey = _FakeHotkey();
    final initialHotKey = HotKey(
      key: PhysicalKeyboardKey.keyK,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );

    final service = DesktopQuickCaptureCoordinator(
      controller: controller,
      window: window,
      hotkey: hotkey,
      hotKey: initialHotKey,
    );

    await service.init();
    expect(hotkey.registeredHotKeys, [initialHotKey]);

    final nextHotKey = HotKey(
      key: PhysicalKeyboardKey.keyJ,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );

    await service.updateHotKey(nextHotKey);
    expect(hotkey.unregisteredHotKeys, [initialHotKey]);
    expect(hotkey.registeredHotKeys.last, nextHotKey);
  });

  test('Blur auto-hides when visible', () async {
    final controller = QuickCaptureController();
    final window = _FakeWindow();
    final hotkey = _FakeHotkey();
    final initialHotKey = HotKey(
      key: PhysicalKeyboardKey.keyK,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );

    final service = DesktopQuickCaptureCoordinator(
      controller: controller,
      window: window,
      hotkey: hotkey,
      hotKey: initialHotKey,
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
  final List<HotKey> registeredHotKeys = [];
  final List<HotKey> unregisteredHotKeys = [];
  void Function()? _onPressed;

  @override
  Future<void> register(
      {required HotKey hotKey, required void Function() onPressed}) async {
    registeredHotKeys.add(hotKey);
    _onPressed = onPressed;
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    unregisteredHotKeys.add(hotKey);
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
