part of 'media_enrichment_gate.dart';

String _autoPdfOcrStatusFromPayload(Map<String, Object?>? payload) {
  return (payload?['ocr_auto_status'] ?? '').toString().trim().toLowerCase();
}

bool shouldNotifyAutoPdfOcrStatusTransition({
  required Map<String, Object?>? previousPayload,
  required Map<String, Object?> nextPayload,
}) {
  final previousStatus = _autoPdfOcrStatusFromPayload(previousPayload);
  final nextStatus = _autoPdfOcrStatusFromPayload(nextPayload);
  if (nextStatus.isEmpty || previousStatus == nextStatus) {
    return false;
  }
  if (nextStatus == 'running') return true;
  if (previousStatus == 'running' &&
      (nextStatus == 'ok' || nextStatus == 'failed')) {
    return true;
  }
  return false;
}

String _firstNonEmptyForAutoOcr(List<String> values) {
  for (final raw in values) {
    final value = raw.trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _joinNonEmptyBlocksForAutoOcr(List<String> parts) {
  final values = parts
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (values.isEmpty) return '';
  return values.join('\n\n');
}

String _truncateUtf8ForAutoOcr(String text, int maxBytes) {
  final bytes = utf8.encode(text);
  if (bytes.length <= maxBytes) return text;
  if (maxBytes <= 0) return '';
  var end = maxBytes;
  while (end > 0 && (bytes[end - 1] & 0xC0) == 0x80) {
    end -= 1;
  }
  if (end <= 0) return '';
  return utf8.decode(bytes.sublist(0, end), allowMalformed: true);
}

String _dominantStringForAutoOcr(List<String> values) {
  if (values.isEmpty) return '';
  final counts = <String, int>{};
  for (final value in values) {
    counts.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  String winner = '';
  var bestCount = -1;
  counts.forEach((value, count) {
    if (count > bestCount) {
      winner = value;
      bestCount = count;
    }
  });
  return winner;
}

Future<VideoKeyframeOcrResult?> _loadManifestKeyframeOcrForAutoOcr({
  required NativeAppBackend backend,
  required Uint8List sessionKey,
  required ParsedVideoManifest manifest,
  required String languageHints,
  required List<VideoManifestPreviewRef> ocrKeyframes,
}) async {
  final keyframeImages = <VideoManifestKeyframeImage>[];
  for (final frame in manifest.keyframes) {
    final frameBytes = await backend.readAttachmentBytes(
      sessionKey,
      sha256: frame.sha256,
    );
    if (frameBytes.isEmpty) continue;
    keyframeImages
        .add(VideoManifestKeyframeImage(frame: frame, bytes: frameBytes));
  }
  if (keyframeImages.isEmpty) return null;
  ocrKeyframes
    ..clear()
    ..addAll(keyframeImages.map((item) => item.frame));
  return VideoKeyframeOcrWorker.runOnManifestKeyframes(
    keyframeImages,
    languageHints: languageHints,
  );
}

Map<String, Object?> buildAutoPdfOcrSuccessPayload({
  required Map<String, Object?> runningPayload,
  required Map<String, Object?> sourcePayload,
  required PlatformPdfOcrResult ocr,
  required String languageHints,
  required int dpi,
  required int nowMs,
}) {
  final extractedFull = (sourcePayload['extracted_text_full'] ?? '').toString();
  final extractedExcerpt =
      (sourcePayload['extracted_text_excerpt'] ?? '').toString();
  final preferredOcr = maybePreferExtractedTextForRuntimeOcr(
    ocr: ocr,
    extractedFull: extractedFull,
    extractedExcerpt: extractedExcerpt,
  );
  final extractedText =
      (extractedExcerpt.trim().isNotEmpty ? extractedExcerpt : extractedFull)
          .trim();
  final completedRanges = _normalizedPageRangesForAutoPdf(
    preferredOcr.completedRanges,
  );
  final failedRanges = _normalizedPageRangesForAutoPdf(
    preferredOcr.failedRanges,
  );
  final normalizedPageCount = preferredOcr.pageCount > 0
      ? preferredOcr.pageCount
      : _MediaEnrichmentGateState._asInt(sourcePayload['page_count']);
  final normalizedProcessedPages = preferredOcr.processedPages > 0
      ? preferredOcr.processedPages
      : _MediaEnrichmentGateState._asInt(sourcePayload['ocr_processed_pages']);
  if (completedRanges.isEmpty && normalizedProcessedPages > 0) {
    completedRanges.add(
      <String, int>{
        'start_page': 1,
        'end_page': normalizedProcessedPages,
      },
    );
  }
  if (failedRanges.isEmpty &&
      normalizedPageCount > 0 &&
      normalizedProcessedPages > 0 &&
      normalizedProcessedPages < normalizedPageCount) {
    failedRanges.add(
      <String, int>{
        'start_page': normalizedProcessedPages + 1,
        'end_page': normalizedPageCount,
      },
    );
  }

  final isPartial = preferredOcr.partial || failedRanges.isNotEmpty;
  final isRetryable =
      preferredOcr.retryable || (isPartial && failedRanges.isNotEmpty);
  final updatedPayload = Map<String, Object?>.from(runningPayload);
  updatedPayload.remove('ocr_auto_running_ms');
  updatedPayload['needs_ocr'] = isPartial ||
      (preferredOcr.fullText.trim().isEmpty && extractedText.isEmpty);
  updatedPayload['ocr_text_full'] = preferredOcr.fullText;
  updatedPayload['ocr_text_excerpt'] = preferredOcr.excerpt;
  updatedPayload['ocr_engine'] = preferredOcr.engine;
  updatedPayload['ocr_lang_hints'] = languageHints;
  updatedPayload['ocr_dpi'] = dpi;
  updatedPayload['ocr_retry_attempted'] = preferredOcr.retryAttempted;
  updatedPayload['ocr_retry_attempts'] = preferredOcr.retryAttempts;
  updatedPayload['ocr_retry_hints'] = preferredOcr.retryHintsTried.join(',');
  updatedPayload['ocr_is_truncated'] = preferredOcr.isTruncated || isPartial;
  updatedPayload['ocr_page_count'] = normalizedPageCount;
  updatedPayload['ocr_processed_pages'] = normalizedProcessedPages;
  updatedPayload['ocr_partial'] = isPartial;
  updatedPayload['ocr_retryable'] = isRetryable;
  if (isPartial) {
    updatedPayload['ocr_failed_ranges'] = failedRanges;
    updatedPayload['ocr_completed_ranges'] = completedRanges;
  } else {
    updatedPayload.remove('ocr_failed_ranges');
    updatedPayload.remove('ocr_completed_ranges');
  }
  updatedPayload['ocr_auto_status'] = 'ok';
  updatedPayload['ocr_auto_last_success_ms'] = nowMs;
  updatedPayload.remove('ocr_auto_last_failure_ms');
  return updatedPayload;
}

List<Map<String, int>> _normalizedPageRangesForAutoPdf(
  List<Map<String, int>> ranges,
) {
  final output = <Map<String, int>>[];
  for (final range in ranges) {
    final start = _MediaEnrichmentGateState._asInt(range['start_page']);
    final end = _MediaEnrichmentGateState._asInt(range['end_page']);
    if (start <= 0 || end <= 0 || end < start) continue;
    output.add(
      <String, int>{
        'start_page': start,
        'end_page': end,
      },
    );
  }
  return output;
}
