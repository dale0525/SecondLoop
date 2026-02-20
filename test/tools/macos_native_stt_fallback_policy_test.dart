import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'audio transcribe client selection keeps runtime fallback and no longer uses native stt chain',
    () {
      final content = File(
        'lib/core/media_enrichment/media_enrichment_gate_audio_transcribe.dart',
      ).readAsStringSync();

      expect(content, contains('LocalRuntimeAudioTranscribeClient('));
      expect(content,
          isNot(contains('supportsPlatformNativeSttAudioTranscribe()')));
      expect(content, isNot(contains('NativeSttAudioTranscribeClient(')));
      expect(content, isNot(contains('mobile_native_stt')));
      expect(
          content, isNot(contains('WindowsNativeSttAudioTranscribeClient(')));
      expect(content, contains('CloudGatewayWhisperAudioTranscribeClient('));
    },
  );
}
