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

  final cached = _audioTranscriptTurnViewCache[payload];
  if (cached != null) {
    return cached.view;
  }

  final persisted = AudioTranscriptTurnView.fromJson(
    payload['transcript_turns_v1'],
  );
  if (persisted != null &&
      persisted.status == AudioTranscriptTurnViewStatus.ok &&
      persisted.turns.isNotEmpty) {
    _audioTranscriptTurnViewCache[payload] =
        _AudioTranscriptTurnViewCacheEntry(persisted);
    return persisted;
  }

  final legacySegments = audioTranscriptTurnSourceSegmentsFromJson(
    payload['transcript_segments'],
  );
  if (legacySegments.isEmpty) {
    _audioTranscriptTurnViewCache[payload] =
        const _AudioTranscriptTurnViewCacheEntry(null);
    return null;
  }

  final built = buildAudioTranscriptTurnView(legacySegments);
  if (built.status != AudioTranscriptTurnViewStatus.ok || built.turns.isEmpty) {
    _audioTranscriptTurnViewCache[payload] =
        const _AudioTranscriptTurnViewCacheEntry(null);
    return null;
  }
  _audioTranscriptTurnViewCache[payload] = _AudioTranscriptTurnViewCacheEntry(
    built,
  );
  return built;
}

final class _AudioTranscriptTurnViewCacheEntry {
  const _AudioTranscriptTurnViewCacheEntry(this.view);

  final AudioTranscriptTurnView? view;
}
