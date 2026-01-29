import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class AndroidMediaLocationPermission {
  static const MethodChannel _channel = MethodChannel('secondloop/permissions');

  static Future<bool> requestIfNeeded() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    try {
      final granted = await _channel.invokeMethod<bool>('requestMediaLocation');
      return granted == true;
    } catch (_) {
      return false;
    }
  }
}
