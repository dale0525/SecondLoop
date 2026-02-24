part of 'audio_transcribe_runner.dart';

int? _observedGatewayMaxAudioBytes;
Future<void>? _loadObservedGatewayMaxAudioBytesFuture;
Future<int?> Function() _readPersistedGatewayMaxAudioBytes =
    AudioTranscribeGatewayLimitPrefs.read;
Future<void> Function(int value) _writePersistedGatewayMaxAudioBytes =
    AudioTranscribeGatewayLimitPrefs.write;

Future<void> ensureGatewayMaxAudioBytesLoaded() async {
  final pending = _loadObservedGatewayMaxAudioBytesFuture;
  if (pending != null) {
    await pending;
    return;
  }

  final loadFuture = _loadGatewayMaxAudioBytesFromPrefs();
  _loadObservedGatewayMaxAudioBytesFuture = loadFuture;
  try {
    await loadFuture;
  } finally {
    if (identical(_loadObservedGatewayMaxAudioBytesFuture, loadFuture)) {
      _loadObservedGatewayMaxAudioBytesFuture = null;
    }
  }
}

Future<void> _loadGatewayMaxAudioBytesFromPrefs() async {
  try {
    final value = await _readPersistedGatewayMaxAudioBytes();
    if (value != null && value > 0) {
      _observedGatewayMaxAudioBytes = value;
    }
  } catch (_) {
    // Best-effort loading.
  }
}

int _resolveGatewayMaxAudioBytes() {
  final observed = _observedGatewayMaxAudioBytes;
  if (observed != null && observed > 0) {
    return observed;
  }
  return _kAudioTranscribeDefaultMaxInputBytes;
}

void _observeGatewayMaxAudioBytesHeader(String? rawValue) {
  final value = int.tryParse((rawValue ?? '').trim());
  if (value == null || value <= 0) {
    return;
  }
  if (_observedGatewayMaxAudioBytes == value) {
    return;
  }
  _observedGatewayMaxAudioBytes = value;
  unawaited(_persistObservedGatewayMaxAudioBytes(value));
}

Future<void> _persistObservedGatewayMaxAudioBytes(int value) async {
  try {
    await _writePersistedGatewayMaxAudioBytes(value);
  } catch (_) {
    // Best-effort persistence.
  }
}

void _observeGatewayMaxAudioBytesFromHeaders(HttpHeaders headers) {
  _observeGatewayMaxAudioBytesHeader(
    headers.value('x-secondloop-max-audio-bytes'),
  );
}

@visibleForTesting
void observeGatewayMaxAudioBytesHeaderForTest(String? rawValue) {
  _observeGatewayMaxAudioBytesHeader(rawValue);
}

@visibleForTesting
Future<void> ensureGatewayMaxAudioBytesLoadedForTest() {
  return ensureGatewayMaxAudioBytesLoaded();
}

@visibleForTesting
void configureGatewayMaxAudioBytesPersistenceForTest({
  Future<int?> Function()? read,
  Future<void> Function(int value)? write,
}) {
  _readPersistedGatewayMaxAudioBytes =
      read ?? AudioTranscribeGatewayLimitPrefs.read;
  _writePersistedGatewayMaxAudioBytes =
      write ?? AudioTranscribeGatewayLimitPrefs.write;
}

@visibleForTesting
void resetObservedGatewayMaxAudioBytesForTest() {
  _observedGatewayMaxAudioBytes = null;
  _loadObservedGatewayMaxAudioBytesFuture = null;
  _readPersistedGatewayMaxAudioBytes = AudioTranscribeGatewayLimitPrefs.read;
  _writePersistedGatewayMaxAudioBytes = AudioTranscribeGatewayLimitPrefs.write;
}
