import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../quick_capture/quick_capture_controller.dart';
import '../quick_capture/quick_capture_scope.dart';

abstract class DesktopHotkeyAdapter {
  Future<void> register({required VoidCallback onPressed});
  Future<void> unregister();
}

abstract class DesktopWindowAdapter {
  Future<void> showAndFocus();
  Future<void> hide();

  Future<void> enterQuickCaptureMode();
  Future<void> exitQuickCaptureMode();
}

class DesktopQuickCaptureService extends StatefulWidget {
  const DesktopQuickCaptureService({required this.child, super.key});

  final Widget child;

  @override
  State<DesktopQuickCaptureService> createState() =>
      _DesktopQuickCaptureServiceState();
}

class _DesktopQuickCaptureServiceState extends State<DesktopQuickCaptureService>
    with WindowListener {
  DesktopQuickCaptureCoordinator? _coordinator;
  bool _enabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_coordinator != null) return;

    final isDesktop = !kIsWeb &&
        switch (defaultTargetPlatform) {
          TargetPlatform.windows ||
          TargetPlatform.macOS ||
          TargetPlatform.linux =>
            true,
          _ => false,
        };
    if (!isDesktop) return;

    _enabled = true;
    final controller = QuickCaptureScope.of(context);
    final window = WindowManagerDesktopWindowAdapter();
    final hotkey = HotkeyManagerDesktopHotkeyAdapter(
      platform: defaultTargetPlatform,
    );

    _coordinator = DesktopQuickCaptureCoordinator(
      controller: controller,
      window: window,
      hotkey: hotkey,
    );

    unawaited(_initDesktop());
  }

  Future<void> _initDesktop() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await _coordinator?.init();
  }

  @override
  void dispose() {
    if (_enabled) {
      windowManager.removeListener(this);
      final coordinator = _coordinator;
      if (coordinator != null) unawaited(coordinator.dispose());
    }
    super.dispose();
  }

  @override
  void onWindowBlur() {
    _coordinator?.onWindowBlur();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

final class HotkeyManagerDesktopHotkeyAdapter implements DesktopHotkeyAdapter {
  HotkeyManagerDesktopHotkeyAdapter({required TargetPlatform platform})
      : _hotKey = HotKey(
          key: LogicalKeyboardKey.keyK,
          modifiers: [
            if (platform == TargetPlatform.macOS)
              HotKeyModifier.meta
            else
              HotKeyModifier.control,
            HotKeyModifier.shift,
          ],
          scope: HotKeyScope.system,
        );

  final HotKey _hotKey;

  @override
  Future<void> register({required VoidCallback onPressed}) async {
    await hotKeyManager.register(
      _hotKey,
      keyDownHandler: (_) => onPressed(),
    );
  }

  @override
  Future<void> unregister() async {
    await hotKeyManager.unregister(_hotKey);
  }
}

final class WindowManagerDesktopWindowAdapter implements DesktopWindowAdapter {
  static const _kQuickCaptureSize = Size(560, 160);

  Size? _savedSize;
  Offset? _savedPosition;

  @override
  Future<void> showAndFocus() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hide() async {
    await windowManager.hide();
  }

  @override
  Future<void> enterQuickCaptureMode() async {
    _savedSize = await windowManager.getSize();
    _savedPosition = await windowManager.getPosition();

    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(_kQuickCaptureSize);
    await windowManager.center();
  }

  @override
  Future<void> exitQuickCaptureMode() async {
    await windowManager.setAlwaysOnTop(false);

    final size = _savedSize;
    final pos = _savedPosition;
    if (size != null) await windowManager.setSize(size);
    if (pos != null) await windowManager.setPosition(pos);

    _savedSize = null;
    _savedPosition = null;
  }
}

final class DesktopQuickCaptureCoordinator {
  DesktopQuickCaptureCoordinator({
    required this.controller,
    required this.window,
    required this.hotkey,
  });

  final QuickCaptureController controller;
  final DesktopWindowAdapter window;
  final DesktopHotkeyAdapter hotkey;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    controller.addListener(_onControllerChanged);
    await hotkey.register(onPressed: controller.toggle);
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    _initialized = false;

    controller.removeListener(_onControllerChanged);
    await hotkey.unregister();
  }

  void onWindowBlur() {
    if (!controller.visible) return;
    controller.hide();
  }

  void _onControllerChanged() {
    unawaited(_syncWindow());
  }

  Future<void> _syncWindow() async {
    if (controller.visible) {
      await window.enterQuickCaptureMode();
      await window.showAndFocus();
      return;
    }

    await window.exitQuickCaptureMode();
    await window.hide();
  }
}
