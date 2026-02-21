part of 'media_enrichment_gate.dart';

String _normalizeAutoOcrPayloadText(Object? raw) {
  if (raw == null) return '';
  final value = raw.toString().trim();
  if (value.toLowerCase() == 'null') return '';
  return value;
}

bool _looksLikeStaleAutoVideoReadableField({
  required String candidate,
  required String oldReadableFull,
  required String oldReadableExcerpt,
}) {
  final normalizedCandidate = candidate.trim();
  if (normalizedCandidate.isEmpty) return false;
  final normalizedFull = oldReadableFull.trim();
  final normalizedExcerpt = oldReadableExcerpt.trim();
  return normalizedCandidate == normalizedFull ||
      normalizedCandidate == normalizedExcerpt;
}

@visibleForTesting
Map<String, Object?>? buildVideoManifestTranscriptBackfillPayload({
  required Map<String, Object?> currentPayload,
  required String transcriptFull,
  required String transcriptExcerpt,
}) {
  final normalizedTranscriptFull = transcriptFull.trim();
  final normalizedTranscriptExcerptRaw = transcriptExcerpt.trim();
  final normalizedTranscriptExcerpt = normalizedTranscriptExcerptRaw.isNotEmpty
      ? normalizedTranscriptExcerptRaw
      : _truncateUtf8ForAutoOcr(normalizedTranscriptFull, 8 * 1024);
  if (normalizedTranscriptFull.isEmpty && normalizedTranscriptExcerpt.isEmpty) {
    return null;
  }

  final currentTranscriptFull =
      _normalizeAutoOcrPayloadText(currentPayload['transcript_full']);
  final currentTranscriptExcerpt =
      _normalizeAutoOcrPayloadText(currentPayload['transcript_excerpt']);
  final currentOcrFull =
      _normalizeAutoOcrPayloadText(currentPayload['ocr_text_full']);
  final currentOcrExcerpt =
      _normalizeAutoOcrPayloadText(currentPayload['ocr_text_excerpt']);

  final oldReadableFull =
      _normalizeAutoOcrPayloadText(currentPayload['readable_text_full']);
  final oldReadableExcerpt =
      _normalizeAutoOcrPayloadText(currentPayload['readable_text_excerpt']);
  final nextReadableFull = _joinNonEmptyBlocksForAutoOcr([
    normalizedTranscriptFull,
    currentOcrFull,
  ]);
  final nextReadableExcerpt = _joinNonEmptyBlocksForAutoOcr([
    normalizedTranscriptExcerpt,
    currentOcrExcerpt,
  ]);

  final oldSummary =
      _normalizeAutoOcrPayloadText(currentPayload['video_summary']);
  final oldFallbackSummary = buildVideoSummaryText(
    oldReadableExcerpt.isNotEmpty ? oldReadableExcerpt : oldReadableFull,
    maxBytes: 2048,
  );
  final nextSummary = buildVideoSummaryText(
    nextReadableExcerpt.isNotEmpty ? nextReadableExcerpt : nextReadableFull,
    maxBytes: 2048,
  );

  final next = Map<String, Object?>.from(currentPayload);
  var changed = false;

  void setOrRemove(String key, String value) {
    final normalizedValue = value.trim();
    final currentValue = _normalizeAutoOcrPayloadText(next[key]);
    if (normalizedValue.isEmpty) {
      if (!next.containsKey(key)) return;
      next.remove(key);
      changed = true;
      return;
    }
    if (currentValue == normalizedValue) return;
    next[key] = normalizedValue;
    changed = true;
  }

  setOrRemove('transcript_full', normalizedTranscriptFull);
  setOrRemove('transcript_excerpt', normalizedTranscriptExcerpt);
  setOrRemove('readable_text_full', nextReadableFull);
  setOrRemove('readable_text_excerpt', nextReadableExcerpt);

  final currentVideoDescriptionFull =
      _normalizeAutoOcrPayloadText(next['video_description_full']);
  if (_looksLikeStaleAutoVideoReadableField(
    candidate: currentVideoDescriptionFull,
    oldReadableFull: oldReadableFull,
    oldReadableExcerpt: oldReadableExcerpt,
  )) {
    setOrRemove('video_description_full', nextReadableFull);
  }

  final currentVideoDescriptionExcerpt =
      _normalizeAutoOcrPayloadText(next['video_description_excerpt']);
  if (_looksLikeStaleAutoVideoReadableField(
    candidate: currentVideoDescriptionExcerpt,
    oldReadableFull: oldReadableFull,
    oldReadableExcerpt: oldReadableExcerpt,
  )) {
    setOrRemove('video_description_excerpt', nextReadableExcerpt);
  }

  final currentKnowledgeMarkdownFull =
      _normalizeAutoOcrPayloadText(next['knowledge_markdown_full']);
  if (_looksLikeStaleAutoVideoReadableField(
    candidate: currentKnowledgeMarkdownFull,
    oldReadableFull: oldReadableFull,
    oldReadableExcerpt: oldReadableExcerpt,
  )) {
    setOrRemove('knowledge_markdown_full', nextReadableFull);
  }

  final currentKnowledgeMarkdownExcerpt =
      _normalizeAutoOcrPayloadText(next['knowledge_markdown_excerpt']);
  if (_looksLikeStaleAutoVideoReadableField(
    candidate: currentKnowledgeMarkdownExcerpt,
    oldReadableFull: oldReadableFull,
    oldReadableExcerpt: oldReadableExcerpt,
  )) {
    setOrRemove('knowledge_markdown_excerpt', nextReadableExcerpt);
  }

  if (oldSummary.isEmpty || oldSummary == oldFallbackSummary) {
    setOrRemove('video_summary', nextSummary);
  }

  final transcriptChanged = currentTranscriptFull != normalizedTranscriptFull ||
      currentTranscriptExcerpt != normalizedTranscriptExcerpt;
  if (!transcriptChanged &&
      nextReadableFull == oldReadableFull &&
      nextReadableExcerpt == oldReadableExcerpt) {
    return null;
  }
  if (!changed) {
    return null;
  }

  return next;
}

