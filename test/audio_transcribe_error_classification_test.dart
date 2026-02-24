import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/audio_transcribe/audio_transcribe_error_classification.dart';

void main() {
  group('classifyAudioTranscribeFailure', () {
    test('classifies payload_too_large as terminal', () {
      final klass = classifyAudioTranscribeFailure(
        StateError('audio_transcribe_http_413:{"error":"payload_too_large"}'),
      );
      expect(klass, AudioTranscribeFailureClass.terminal);
    });

    test('classifies model_not_allowed as terminal', () {
      final klass = classifyAudioTranscribeFailure(
        StateError('audio_transcribe_http_400:{"error":"model_not_allowed"}'),
      );
      expect(klass, AudioTranscribeFailureClass.terminal);
    });

    test('classifies invalid_multipart as terminal', () {
      final klass = classifyAudioTranscribeFailure(
        StateError('audio_transcribe_http_400:{"error":"invalid_multipart"}'),
      );
      expect(klass, AudioTranscribeFailureClass.terminal);
    });

    test('classifies speech recognizer unavailable as longBackoff', () {
      final klass = classifyAudioTranscribeFailure(
        StateError('speech_recognizer_unavailable'),
      );
      expect(klass, AudioTranscribeFailureClass.longBackoff);
    });

    test('classifies local runtime model missing as longBackoff', () {
      final klass = classifyAudioTranscribeFailure(
        StateError('audio_transcribe_local_runtime_model_missing:base'),
      );
      expect(klass, AudioTranscribeFailureClass.longBackoff);
    });

    test('classifies network timeout as retryable', () {
      final klass = classifyAudioTranscribeFailure(
        StateError('socket timeout while calling gateway'),
      );
      expect(klass, AudioTranscribeFailureClass.retryable);
    });
  });
}
