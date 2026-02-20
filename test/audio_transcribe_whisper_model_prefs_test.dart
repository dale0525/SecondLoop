import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/audio_transcribe_whisper_model_prefs.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('normalizes unknown whisper model to base', () {
    expect(normalizeAudioTranscribeWhisperModel('unknown-model'), 'base');
    expect(normalizeAudioTranscribeWhisperModel(''), 'base');
  });

  test('read returns platform default by default', () async {
    final model = await AudioTranscribeWhisperModelPrefs.read();
    expect(model, defaultAudioTranscribeWhisperModelForCurrentPlatform());
  });

  test('write and read keep supported whisper model', () async {
    await AudioTranscribeWhisperModelPrefs.write('small');
    final model = await AudioTranscribeWhisperModelPrefs.read();
    expect(model, 'small');
  });

  test('write normalizes unsupported value back to base', () async {
    await AudioTranscribeWhisperModelPrefs.write('not-supported');
    final model = await AudioTranscribeWhisperModelPrefs.read();
    expect(model, 'base');
  });

  test('default model helper returns tiny on mobile and base on desktop', () {
    final previous = debugDefaultTargetPlatformOverride;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previous;
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(defaultAudioTranscribeWhisperModelForCurrentPlatform(), 'tiny');

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(defaultAudioTranscribeWhisperModelForCurrentPlatform(), 'tiny');

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(defaultAudioTranscribeWhisperModelForCurrentPlatform(), 'base');
  });
  test('supported models list includes base default', () {
    expect(audioTranscribeWhisperModelOptions, contains('base'));
    expect(audioTranscribeWhisperModelOptions.first, 'tiny');
  });
}
