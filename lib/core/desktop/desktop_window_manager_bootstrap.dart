import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Ensures the Windows taskbar integration in `window_manager` is initialized
/// before any `setSkipTaskbar` calls.
final class DesktopWindowManagerBootstrap {
  static Future<void>? _ready;

  static Future<void> ensureInitialized() {
    final current = _ready;
    if (current != null) {
      return current;
    }

    late final Future<void> ready;
    ready = _initialize().catchError((Object error, StackTrace stack) {
      if (identical(_ready, ready)) {
        _ready = null;
      }
      Error.throwWithStackTrace(error, stack);
    });
    _ready = ready;
    return ready;
  }

  static Future<void> waitUntilReadyToShow() => ensureInitialized();

  static Future<void> _initialize() async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow();
  }

  @visibleForTesting
  static void resetForTest() {
    _ready = null;
  }
}