extension _MediaEnrichmentGateVideoTranscriptBackfill
    on _MediaEnrichmentGateState {
  Future<int> _backfillVideoManifestTranscriptForRecentAttachments({
    required NativeAppBackend backend,
    required Uint8List sessionKey,
  }) async {
    final recent = await backend.listRecentAttachments(sessionKey, limit: 80);
    var updated = 0;

    for (final attachment in recent) {
      final mime = attachment.mimeType.trim().toLowerCase();
      if (mime != kSecondLoopVideoManifestMimeType) continue;

      final payloadJson = await backend.readAttachmentAnnotationPayloadJson(
        sessionKey,
        sha256: attachment.sha256,
      );
      final payload =
          _MediaEnrichmentGateState._decodePayloadObject(payloadJson);
      if (payload == null) continue;

      final schema =
          _normalizeAutoOcrPayloadText(payload['schema']).toLowerCase();
      if (schema != 'secondloop.video_extract.v1') continue;

      final ocrEngine = _normalizeAutoOcrPayloadText(payload['ocr_engine']);
      if (ocrEngine.isEmpty) continue;

      final audioSha256 = _normalizeAutoOcrPayloadText(payload['audio_sha256']);
      if (audioSha256.isEmpty) continue;

      final linkedAudioPayloadJson =
          await backend.readAttachmentAnnotationPayloadJson(
        sessionKey,
        sha256: audioSha256,
      );
      final linkedAudioPayload = _MediaEnrichmentGateState._decodePayloadObject(
        linkedAudioPayloadJson,
      );
      if (linkedAudioPayload == null) continue;

      final transcriptSeed = resolveVideoManifestTranscriptSeed(
        runningPayload: payload,
        audioSha256: audioSha256,
        audioMimeType: _normalizeAutoOcrPayloadText(payload['audio_mime_type']),
        linkedAudioPayload: linkedAudioPayload,
        allowDeferForMissingLinkedAudio: false,
      );

      final nextPayload = buildVideoManifestTranscriptBackfillPayload(
        currentPayload: payload,
        transcriptFull: transcriptSeed.transcriptFull,
        transcriptExcerpt: transcriptSeed.transcriptExcerpt,
      );
      if (nextPayload == null) continue;

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await backend.markAttachmentAnnotationOkJson(
        sessionKey,
        attachmentSha256: attachment.sha256,
        lang: 'und',
        modelName: 'video_extract.v1',
        payloadJson: jsonEncode(nextPayload),
        nowMs: nowMs,
      );
      updated += 1;
    }

    return updated;
  }
}
