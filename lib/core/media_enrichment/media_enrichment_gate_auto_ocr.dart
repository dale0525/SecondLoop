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

extension _MediaEnrichmentGateAutoOcr on _MediaEnrichmentGateState {
  Future<int> _runAutoPdfOcrForRecentScannedPdfs({
    required NativeAppBackend backend,
    required Uint8List sessionKey,
    required ContentEnrichmentConfig? contentConfig,
    required Future<PlatformPdfOcrResult?> Function(
      Uint8List bytes, {
      required int pageCount,
    }) runMultimodalPdfOcr,
    VoidCallback? onAutoPdfOcrStatusChanged,
  }) async {
    if (!(contentConfig?.ocrEnabled ?? true)) return 0;
    const autoMaxPages = 0;
    const hardMaxPages = 10000;
    const dpi = 180;
    final configuredHints = contentConfig?.ocrLanguageHints.trim() ?? '';
    final languageHints =
        configuredHints.isEmpty ? 'device_plus_en' : configuredHints;

    final recent = await backend.listRecentAttachments(sessionKey, limit: 80);
    var updated = 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final attachment in recent) {
      final mime = attachment.mimeType.trim().toLowerCase();
      if (mime != 'application/pdf') continue;
      if (_autoOcrCompletedShas.contains(attachment.sha256)) continue;

      final payloadJson = await backend.readAttachmentAnnotationPayloadJson(
        sessionKey,
        sha256: attachment.sha256,
      );
      final payload =
          _MediaEnrichmentGateState._decodePayloadObject(payloadJson);
      if (payload == null) continue;
      if (!shouldAutoRunPdfOcr(
        payload,
        autoMaxPages: autoMaxPages,
        nowMs: now,
      )) {
        continue;
      }

      final pageCount = _MediaEnrichmentGateState._asInt(payload['page_count']);
      if (pageCount <= 0) continue;

      const runMaxPages = hardMaxPages;
      final attemptMs = DateTime.now().millisecondsSinceEpoch;
      final retryCount =
          _MediaEnrichmentGateState._asInt(payload['ocr_auto_retry_count']);

      Future<void> persistPayload(Map<String, Object?> next, int ts) async {
        await backend.markAttachmentAnnotationOkJson(
          sessionKey,
          attachmentSha256: attachment.sha256,
          lang: 'und',
          modelName: 'document_extract.v1',
          payloadJson: jsonEncode(next),
          nowMs: ts,
        );
      }

      void notifyStatusTransition(
        Map<String, Object?> previousPayload,
        Map<String, Object?> nextPayload,
      ) {
        if (onAutoPdfOcrStatusChanged == null) return;
        if (!shouldNotifyAutoPdfOcrStatusTransition(
          previousPayload: previousPayload,
          nextPayload: nextPayload,
        )) {
          return;
        }
        onAutoPdfOcrStatusChanged();
      }

      try {
        final runningPayload = Map<String, Object?>.from(payload);
        runningPayload['ocr_auto_status'] = 'running';
        runningPayload['ocr_auto_running_ms'] = attemptMs;
        runningPayload['ocr_auto_last_attempt_ms'] = attemptMs;
        runningPayload['ocr_auto_attempted_ms'] = attemptMs;
        runningPayload['ocr_auto_retry_count'] = retryCount;
        await persistPayload(runningPayload, attemptMs);
        notifyStatusTransition(payload, runningPayload);

        final bytes = await backend.readAttachmentBytes(
          sessionKey,
          sha256: attachment.sha256,
        );
        if (bytes.isEmpty) {
          final failedPayload = Map<String, Object?>.from(runningPayload);
          failedPayload.remove('ocr_auto_running_ms');
          failedPayload['ocr_auto_status'] = 'failed';
          failedPayload['ocr_auto_last_failure_ms'] =
              DateTime.now().millisecondsSinceEpoch;
          failedPayload['ocr_auto_retry_count'] = retryCount + 1;
          await persistPayload(
            failedPayload,
            failedPayload['ocr_auto_last_failure_ms'] as int,
          );
          notifyStatusTransition(runningPayload, failedPayload);
          continue;
        }

        final ocr = await runMultimodalPdfOcr(bytes, pageCount: pageCount) ??
            await PlatformPdfOcr.tryOcrPdfBytes(
              bytes,
              maxPages: runMaxPages,
              dpi: dpi,
              languageHints: languageHints,
            );

        final updatedPayload = Map<String, Object?>.from(runningPayload);
        updatedPayload.remove('ocr_auto_running_ms');
        if (ocr != null) {
          final extractedFull =
              (payload['extracted_text_full'] ?? '').toString();
          final extractedExcerpt =
              (payload['extracted_text_excerpt'] ?? '').toString();
          final preferredOcr = maybePreferExtractedTextForRuntimeOcr(
            ocr: ocr,
            extractedFull: extractedFull,
            extractedExcerpt: extractedExcerpt,
          );
          final extractedText = (extractedExcerpt.trim().isNotEmpty
                  ? extractedExcerpt
                  : extractedFull)
              .trim();
          updatedPayload['needs_ocr'] =
              preferredOcr.fullText.trim().isEmpty && extractedText.isEmpty;
          updatedPayload['ocr_text_full'] = preferredOcr.fullText;
          updatedPayload['ocr_text_excerpt'] = preferredOcr.excerpt;
          updatedPayload['ocr_engine'] = preferredOcr.engine;
          updatedPayload['ocr_lang_hints'] = languageHints;
          updatedPayload['ocr_dpi'] = dpi;
          updatedPayload['ocr_retry_attempted'] = preferredOcr.retryAttempted;
          updatedPayload['ocr_retry_attempts'] = preferredOcr.retryAttempts;
          updatedPayload['ocr_retry_hints'] =
              preferredOcr.retryHintsTried.join(',');
          updatedPayload['ocr_is_truncated'] = preferredOcr.isTruncated;
          updatedPayload['ocr_page_count'] = preferredOcr.pageCount;
          updatedPayload['ocr_processed_pages'] = preferredOcr.processedPages;
          updatedPayload['ocr_auto_status'] = 'ok';
          updatedPayload['ocr_auto_last_success_ms'] =
              DateTime.now().millisecondsSinceEpoch;
          updatedPayload.remove('ocr_auto_last_failure_ms');
          await persistPayload(
            updatedPayload,
            updatedPayload['ocr_auto_last_success_ms'] as int,
          );
          _autoOcrCompletedShas.add(attachment.sha256);
          updated += 1;
        } else {
          updatedPayload['ocr_auto_status'] = 'failed';
          updatedPayload['ocr_auto_last_failure_ms'] =
              DateTime.now().millisecondsSinceEpoch;
          updatedPayload['ocr_auto_retry_count'] = retryCount + 1;
          await persistPayload(
            updatedPayload,
            updatedPayload['ocr_auto_last_failure_ms'] as int,
          );
        }
      } catch (_) {
        final failedPayload = Map<String, Object?>.from(payload);
        failedPayload.remove('ocr_auto_running_ms');
        failedPayload['ocr_auto_status'] = 'failed';
        failedPayload['ocr_auto_last_failure_ms'] =
            DateTime.now().millisecondsSinceEpoch;
        failedPayload['ocr_auto_retry_count'] = retryCount + 1;
        try {
          await persistPayload(
            failedPayload,
            failedPayload['ocr_auto_last_failure_ms'] as int,
          );
        } catch (_) {
          // ignore per-attachment status persistence failures.
        }
      }
    }

