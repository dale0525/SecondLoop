import 'package:shared_preferences/shared_preferences.dart';

final class AudioTranscribeGatewayLimitPrefs {
  static const _prefsKey =
      'media_capability_audio_transcribe_gateway_max_bytes_v1';

  static Future<int?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_prefsKey);
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  }

  static Future<void> write(int value) async {
    if (value <= 0) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, value);
  }
}
