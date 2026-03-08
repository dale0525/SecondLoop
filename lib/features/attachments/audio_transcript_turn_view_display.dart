import '../audio_transcribe/audio_transcribe_turn_view.dart';

final Expando<_AudioTranscriptTurnViewCacheEntry>
    _audioTranscriptTurnViewCache = Expando<_AudioTranscriptTurnViewCacheEntry>(
  'audio_transcript_turn_view_cache',
);

String resolveAudioTranscriptTurnViewDisplayFull(
  Map<String, Object?>? payload,
) {
  final view = _resolveAudioTranscriptTurnView(payload);
  if (view == null) return '';
  return formatAudioTranscriptTurnViewFull(view).trim();
}

String resolveAudioTranscriptTurnViewDisplayExcerpt(
  Map<String, Object?>? payload, {
  int maxChars = 280,
}) {
  final view = _resolveAudioTranscriptTurnView(payload);
  if (view == null) return '';
  return excerptAudioTranscriptTurnView(view, maxChars: maxChars).trim();
}

AudioTranscriptTurnView? _resolveAudioTranscriptTurnView(
  Map<String, Object?>? payload,
) {
  final persisted = AudioTranscriptTurnView.fromJson(
    payload?['transcript_turns_v1'],
  );
  if (persisted != null &&
      persisted.status == AudioTranscriptTurnViewStatus.ok &&
      persisted.turns.isNotEmpty) {
    return persisted;
  }

  if (payload == null) {
    return null;
  }

  final cached = _audioTranscriptTurnViewCache[payload];
  if (cached != null) {
    return cached.view;
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
