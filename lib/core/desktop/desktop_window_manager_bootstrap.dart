import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Ensures the Windows taskbar integration in `window_manager` is initialized
/// before any `setSkipTaskbar` calls.
final class DesktopWindowManagerBootstrap {
  static Future<void>? _initializing;
  static Future<void>? _waitingUntilReadyToShow;

  static Future<void> ensureInitialized() {
    return _initializing ??= _initialize();
  }

  static Future<void> waitUntilReadyToShow() {
    return _waitingUntilReadyToShow ??= _waitUntilReadyToShow();
  }

  static Future<void> _initialize() async {
    await windowManager.ensureInitialized();
  }

  static Future<void> _waitUntilReadyToShow() async {
    await ensureInitialized();
    await windowManager.waitUntilReadyToShow();
  }

  @visibleForTesting
  static void resetForTest() {
    _initializing = null;
    _waitingUntilReadyToShow = null;
  }
}
