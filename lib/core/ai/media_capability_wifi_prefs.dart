import 'package:shared_preferences/shared_preferences.dart';

enum MediaCapabilityWifiScope {
  audioTranscribe,
  documentOcr,
  imageCaption,
}

final class MediaCapabilityWifiPrefs {
  static const _audioWifiOnlyKey = 'media_capability_audio_wifi_only_v1';
  static const _ocrWifiOnlyKey = 'media_capability_ocr_wifi_only_v1';
  static const _imageWifiOnlyKey = 'media_capability_image_wifi_only_v1';

  static Future<bool> readAudioWifiOnly({
    required bool fallbackWifiOnly,
  }) async {
    return _readWifiOnly(
      _audioWifiOnlyKey,
      fallbackWifiOnly: fallbackWifiOnly,
    );
  }

  static Future<bool> readOcrWifiOnly({
    required bool fallbackWifiOnly,
  }) async {
    return _readWifiOnly(
      _ocrWifiOnlyKey,
      fallbackWifiOnly: fallbackWifiOnly,
    );
  }

  static Future<bool> readImageWifiOnly({
    required bool fallbackWifiOnly,
  }) async {
    return _readWifiOnly(
      _imageWifiOnlyKey,
      fallbackWifiOnly: fallbackWifiOnly,
    );
  }

  static Future<void> write(
    MediaCapabilityWifiScope scope, {
    required bool wifiOnly,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOf(scope), wifiOnly);
  }

  static Future<void> writeAll({required bool wifiOnly}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_audioWifiOnlyKey, wifiOnly);
    await prefs.setBool(_ocrWifiOnlyKey, wifiOnly);
    await prefs.setBool(_imageWifiOnlyKey, wifiOnly);
  }

  static Future<bool> _readWifiOnly(
    String key, {
    required bool fallbackWifiOnly,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? fallbackWifiOnly;
  }

  static String _keyOf(MediaCapabilityWifiScope scope) {
    return switch (scope) {
      MediaCapabilityWifiScope.audioTranscribe => _audioWifiOnlyKey,
      MediaCapabilityWifiScope.documentOcr => _ocrWifiOnlyKey,
      MediaCapabilityWifiScope.imageCaption => _imageWifiOnlyKey,
    };
  }
}
