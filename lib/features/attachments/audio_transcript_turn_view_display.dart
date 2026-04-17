import '../audio_transcribe/audio_transcribe_turn_view.dart';

final Expando<_AudioTranscriptTurnViewCacheEntry>
    _audioTranscriptTurnViewCache = Expando<_AudioTranscriptTurnViewCacheEntry>(
  'audio_transcript_turn_view_cache',
);

final class AudioTranscriptTurnViewDisplayText {
  const AudioTranscriptTurnViewDisplayText({
    required this.excerpt,
    required this.full,
  });

  final String excerpt;
  final String full;
}

AudioTranscriptTurnViewDisplayText resolveAudioTranscriptTurnViewDisplayText(
  Map<String, Object?>? payload, {
  int maxChars = 280,
}) {
  final view = resolveAudioTranscriptTurnView(payload);
  if (view == null) {
    return const AudioTranscriptTurnViewDisplayText(excerpt: '', full: '');
  }
  return AudioTranscriptTurnViewDisplayText(
    excerpt: excerptAudioTranscriptTurnView(view, maxChars: maxChars).trim(),
    full: formatAudioTranscriptTurnViewFull(view).trim(),
  );
}

String resolveAudioTranscriptTurnViewDisplayFull(
  Map<String, Object?>? payload,
) {
  return resolveAudioTranscriptTurnViewDisplayText(payload).full;
}

String resolveAudioTranscriptTurnViewDisplayExcerpt(
  Map<String, Object?>? payload, {
  int maxChars = 280,
}) {
  return resolveAudioTranscriptTurnViewDisplayText(
    payload,
    maxChars: maxChars,
  ).excerpt;
}

AudioTranscriptTurnView? resolveAudioTranscriptTurnView(
  Map<String, Object?>? payload,
) {
  if (payload == null) {
    return null;
  }

  final turnsRaw = payload['transcript_turns_v1'];
  final segmentsRaw = payload['transcript_segments'];
  final signature = _fingerprintTurnViewInputs(turnsRaw, segmentsRaw);
  final cached = _audioTranscriptTurnViewCache[payload];
  if (cached != null && cached.signature == signature) {
    return cached.view;
  }

  final persisted = AudioTranscriptTurnView.fromJson(turnsRaw);
  if (persisted != null &&
      persisted.status == AudioTranscriptTurnViewStatus.ok &&
      persisted.turns.isNotEmpty) {
    _audioTranscriptTurnViewCache[payload] =
        _AudioTranscriptTurnViewCacheEntry(signature, persisted);
    return persisted;
  }

  final legacySegments = audioTranscriptTurnSourceSegmentsFromJson(
    segmentsRaw,
  );
  if (legacySegments.isEmpty) {
    _audioTranscriptTurnViewCache[payload] =
        _AudioTranscriptTurnViewCacheEntry(signature, null);
    return null;
  }

  final built = buildAudioTranscriptTurnView(legacySegments);
  if (built.status != AudioTranscriptTurnViewStatus.ok || built.turns.isEmpty) {
    _audioTranscriptTurnViewCache[payload] =
        _AudioTranscriptTurnViewCacheEntry(signature, null);
    return null;
  }
  _audioTranscriptTurnViewCache[payload] = _AudioTranscriptTurnViewCacheEntry(
    signature,
    built,
  );
  return built;
}

int _fingerprintTurnViewInputs(Object? turnsRaw, Object? segmentsRaw) {
  // This is a lightweight cache invalidation fingerprint, not a canonical
  // identity. A rare hash collision is acceptable here to avoid deep compares.
  return Object.hash(
    _fingerprintJsonLike(turnsRaw),
    _fingerprintJsonLike(segmentsRaw),
  );
}

int _fingerprintJsonLike(Object? value) {
  if (value == null) return 0;
  if (value is String || value is num || value is bool) {
    return value.hashCode;
  }
  if (value is List) {
    return Object.hash(
      value.length,
      Object.hashAll(value.map(_fingerprintJsonLike)),
    );
  }
  if (value is Map) {
    final entries = value.entries
        .map(
          (entry) => (
            key: entry.key.toString(),
            value: _fingerprintJsonLike(entry.value),
          ),
        )
        .toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    return Object.hash(
      entries.length,
      Object.hashAll(
        entries.map((entry) => Object.hash(entry.key, entry.value)),
      ),
    );
  }
  return value.hashCode;
}

final class _AudioTranscriptTurnViewCacheEntry {
  const _AudioTranscriptTurnViewCacheEntry(this.signature, this.view);

  final int signature;
  final AudioTranscriptTurnView? view;
}
