import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audio transcribe client selection no longer uses native stt fallback',
      () {
    final content = File(
      'lib/core/media_enrichment/media_enrichment_gate_audio_transcribe.dart',
    ).readAsStringSync();

    expect(content, isNot(contains('NativeSttAudioTranscribeClient(')));
    expect(content, isNot(contains('WindowsNativeSttAudioTranscribeClient(')));
    expect(content, isNot(contains('LocalRuntimeAudioTranscribeClient(')));
    expect(content, contains('CloudGatewayWhisperAudioTranscribeClient('));
  });
}
