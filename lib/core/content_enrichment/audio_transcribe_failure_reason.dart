const String kAudioTranscribeFailureSpeechPermissionDenied =
    'speech_permission_denied';
const String kAudioTranscribeFailureSpeechPermissionRestricted =
    'speech_permission_restricted';
const String kAudioTranscribeFailureSpeechPermissionNotDetermined =
    'speech_permission_not_determined';
const String kAudioTranscribeFailureSpeechServiceDisabled =
    'speech_service_disabled';
const String kAudioTranscribeFailureSpeechOfflineUnavailable =
    'speech_offline_unavailable';
const String kAudioTranscribeFailureSpeechRuntimeUnavailable =
    'speech_runtime_unavailable';

String? detectAudioTranscribeFailureReasonToken(Object? rawError) {
  final raw = (rawError ?? '').toString().trim();
  if (raw.isEmpty) return null;

  final lower = raw.toLowerCase();

  if (_containsAny(lower, const <String>[
    'speech_permission_denied',
    'speech_authorization_denied',
  ])) {
    return kAudioTranscribeFailureSpeechPermissionDenied;
  }

  if (_containsAny(lower, const <String>[
    'speech_permission_restricted',
    'speech_authorization_restricted',
  ])) {
    return kAudioTranscribeFailureSpeechPermissionRestricted;
  }

  if (_containsAny(lower, const <String>[
    'speech_permission_not_determined',
    'speech_authorization_not_determined',
    'speech_permission_request_required',
  ])) {
    return kAudioTranscribeFailureSpeechPermissionNotDetermined;
  }

  if (_containsAny(lower, const <String>[
    'speech_service_disabled',
    'speech_service_not_enabled',
  ])) {
    return kAudioTranscribeFailureSpeechServiceDisabled;
  }

  if (lower.contains('siri') &&
      lower.contains('dictation') &&
      _containsAny(lower, const <String>['disable', 'disabled'])) {
    return kAudioTranscribeFailureSpeechServiceDisabled;
  }

  if (_containsAny(lower, const <String>[
    'speech_offline_unavailable',
    'speech_on_device_unavailable',
    'speech_recognizer_offline_unavailable',
    'offline model not available',
    'on-device recognition is not available',
  ])) {
    return kAudioTranscribeFailureSpeechOfflineUnavailable;
  }

  if (_containsAny(lower, const <String>[
    'speech_runtime_unavailable',
    'speech_recognizer_unavailable',
  ])) {
    return kAudioTranscribeFailureSpeechRuntimeUnavailable;
  }

  return null;
}

bool shouldOpenAudioTranscribeSystemSettings(Object? rawError) {
  final reason = detectAudioTranscribeFailureReasonToken(rawError);
  if (reason == null) return false;

  return reason == kAudioTranscribeFailureSpeechPermissionDenied ||
      reason == kAudioTranscribeFailureSpeechPermissionRestricted ||
      reason == kAudioTranscribeFailureSpeechServiceDisabled;
}

bool _containsAny(String haystack, List<String> needles) {
  for (final needle in needles) {
    if (haystack.contains(needle)) {
      return true;
    }
  }
  return false;
}
