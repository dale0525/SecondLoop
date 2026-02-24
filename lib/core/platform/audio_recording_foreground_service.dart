import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class AudioRecordingForegroundService {
  static const MethodChannel _channel = MethodChannel(
    'secondloop/audio_recording_lifecycle',
  );

  static Future<bool> startIfSupported() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    try {
      final started =
          await _channel.invokeMethod<bool>('startForegroundRecording');
      return started == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> stopIfSupported() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    try {
      final stopped =
          await _channel.invokeMethod<bool>('stopForegroundRecording');
      return stopped == true;
    } catch (_) {
      return false;
    }
  }
}
