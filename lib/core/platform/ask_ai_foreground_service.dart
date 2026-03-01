import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final class AskAiForegroundService {
  static const MethodChannel _channel = MethodChannel(
    'secondloop/audio_recording_lifecycle',
  );

  static Future<bool> startIfSupported() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    await _requestNotificationsPermissionBestEffort();

    try {
      final started = await _channel.invokeMethod<bool>('startForegroundAskAi');
      return started == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> stopIfSupported() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    try {
      final stopped = await _channel.invokeMethod<bool>('stopForegroundAskAi');
      return stopped == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _requestNotificationsPermissionBestEffort() async {
    try {
      final androidImpl = AndroidFlutterLocalNotificationsPlugin();
      await androidImpl.requestNotificationsPermission();
    } catch (_) {
      // Best-effort only.
    }
  }
}
