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
    required bool shouldTryMultimodalOcr,
    required bool canUseNetworkOcr,
    required SubscriptionStatus subscriptionStatus,
    required MediaAnnotationConfig mediaAnnotationConfig,
    required List<LlmProfile> llmProfiles,
    required String cloudGatewayBaseUrl,
    required String cloudIdToken,
    required String cloudModelName,
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

        Map<String, Object?>? linkedAudioPayload;
        final audioSha256 = (manifest.audioSha256 ?? '').trim();
        if (audioSha256.isNotEmpty) {
          final linkedAudioPayloadJson =
              await backend.readAttachmentAnnotationPayloadJson(
            sessionKey,
            sha256: audioSha256,
          );
          linkedAudioPayload = _MediaEnrichmentGateState._decodePayloadObject(
            linkedAudioPayloadJson,
          );
        }

        final transcriptSeed = resolveVideoManifestTranscriptSeed(
          runningPayload: runningPayload,
          audioSha256: manifest.audioSha256,
          linkedAudioPayload: linkedAudioPayload,
        );
        if (transcriptSeed.shouldDeferForLinkedAudio) {
          final queuedPayload = Map<String, Object?>.from(runningPayload);
          queuedPayload.remove('ocr_auto_running_ms');
          queuedPayload['ocr_auto_status'] = 'queued';
          await persistPayload(attachment.sha256, queuedPayload, attemptMs);
          continue;
        }
        _setOrRemoveAutoOcrPayloadField(
          runningPayload,
          'transcript_full',
          transcriptSeed.transcriptFull,
        );
        _setOrRemoveAutoOcrPayloadField(
          runningPayload,
          'transcript_excerpt',
          transcriptSeed.transcriptExcerpt,
        );

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
        Uint8List? insightSegmentBytes;
        String? insightSegmentMimeType;

        for (var i = 0; i < segmentRefs.length; i++) {
          final segment = segmentRefs[i];
          final segmentBytes = await backend.readAttachmentBytes(
            sessionKey,
            sha256: segment.sha256,
          );
          if (segmentBytes.isEmpty) continue;
          insightSegmentBytes ??= segmentBytes;
          insightSegmentMimeType ??= segment.mimeType;

          final ocrResult = await runAutoVideoSegmentOcrWithFallback(
            shouldTryMultimodalOcr: shouldTryMultimodalOcr,
            canUseNetworkOcr: canUseNetworkOcr,
            runMultimodalOcr: () {
              return tryConfiguredMultimodalMediaOcr(
                backend: backend,
                sessionKey: sessionKey,
                mimeType: segment.mimeType,
                mediaBytes: segmentBytes,
                pageCountHint: 1,
                languageHints: languageHints,
                subscriptionStatus: subscriptionStatus,
                mediaAnnotationConfig: mediaAnnotationConfig,
                llmProfiles: llmProfiles,
                cloudGatewayBaseUrl: cloudGatewayBaseUrl,
                cloudIdToken: cloudIdToken,
                cloudModelName: cloudModelName,
              );
            },
            runKeyframeOcr: () {
              return VideoKeyframeOcrWorker.runOnVideoBytes(
                segmentBytes,
                sourceMimeType: segment.mimeType,
                maxFrames: maxFramesPerSegment,
                frameIntervalSeconds: 5,
                languageHints: languageHints,
              );
            },
          );
          if (ocrResult == null) continue;

          processedSegments += 1;
          totalFrameCount += ocrResult.pageCount;
          totalProcessedFrames += ocrResult.processedPages;
          ocrTruncated = ocrTruncated || ocrResult.isTruncated;

          final engine = ocrResult.engine.trim();
          if (engine.isNotEmpty) {
            ocrEngines.add(engine);
          }

          final full = ocrResult.fullText.trim();
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

        final transcriptFull = transcriptSeed.transcriptFull;
        final transcriptExcerpt = transcriptSeed.transcriptExcerpt;

        final readableTextFull = _joinNonEmptyBlocksForAutoOcr([
          transcriptFull,
          ocrFullText,
        ]);
        final readableTextExcerpt = _joinNonEmptyBlocksForAutoOcr([
          transcriptExcerpt,
          ocrExcerpt,
        ]);

        MultimodalVideoInsight? multimodalInsight;
        if (shouldTryMultimodalOcr &&
            canUseNetworkOcr &&
            insightSegmentBytes != null &&
            insightSegmentMimeType != null) {
          try {
            multimodalInsight = await tryConfiguredMultimodalVideoInsight(
              backend: backend,
              sessionKey: sessionKey,
              mimeType: insightSegmentMimeType,
              mediaBytes: insightSegmentBytes,
              languageHints: languageHints,
              subscriptionStatus: subscriptionStatus,
              mediaAnnotationConfig: mediaAnnotationConfig,
              llmProfiles: llmProfiles,
              cloudGatewayBaseUrl: cloudGatewayBaseUrl,
              cloudIdToken: cloudIdToken,
              cloudModelName: cloudModelName,
            );
          } catch (_) {
            multimodalInsight = null;
          }
        }

        final heuristicContentKind = inferVideoContentKind(
          transcriptFull: transcriptFull,
          ocrTextFull: ocrFullText,
          readableTextFull: readableTextFull,
        );
        final updatedPayload = buildAutoVideoManifestOcrPayload(
          runningPayload: runningPayload,
          manifest: manifest,
          maxSegments: maxSegments,
          processedSegments: processedSegments,
          transcriptFull: transcriptFull,
          transcriptExcerpt: transcriptExcerpt,
          readableTextFull: readableTextFull,
          readableTextExcerpt: readableTextExcerpt,
          ocrFullText: ocrFullText,
          ocrExcerpt: ocrExcerpt,
          ocrEngine: ocrEngine,
          languageHints: languageHints,
          ocrTruncated: ocrTruncated,
          totalFrameCount: totalFrameCount,
          totalProcessedFrames: totalProcessedFrames,
          heuristicContentKind: heuristicContentKind,
          multimodalInsight: multimodalInsight,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );

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

@visibleForTesting
Map<String, Object?> buildAutoVideoManifestOcrPayload({
  required Map<String, Object?> runningPayload,
  required ParsedVideoManifest manifest,
  required int maxSegments,
  required int processedSegments,
  required String transcriptFull,
  required String transcriptExcerpt,
  required String readableTextFull,
  required String readableTextExcerpt,
  required String ocrFullText,
  required String ocrExcerpt,
  required String ocrEngine,
  required String languageHints,
  required bool ocrTruncated,
  required int totalFrameCount,
  required int totalProcessedFrames,
  required String heuristicContentKind,
  required MultimodalVideoInsight? multimodalInsight,
  required int nowMs,
}) {
  final videoContentKind = _resolvedVideoContentKindForAutoOcr(
    multimodalContentKind: multimodalInsight?.contentKind ?? '',
    heuristicContentKind: heuristicContentKind,
  );
  final fallbackSummary = buildVideoSummaryText(
    readableTextExcerpt.isNotEmpty ? readableTextExcerpt : readableTextFull,
    maxBytes: 2048,
  );
  final videoSummary = _firstNonEmptyForAutoOcr([
    multimodalInsight?.summary ?? '',
    fallbackSummary,
  ]);
  final knowledgeMarkdownFull = _firstNonEmptyForAutoOcr([
    multimodalInsight?.knowledgeMarkdown ?? '',
    readableTextFull,
  ]);
  final knowledgeMarkdownExcerpt = _truncateUtf8ForAutoOcr(
    _firstNonEmptyForAutoOcr([
      multimodalInsight?.knowledgeMarkdown ?? '',
      readableTextExcerpt,
      readableTextFull,
    ]),
    8 * 1024,
  );
  final videoDescriptionFull = _firstNonEmptyForAutoOcr([
    multimodalInsight?.videoDescription ?? '',
    readableTextFull,
  ]);
  final videoDescriptionExcerpt = _truncateUtf8ForAutoOcr(
    _firstNonEmptyForAutoOcr([
      multimodalInsight?.videoDescription ?? '',
      readableTextExcerpt,
      readableTextFull,
    ]),
    8 * 1024,
  );

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
  } else {
    updatedPayload.remove('audio_sha256');
  }
  if (manifest.audioMimeType != null) {
    updatedPayload['audio_mime_type'] = manifest.audioMimeType;
  } else {
    updatedPayload.remove('audio_mime_type');
  }
  _setOrRemoveAutoOcrPayloadField(
    updatedPayload,
    'transcript_full',
    transcriptFull,
  );
  _setOrRemoveAutoOcrPayloadField(
    updatedPayload,
    'transcript_excerpt',
    transcriptExcerpt,
  );
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
  updatedPayload['video_content_kind'] = videoContentKind;

  final videoContentKindEngine = (multimodalInsight?.engine ?? '').trim();
  if (videoContentKindEngine.isNotEmpty) {
    updatedPayload['video_content_kind_engine'] = videoContentKindEngine;
  } else {
    updatedPayload.remove('video_content_kind_engine');
  }

  _setOrRemoveAutoOcrPayloadField(
      updatedPayload, 'video_summary', videoSummary);

  if (videoContentKind == 'knowledge') {
    _setOrRemoveAutoOcrPayloadField(
      updatedPayload,
      'knowledge_markdown_full',
      knowledgeMarkdownFull,
    );
    _setOrRemoveAutoOcrPayloadField(
      updatedPayload,
      'knowledge_markdown_excerpt',
      knowledgeMarkdownExcerpt,
    );
    updatedPayload.remove('video_description_full');
    updatedPayload.remove('video_description_excerpt');
  } else if (videoContentKind == 'non_knowledge') {
    _setOrRemoveAutoOcrPayloadField(
      updatedPayload,
      'video_description_full',
      videoDescriptionFull,
    );
    _setOrRemoveAutoOcrPayloadField(
      updatedPayload,
      'video_description_excerpt',
      videoDescriptionExcerpt,
    );
    updatedPayload.remove('knowledge_markdown_full');
    updatedPayload.remove('knowledge_markdown_excerpt');
  } else {
    updatedPayload.remove('knowledge_markdown_full');
    updatedPayload.remove('knowledge_markdown_excerpt');
    updatedPayload.remove('video_description_full');
    updatedPayload.remove('video_description_excerpt');
  }

  updatedPayload['ocr_auto_status'] = 'ok';
  updatedPayload['ocr_auto_last_success_ms'] = nowMs;
  updatedPayload.remove('ocr_auto_last_failure_ms');
  return updatedPayload;
}

