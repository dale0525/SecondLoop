import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Ensures the Windows taskbar integration in `window_manager` is initialized
/// before any `setSkipTaskbar` calls.
final class DesktopWindowManagerBootstrap {
  static const MethodChannel _channel = MethodChannel('window_manager');
  static Future<void>? _initializing;

  static Future<void> ensureInitialized() {
    return _initializing ??= _initialize();
  }

  static Future<void> _initialize() async {
    await windowManager.ensureInitialized();
    await _channel.invokeMethod<void>('waitUntilReadyToShow');
  }

  @visibleForTesting
  static void resetForTest() {
    _initializing = null;
  }
}
