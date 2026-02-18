import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'audio transcribe client selection keeps runtime fallback and gates native stt by platform',
    () {
      final content = File(
        'lib/core/media_enrichment/media_enrichment_gate_audio_transcribe.dart',
      ).readAsStringSync();

      expect(content, contains('LocalRuntimeAudioTranscribeClient('));
      expect(content, contains('supportsPlatformNativeSttAudioTranscribe()'));
      expect(content, contains('if (supportsNativeStt)'));
      expect(content, contains('NativeSttAudioTranscribeClient('));
      expect(
          content, isNot(contains('WindowsNativeSttAudioTranscribeClient(')));
      expect(content, contains('CloudGatewayWhisperAudioTranscribeClient('));
    },
  );
}
