import '../audio_transcribe/audio_transcribe_turn_view.dart';

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

  final legacySegments = audioTranscriptTurnSourceSegmentsFromJson(
    payload?['transcript_segments'],
  );
  if (legacySegments.isEmpty) return null;

  final built = buildAudioTranscriptTurnView(legacySegments);
  if (built.status != AudioTranscriptTurnViewStatus.ok || built.turns.isEmpty) {
    return null;
  }
  return built;
}
