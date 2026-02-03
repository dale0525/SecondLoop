import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../quick_capture/quick_capture_controller.dart';
import '../quick_capture/quick_capture_scope.dart';
import 'desktop_quick_capture_hotkey_prefs.dart';

abstract class DesktopHotkeyAdapter {
  Future<void> register(
      {required HotKey hotKey, required VoidCallback onPressed});
  Future<void> unregister(HotKey hotKey);
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
  VoidCallback? _hotkeyPrefsListener;

  HotKey _defaultHotKey(TargetPlatform platform) => HotKey(
        identifier: DesktopQuickCaptureHotkeyPrefs.hotKeyIdentifier,
        key: PhysicalKeyboardKey.keyK,
        modifiers: [
          if (platform == TargetPlatform.macOS)
            HotKeyModifier.meta
          else
            HotKeyModifier.control,
          HotKeyModifier.shift,
        ],
        scope: HotKeyScope.system,
      );

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
    final hotkey = HotkeyManagerDesktopHotkeyAdapter();
    final defaultHotKey = _defaultHotKey(defaultTargetPlatform);

    _coordinator = DesktopQuickCaptureCoordinator(
      controller: controller,
      window: window,
      hotkey: hotkey,
      hotKey: defaultHotKey,
    );

    unawaited(_initDesktop());
  }

  Future<void> _initDesktop() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);

    await DesktopQuickCaptureHotkeyPrefs.load();

    void onHotkeyPrefChanged() {
      final coordinator = _coordinator;
      if (coordinator == null) return;

      final hotKey = DesktopQuickCaptureHotkeyPrefs.value.value ??
          _defaultHotKey(defaultTargetPlatform);
      unawaited(coordinator.updateHotKey(hotKey));
    }

    _hotkeyPrefsListener = onHotkeyPrefChanged;
    DesktopQuickCaptureHotkeyPrefs.value.addListener(onHotkeyPrefChanged);

    onHotkeyPrefChanged();
    await _coordinator?.init();
  }

  @override
  void dispose() {
    if (_enabled) {
      windowManager.removeListener(this);
      final listener = _hotkeyPrefsListener;
      if (listener != null) {
        DesktopQuickCaptureHotkeyPrefs.value.removeListener(listener);
      }
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
  @override
  Future<void> register({
    required HotKey hotKey,
    required VoidCallback onPressed,
  }) async {
    await hotKeyManager.register(
      hotKey,
      keyDownHandler: (_) => onPressed(),
    );
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    await hotKeyManager.unregister(hotKey);
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
    required HotKey hotKey,
  }) : _hotKey = hotKey;

  HotKey _hotKey;

  final QuickCaptureController controller;
  final DesktopWindowAdapter window;
  final DesktopHotkeyAdapter hotkey;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    controller.addListener(_onControllerChanged);
    await hotkey.register(hotKey: _hotKey, onPressed: controller.toggle);
  }

  Future<void> updateHotKey(HotKey hotKey) async {
    final previous = _hotKey;
    _hotKey = hotKey;
    if (!_initialized) return;

    await hotkey.unregister(previous);
    await hotkey.register(hotKey: _hotKey, onPressed: controller.toggle);
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    _initialized = false;

    controller.removeListener(_onControllerChanged);
    await hotkey.unregister(_hotKey);
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
