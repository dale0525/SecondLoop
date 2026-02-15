import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macos speech fallback is opt-in via dart-define', () {
    final content = File(
      'lib/core/media_enrichment/media_enrichment_gate_audio_transcribe.dart',
    ).readAsStringSync();

    expect(
      content,
      contains('SECONDLOOP_ENABLE_MACOS_NATIVE_STT_FALLBACK'),
    );
    expect(content, contains('bool.fromEnvironment'));
    expect(content, contains('bool _shouldEnableMacosSpeechFallback()'));
    expect(content, contains('if (!_shouldEnableMacosSpeechFallback())'));

    final gateIndex =
        content.indexOf('if (!_shouldEnableMacosSpeechFallback())');
    final nativeClientIndex =
        content.indexOf('NativeSttAudioTranscribeClient(');
    expect(gateIndex, greaterThanOrEqualTo(0));
    expect(nativeClientIndex, greaterThan(gateIndex));
  });

  test('macos local runtime fallback remains enabled independently', () {
    final content = File(
      'lib/core/media_enrichment/media_enrichment_gate_audio_transcribe.dart',
    ).readAsStringSync();

    expect(content, contains('if (shouldEnableLocalFallback)'));
    expect(content, isNot(contains('shouldEnableLocalRuntimeFallback')));

    final localRuntimeGateIndex =
        content.indexOf('if (shouldEnableLocalFallback)');
    final localRuntimeClientIndex =
        content.indexOf('LocalRuntimeAudioTranscribeClient(');

    expect(localRuntimeGateIndex, greaterThanOrEqualTo(0));
    expect(localRuntimeClientIndex, greaterThan(localRuntimeGateIndex));
  });
}