void _setOrRemoveAutoOcrPayloadField(
  Map<String, Object?> payload,
  String key,
  String value,
) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    payload.remove(key);
    return;
  }
  payload[key] = normalized;
}

enum AutoVideoSegmentOcrSource {
  multimodal,
  keyframe,
}

final class AutoVideoSegmentOcrResult {
  const AutoVideoSegmentOcrResult({
    required this.source,
    required this.fullText,
    required this.engine,
    required this.isTruncated,
    required this.pageCount,
    required this.processedPages,
  });

  final AutoVideoSegmentOcrSource source;
  final String fullText;
  final String engine;
  final bool isTruncated;
  final int pageCount;
  final int processedPages;
}

@visibleForTesting
Future<AutoVideoSegmentOcrResult?> runAutoVideoSegmentOcrWithFallback({
  required bool shouldTryMultimodalOcr,
  required bool canUseNetworkOcr,
  required Future<PlatformPdfOcrResult?> Function() runMultimodalOcr,
  required Future<VideoKeyframeOcrResult?> Function() runKeyframeOcr,
}) async {
  if (shouldTryMultimodalOcr && canUseNetworkOcr) {
    final multimodalOcr = await runMultimodalOcr();
    if (multimodalOcr != null) {
      final pageCount =
          multimodalOcr.pageCount > 0 ? multimodalOcr.pageCount : 1;
      final processedPages = multimodalOcr.processedPages > 0
          ? multimodalOcr.processedPages
          : pageCount;
      return AutoVideoSegmentOcrResult(
        source: AutoVideoSegmentOcrSource.multimodal,
        fullText: multimodalOcr.fullText,
        engine: multimodalOcr.engine,
        isTruncated: multimodalOcr.isTruncated,
        pageCount: pageCount,
        processedPages: processedPages,
      );
    }
  }

  final keyframeOcr = await runKeyframeOcr();
  if (keyframeOcr == null) return null;

  final pageCount = keyframeOcr.frameCount > 0 ? keyframeOcr.frameCount : 1;
  final processedPages =
      keyframeOcr.processedFrames > 0 ? keyframeOcr.processedFrames : pageCount;
  return AutoVideoSegmentOcrResult(
    source: AutoVideoSegmentOcrSource.keyframe,
    fullText: keyframeOcr.fullText,
    engine: keyframeOcr.engine,
    isTruncated: keyframeOcr.isTruncated,
    pageCount: pageCount,
    processedPages: processedPages,
  );
}

String _resolvedVideoContentKindForAutoOcr({
  required String multimodalContentKind,
  required String heuristicContentKind,
}) {
  final normalizedMultimodal = multimodalContentKind.trim().toLowerCase();
  if (normalizedMultimodal == 'knowledge' ||
      normalizedMultimodal == 'non_knowledge') {
    return normalizedMultimodal;
  }

  final normalizedHeuristic = heuristicContentKind.trim().toLowerCase();
  if (normalizedHeuristic == 'knowledge' ||
      normalizedHeuristic == 'non_knowledge') {
    return normalizedHeuristic;
  }
  return 'unknown';
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
