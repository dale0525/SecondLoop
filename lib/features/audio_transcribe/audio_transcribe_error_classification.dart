enum AudioTranscribeFailureClass {
  retryable,
  longBackoff,
  terminal,
}

AudioTranscribeFailureClass classifyAudioTranscribeFailure(Object error) {
  final detail = error.toString().trim().toLowerCase();
  if (detail.isEmpty) {
    return AudioTranscribeFailureClass.retryable;
  }

  if (_containsAny(detail, const <String>[
    'audio_transcribe_http_413',
    'payload_too_large',
    'audio_transcribe_payload_too_large_local_check',
    'model_not_allowed',
    'invalid_multipart',
  ])) {
    return AudioTranscribeFailureClass.terminal;
  }

  if (_containsAny(detail, const <String>[
    'audio_transcribe_native_stt_missing_speech_pack',
    'speech_recognizer_unavailable',
    'audio_transcribe_local_runtime_model_missing',
  ])) {
    return AudioTranscribeFailureClass.longBackoff;
  }

  return AudioTranscribeFailureClass.retryable;
}

bool _containsAny(String haystack, List<String> tokens) {
  for (final token in tokens) {
    if (haystack.contains(token)) {
      return true;
    }
  }
  return false;
}