    return updated;
  }

  Future<int> _runAutoDocxOcrForRecentOfficeDocs({
    required NativeAppBackend backend,
    required Uint8List sessionKey,
    required ContentEnrichmentConfig? contentConfig,
    required Future<PlatformPdfOcrResult?> Function(
      Uint8List bytes, {
      required int pageCount,
      required String languageHints,
    }) runDocxOcr,
  }) async {
    if (!(contentConfig?.ocrEnabled ?? true)) return 0;
    final configuredHints = contentConfig?.ocrLanguageHints.trim() ?? '';
    final languageHints =
        configuredHints.isEmpty ? 'device_plus_en' : configuredHints;

    final recent = await backend.listRecentAttachments(sessionKey, limit: 80);
    var updated = 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final attachment in recent) {
      final mime = attachment.mimeType.trim().toLowerCase();
      if (!isDocxMimeType(mime)) continue;
      if (_autoOcrCompletedShas.contains(attachment.sha256)) continue;

      final payloadJson = await backend.readAttachmentAnnotationPayloadJson(
        sessionKey,
        sha256: attachment.sha256,
      );
      final payload =
          _MediaEnrichmentGateState._decodePayloadObject(payloadJson);
      if (payload == null) continue;
      if (!shouldAttemptDocxOcr(payload, nowMs: now)) continue;

      final pageCountHint =
          _MediaEnrichmentGateState._asInt(payload['page_count']) > 0
              ? _MediaEnrichmentGateState._asInt(payload['page_count'])
              : 1;
      final attemptMs = DateTime.now().millisecondsSinceEpoch;
      final retryCount =
          _MediaEnrichmentGateState._asInt(payload['ocr_auto_retry_count']);

      Future<void> persistPayload(Map<String, Object?> next, int ts) async {
        await backend.markAttachmentAnnotationOkJson(
          sessionKey,
          attachmentSha256: attachment.sha256,
          lang: 'und',
          modelName: 'document_extract.v1',
          payloadJson: jsonEncode(next),
          nowMs: ts,
        );
      }

      try {
        final runningPayload = Map<String, Object?>.from(payload);
        runningPayload['ocr_auto_status'] = 'running';
        runningPayload['ocr_auto_running_ms'] = attemptMs;
        runningPayload['ocr_auto_last_attempt_ms'] = attemptMs;
        runningPayload['ocr_auto_attempted_ms'] = attemptMs;
        runningPayload['ocr_auto_retry_count'] = retryCount;
        await persistPayload(runningPayload, attemptMs);

        final bytes = await backend.readAttachmentBytes(
          sessionKey,
          sha256: attachment.sha256,
        );
        if (bytes.isEmpty) {
          final failedPayload = Map<String, Object?>.from(runningPayload);
          failedPayload.remove('ocr_auto_running_ms');
          failedPayload['ocr_auto_status'] = 'failed';
          failedPayload['ocr_auto_last_failure_ms'] =
              DateTime.now().millisecondsSinceEpoch;
          failedPayload['ocr_auto_retry_count'] = retryCount + 1;
          await persistPayload(
            failedPayload,
            failedPayload['ocr_auto_last_failure_ms'] as int,
          );
          continue;
        }

        final ocr = await runDocxOcr(
          bytes,
          pageCount: pageCountHint,
          languageHints: languageHints,
        );

        final updatedPayload = Map<String, Object?>.from(runningPayload);
        updatedPayload.remove('ocr_auto_running_ms');
        if (ocr != null) {
          final extractedFull =
              (payload['extracted_text_full'] ?? '').toString();
          final extractedExcerpt =
              (payload['extracted_text_excerpt'] ?? '').toString();
          final extractedText = (extractedExcerpt.trim().isNotEmpty
                  ? extractedExcerpt
                  : extractedFull)
              .trim();
          updatedPayload['needs_ocr'] =
              ocr.fullText.trim().isEmpty && extractedText.isEmpty;
          updatedPayload['ocr_text_full'] = ocr.fullText;
          updatedPayload['ocr_text_excerpt'] = ocr.excerpt;
          updatedPayload['ocr_engine'] = ocr.engine;
          updatedPayload['ocr_lang_hints'] = languageHints;
          updatedPayload['ocr_dpi'] = 0;
          updatedPayload['ocr_retry_attempted'] = ocr.retryAttempted;
          updatedPayload['ocr_retry_attempts'] = ocr.retryAttempts;
          updatedPayload['ocr_retry_hints'] = ocr.retryHintsTried.join(',');
          updatedPayload['ocr_is_truncated'] = ocr.isTruncated;
          updatedPayload['ocr_page_count'] = ocr.pageCount;
          updatedPayload['ocr_processed_pages'] = ocr.processedPages;
          updatedPayload['ocr_auto_status'] = 'ok';
          updatedPayload['ocr_auto_last_success_ms'] =
              DateTime.now().millisecondsSinceEpoch;
          updatedPayload.remove('ocr_auto_last_failure_ms');
          await persistPayload(
            updatedPayload,
            updatedPayload['ocr_auto_last_success_ms'] as int,
          );
          _autoOcrCompletedShas.add(attachment.sha256);
          updated += 1;
        } else {
          updatedPayload['ocr_auto_status'] = 'failed';
          updatedPayload['ocr_auto_last_failure_ms'] =
              DateTime.now().millisecondsSinceEpoch;
          updatedPayload['ocr_auto_retry_count'] = retryCount + 1;
          await persistPayload(
            updatedPayload,
            updatedPayload['ocr_auto_last_failure_ms'] as int,
          );
        }
      } catch (_) {
        final failedPayload = Map<String, Object?>.from(payload);
        failedPayload.remove('ocr_auto_running_ms');
        failedPayload['ocr_auto_status'] = 'failed';
        failedPayload['ocr_auto_last_failure_ms'] =
            DateTime.now().millisecondsSinceEpoch;
        failedPayload['ocr_auto_retry_count'] = retryCount + 1;
        try {
          await persistPayload(
            failedPayload,
            failedPayload['ocr_auto_last_failure_ms'] as int,
          );
        } catch (_) {
          // ignore per-attachment status persistence failures.
        }
      }
    }

    return updated;
  }

  Future<int> _runAutoVideoManifestOcrForRecentAttachments({
    required NativeAppBackend backend,
    required Uint8List sessionKey,
    required ContentEnrichmentConfig? contentConfig,
  }) async {
    if (!(contentConfig?.ocrEnabled ?? true)) return 0;
    final configuredHints = contentConfig?.ocrLanguageHints.trim() ?? '';
    final languageHints =
        configuredHints.isEmpty ? 'device_plus_en' : configuredHints;

    final recent = await backend.listRecentAttachments(sessionKey, limit: 80);
    var updated = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    const maxSegments = 6;

    Future<void> persistPayload(
      String attachmentSha256,
      Map<String, Object?> next,
      int ts,
    ) async {
      await backend.markAttachmentAnnotationOkJson(
        sessionKey,
        attachmentSha256: attachmentSha256,
        lang: 'und',
        modelName: 'video_extract.v1',
        payloadJson: jsonEncode(next),
        nowMs: ts,
      );
    }

    Future<void> markFailed({
      required String attachmentSha256,
      required Map<String, Object?> payload,
      required int retryCount,
      required int attemptMs,
    }) async {
      final failedPayload = Map<String, Object?>.from(payload);
      failedPayload.remove('ocr_auto_running_ms');
      failedPayload['ocr_auto_status'] = 'failed';
      failedPayload['ocr_auto_last_attempt_ms'] = attemptMs;
      failedPayload['ocr_auto_last_failure_ms'] =
          DateTime.now().millisecondsSinceEpoch;
      failedPayload['ocr_auto_retry_count'] = retryCount + 1;
      await persistPayload(
        attachmentSha256,
        failedPayload,
        failedPayload['ocr_auto_last_failure_ms'] as int,
      );
    }

    for (final attachment in recent) {
      final mime = attachment.mimeType.trim().toLowerCase();
      if (mime != kSecondLoopVideoManifestMimeType) continue;
      if (_autoOcrCompletedShas.contains(attachment.sha256)) continue;

      final payloadJson = await backend.readAttachmentAnnotationPayloadJson(
        sessionKey,
        sha256: attachment.sha256,
      );
      final payload =
          _MediaEnrichmentGateState._decodePayloadObject(payloadJson);
      if (payload == null) continue;
      if (!shouldAutoRunVideoManifestOcr(payload, nowMs: now)) continue;

      final retryCount =
          _MediaEnrichmentGateState._asInt(payload['ocr_auto_retry_count']);
      final attemptMs = DateTime.now().millisecondsSinceEpoch;

      try {
        final runningPayload = Map<String, Object?>.from(payload);
        runningPayload['ocr_auto_status'] = 'running';
        runningPayload['ocr_auto_running_ms'] = attemptMs;
        runningPayload['ocr_auto_last_attempt_ms'] = attemptMs;
        runningPayload['ocr_auto_attempted_ms'] = attemptMs;
        runningPayload['ocr_auto_retry_count'] = retryCount;
        await persistPayload(attachment.sha256, runningPayload, attemptMs);

        final manifestBytes = await backend.readAttachmentBytes(
          sessionKey,
          sha256: attachment.sha256,
        );
        final manifest = parseVideoManifestPayload(manifestBytes);
        if (manifest == null) {
          await markFailed(
            attachmentSha256: attachment.sha256,
            payload: runningPayload,
            retryCount: retryCount,
            attemptMs: attemptMs,
          );
          continue;
        }

        final segmentRefs =
            manifest.segments.take(maxSegments).toList(growable: false);
        if (segmentRefs.isEmpty) {
          await markFailed(
            attachmentSha256: attachment.sha256,
            payload: runningPayload,
            retryCount: retryCount,
            attemptMs: attemptMs,
          );
          continue;
        }

        final maxFramesPerSegment =
            segmentRefs.length <= 1 ? 12 : (segmentRefs.length <= 2 ? 8 : 4);

        final ocrBlocks = <String>[];
        final ocrEngines = <String>[];
        var totalFrameCount = 0;
        var totalProcessedFrames = 0;
        var processedSegments = 0;
        var ocrTruncated = manifest.segments.length > segmentRefs.length;

        for (var i = 0; i < segmentRefs.length; i++) {
          final segment = segmentRefs[i];
          final segmentBytes = await backend.readAttachmentBytes(
            sessionKey,
            sha256: segment.sha256,
          );
          if (segmentBytes.isEmpty) continue;

          final ocr = await VideoKeyframeOcrWorker.runOnVideoBytes(
            segmentBytes,
            sourceMimeType: segment.mimeType,
            maxFrames: maxFramesPerSegment,
            frameIntervalSeconds: 5,
            languageHints: languageHints,
          );
          if (ocr == null) continue;

          processedSegments += 1;
          totalFrameCount += ocr.frameCount;
          totalProcessedFrames += ocr.processedFrames;
          ocrTruncated = ocrTruncated || ocr.isTruncated;

          final engine = ocr.engine.trim();
          if (engine.isNotEmpty) {
            ocrEngines.add(engine);
          }

          final full = ocr.fullText.trim();
          if (full.isEmpty) continue;
          if (segmentRefs.length <= 1) {
            ocrBlocks.add(full);
          } else {
            ocrBlocks.add('[segment ${i + 1}]\n$full');
          }
        }

        if (processedSegments <= 0) {
          await markFailed(
            attachmentSha256: attachment.sha256,
            payload: runningPayload,
            retryCount: retryCount,
            attemptMs: attemptMs,
          );
          continue;
        }

        final ocrFullText = ocrBlocks.join('\n\n').trim();
        final ocrExcerpt = _truncateUtf8ForAutoOcr(ocrFullText, 8 * 1024);
        final ocrEngine = _dominantStringForAutoOcr(ocrEngines);

        if (ocrEngine.isEmpty || ocrFullText.isEmpty) {
          await markFailed(
            attachmentSha256: attachment.sha256,
            payload: runningPayload,
            retryCount: retryCount,
            attemptMs: attemptMs,
          );
          continue;
        }

        final transcriptFull = _readTrimmedPayloadString(
          runningPayload,
          'transcript_full',
        );
        final transcriptExcerptRaw = _readTrimmedPayloadString(
          runningPayload,
          'transcript_excerpt',
        );
        final transcriptExcerpt = transcriptExcerptRaw.isNotEmpty
            ? transcriptExcerptRaw
            : _truncateUtf8ForAutoOcr(transcriptFull, 8 * 1024);

        final readableTextFull = _joinNonEmptyBlocksForAutoOcr([
          transcriptFull,
          ocrFullText,
        ]);
        final readableTextExcerpt = _joinNonEmptyBlocksForAutoOcr([
          transcriptExcerpt,
          ocrExcerpt,
        ]);

        final segmentPayloads = manifest.segments
            .map(
              (segment) => <String, Object?>{
                'index': segment.index,
                'sha256': segment.sha256,
                'mime_type': segment.mimeType,
              },
            )
            .toList(growable: false);

        final updatedPayload = Map<String, Object?>.from(runningPayload);
        updatedPayload.remove('ocr_auto_running_ms');
        updatedPayload['video_segment_count'] = manifest.segments.length;
        updatedPayload['video_processed_segment_count'] = processedSegments;
        updatedPayload['video_ocr_segment_limit'] = maxSegments;
        updatedPayload['video_segments'] = segmentPayloads;
        if (manifest.audioSha256 != null) {
          updatedPayload['audio_sha256'] = manifest.audioSha256;
        }
        if (manifest.audioMimeType != null) {
          updatedPayload['audio_mime_type'] = manifest.audioMimeType;
        }
        if (transcriptFull.isNotEmpty) {
          updatedPayload['transcript_full'] = transcriptFull;
        }
        if (transcriptExcerpt.isNotEmpty) {
          updatedPayload['transcript_excerpt'] = transcriptExcerpt;
        }
        updatedPayload['needs_ocr'] = false;
        updatedPayload['readable_text_full'] = readableTextFull;
        updatedPayload['readable_text_excerpt'] = readableTextExcerpt;
        updatedPayload['ocr_text_full'] = ocrFullText;
        updatedPayload['ocr_text_excerpt'] = ocrExcerpt;
        updatedPayload['ocr_engine'] = ocrEngine;
        updatedPayload['ocr_lang_hints'] = languageHints;
        updatedPayload['ocr_is_truncated'] = ocrTruncated;
        updatedPayload['ocr_page_count'] = totalFrameCount;
        updatedPayload['ocr_processed_pages'] = totalProcessedFrames;
        updatedPayload['ocr_auto_status'] = 'ok';
        updatedPayload['ocr_auto_last_success_ms'] =
            DateTime.now().millisecondsSinceEpoch;
        updatedPayload.remove('ocr_auto_last_failure_ms');

        await persistPayload(
          attachment.sha256,
          updatedPayload,
          updatedPayload['ocr_auto_last_success_ms'] as int,
        );

        _autoOcrCompletedShas.add(attachment.sha256);
        updated += 1;
      } catch (_) {
        try {
          await markFailed(
            attachmentSha256: attachment.sha256,
            payload: payload,
            retryCount: retryCount,
            attemptMs: attemptMs,
          );
        } catch (_) {
          // ignore per-attachment status persistence failures.
        }
      }
    }

    return updated;
  }
}

String _readTrimmedPayloadString(Map<String, Object?> payload, String key) {
  final raw = payload[key];
  if (raw == null) return '';
  final value = raw.toString().trim();
  if (value.toLowerCase() == 'null') return '';
  return value;
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
