import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_source_prefs.dart';

enum MediaCapabilitySourceScope {
  audioTranscribe,
  documentOcr,
}

final class MediaCapabilitySourcePrefs {
  static const _audioSourceKey = 'media_capability_audio_source_preference_v1';
  static const _ocrSourceKey = 'media_capability_ocr_source_preference_v1';

  static Future<MediaSourcePreference> readAudio() async {
    final prefs = await SharedPreferences.getInstance();
    final value = _decode(prefs.getString(_audioSourceKey));
    if (value == MediaSourcePreference.local &&
        !supportsPlatformLocalRuntimeAudioTranscribe()) {
      return MediaSourcePreference.auto;
    }
    return value;
  }

  static Future<MediaSourcePreference> readDocumentOcr() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_ocrSourceKey));
  }

  static Future<void> write(
    MediaCapabilitySourceScope scope, {
    required MediaSourcePreference preference,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _encode(preference);
    if (raw == null) {
      await prefs.remove(_keyOf(scope));
      return;
    }
    await prefs.setString(_keyOf(scope), raw);
  }

  static String _keyOf(MediaCapabilitySourceScope scope) {
    return switch (scope) {
      MediaCapabilitySourceScope.audioTranscribe => _audioSourceKey,
      MediaCapabilitySourceScope.documentOcr => _ocrSourceKey,
    };
  }

  static MediaSourcePreference _decode(String? raw) {
    return switch (raw?.trim() ?? '') {
      'cloud' => MediaSourcePreference.cloud,
      'byok' => MediaSourcePreference.byok,
      'local' => MediaSourcePreference.local,
      _ => MediaSourcePreference.auto,
    };
  }

  static String? _encode(MediaSourcePreference preference) {
    return switch (preference) {
      MediaSourcePreference.auto => null,
      MediaSourcePreference.cloud => 'cloud',
      MediaSourcePreference.byok => 'byok',
      MediaSourcePreference.local => 'local',
    };
  }

  static bool supportsPlatformLocalRuntimeAudioTranscribe() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }
}
