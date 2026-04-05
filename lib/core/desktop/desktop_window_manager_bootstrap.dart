import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Ensures the Windows taskbar integration in `window_manager` is initialized
/// before any `setSkipTaskbar` calls.
final class DesktopWindowManagerBootstrap {
  static Future<void>? _initializing;
  static Future<void>? _waitingUntilReadyToShow;

  static Future<void> ensureInitialized() {
    final current = _initializing;
    if (current != null) {
      return current;
    }

    late final Future<void> initializing;
    initializing = _initialize().catchError((Object error, StackTrace stack) {
      if (identical(_initializing, initializing)) {
        _initializing = null;
      }
      Error.throwWithStackTrace(error, stack);
    });
    _initializing = initializing;
    return initializing;
  }

  static Future<void> waitUntilReadyToShow() {
    final current = _waitingUntilReadyToShow;
    if (current != null) {
      return current;
    }

    late final Future<void> waitingUntilReadyToShow;
    waitingUntilReadyToShow =
        _waitUntilReadyToShow().catchError((Object error, StackTrace stack) {
      if (identical(_waitingUntilReadyToShow, waitingUntilReadyToShow)) {
        _waitingUntilReadyToShow = null;
      }
      Error.throwWithStackTrace(error, stack);
    });
    _waitingUntilReadyToShow = waitingUntilReadyToShow;
    return waitingUntilReadyToShow;
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
