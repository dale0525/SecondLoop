import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/content_enrichment/audio_transcribe_failure_reason.dart';

void main() {
  test('detectAudioTranscribeFailureReasonToken recognizes canonical tokens',
      () {
    expect(
      detectAudioTranscribeFailureReasonToken(
        'audio_transcribe_native_stt_failed:speech_permission_denied',
      ),
      kAudioTranscribeFailureSpeechPermissionDenied,
    );
    expect(
      detectAudioTranscribeFailureReasonToken(
        'audio_transcribe_native_stt_failed:speech_permission_not_determined',
      ),
      kAudioTranscribeFailureSpeechPermissionNotDetermined,
    );
    expect(
      detectAudioTranscribeFailureReasonToken('speech_service_disabled'),
      kAudioTranscribeFailureSpeechServiceDisabled,
    );
    expect(
      detectAudioTranscribeFailureReasonToken('speech_offline_unavailable'),
      kAudioTranscribeFailureSpeechOfflineUnavailable,
    );
    expect(
      detectAudioTranscribeFailureReasonToken('speech_runtime_unavailable'),
      kAudioTranscribeFailureSpeechRuntimeUnavailable,
    );
  });

  test(
      'detectAudioTranscribeFailureReasonToken recognizes legacy speech tokens',
      () {
    expect(
      detectAudioTranscribeFailureReasonToken(
        'audio_transcribe_native_stt_failed:speech_authorization_denied',
      ),
      kAudioTranscribeFailureSpeechPermissionDenied,
    );
    expect(
      detectAudioTranscribeFailureReasonToken(
          'speech_authorization_restricted'),
      kAudioTranscribeFailureSpeechPermissionRestricted,
    );
    expect(
      detectAudioTranscribeFailureReasonToken(
        'audio_transcribe_native_stt_failed:speech_authorization_not_determined',
      ),
      kAudioTranscribeFailureSpeechPermissionNotDetermined,
    );
    expect(
      detectAudioTranscribeFailureReasonToken(
        'audio_transcribe_native_stt_failed:on-device recognition is not available',
      ),
      kAudioTranscribeFailureSpeechOfflineUnavailable,
    );
    expect(
      detectAudioTranscribeFailureReasonToken('speech_recognizer_unavailable'),
      kAudioTranscribeFailureSpeechRuntimeUnavailable,
    );
  });

  test(
      'detectAudioTranscribeFailureReasonToken recognizes Siri and Dictation disabled text',
      () {
    expect(
      detectAudioTranscribeFailureReasonToken(
        'Bad state: audio_transcribe_local_runtime_failed:local_runtime_failed:Siri and Dictation are disabled',
      ),
      kAudioTranscribeFailureSpeechServiceDisabled,
    );
  });

  test(
      'shouldOpenAudioTranscribeSystemSettings only for recoverable permission states',
      () {
    expect(
      shouldOpenAudioTranscribeSystemSettings(
        kAudioTranscribeFailureSpeechPermissionDenied,
      ),
      isTrue,
    );
    expect(
      shouldOpenAudioTranscribeSystemSettings(
        kAudioTranscribeFailureSpeechPermissionRestricted,
      ),
      isTrue,
    );
    expect(
      shouldOpenAudioTranscribeSystemSettings(
        kAudioTranscribeFailureSpeechServiceDisabled,
      ),
      isTrue,
    );
    expect(
      shouldOpenAudioTranscribeSystemSettings(
        kAudioTranscribeFailureSpeechPermissionNotDetermined,
      ),
      isFalse,
    );
    expect(
      shouldOpenAudioTranscribeSystemSettings(
        kAudioTranscribeFailureSpeechOfflineUnavailable,
      ),
      isFalse,
    );
    expect(
      shouldOpenAudioTranscribeSystemSettings(
        kAudioTranscribeFailureSpeechRuntimeUnavailable,
      ),
      isFalse,
    );
    expect(shouldOpenAudioTranscribeSystemSettings('unknown_error'), isFalse);
  });
}
