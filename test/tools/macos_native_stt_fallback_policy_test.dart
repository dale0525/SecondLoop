import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macos native stt fallback is opt-in via dart-define', () {
    final content = File(
      'lib/core/media_enrichment/media_enrichment_gate_audio_transcribe.dart',
    ).readAsStringSync();

    expect(
      content,
      contains('SECONDLOOP_ENABLE_MACOS_NATIVE_STT_FALLBACK'),
    );
    expect(content, contains('bool.fromEnvironment'));

    final gateIndex = content.indexOf('if (!_kEnableMacosNativeSttFallback)');
    final clientIndex = content.indexOf('NativeSttAudioTranscribeClient(');
    expect(gateIndex, greaterThanOrEqualTo(0));
    expect(clientIndex, greaterThan(gateIndex));
  });
}
