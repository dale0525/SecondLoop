import 'package:shared_preferences/shared_preferences.dart';

const String kDefaultAudioTranscribeWhisperModel = 'base';

const List<String> audioTranscribeWhisperModelOptions = <String>[
  'tiny',
  'base',
  'small',
  'medium',
  'large-v3-turbo',
  'large-v3',
];

String normalizeAudioTranscribeWhisperModel(String model) {
  final normalized = model.trim().toLowerCase();
  for (final option in audioTranscribeWhisperModelOptions) {
    if (option == normalized) {
      return option;
    }
  }
  return kDefaultAudioTranscribeWhisperModel;
}

final class AudioTranscribeWhisperModelPrefs {
  static const _prefsKey =
      'media_capability_audio_transcribe_whisper_model_preference_v1';

  static Future<String> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString(_prefsKey) ?? kDefaultAudioTranscribeWhisperModel;
    return normalizeAudioTranscribeWhisperModel(raw);
  }

  static Future<void> write(String model) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = normalizeAudioTranscribeWhisperModel(model);
    await prefs.setString(_prefsKey, normalized);
  }
}
