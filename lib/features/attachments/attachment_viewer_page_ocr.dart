part of 'attachment_viewer_page.dart';

extension _AttachmentViewerPageOcr on _AttachmentViewerPageState {
  String _buildOcrFailedStatus([Object? error]) {
    final base = context.t.attachments.content.ocrFailed;
    final detail = error?.toString().trim() ?? '';
    if (detail.isEmpty) return base;
    return '$base ($detail)';
  }

  bool _isPdfAttachment() =>
      widget.attachment.mimeType.trim().toLowerCase() == 'application/pdf';

  bool _isDocxAttachment() => isDocxMimeType(widget.attachment.mimeType);

  bool _supportsDocumentOcrAttachment() =>
      _isPdfAttachment() || _isDocxAttachment();

  bool _isVideoManifestAttachment() =>
      widget.attachment.mimeType.trim().toLowerCase() ==
      kSecondLoopVideoManifestMimeType;

  Future<void> _runVideoManifestOcr() async {
    if (_runningDocumentOcr) return;
    if (!_isVideoManifestAttachment()) return;
    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) return;
    final backend = backendAny;
    final sessionKey = SessionScope.of(context).sessionKey;
    final now = DateTime.now().millisecondsSinceEpoch;
    final localeTag = Localizations.localeOf(context).toLanguageTag();

    _updateViewerState(() {
      _runningDocumentOcr = true;
      _documentOcrStatusText = context.t.attachments.content.ocrRunning;
    });

    try {
      final manifestBytes = await (_bytesFuture ??= _loadBytes());
      final manifest = parseVideoManifestPayload(manifestBytes);
      if (manifest == null) {
        final failedText = _buildOcrFailedStatus('video_manifest_parse_failed');
        if (!mounted) return;
        _updateViewerState(() {
          _runningDocumentOcr = false;
          _documentOcrStatusText = failedText;
        });
        return;
      }

      final languageHints = _effectiveDocumentOcrLanguageHints;
      const maxSegments = 6;
      final segmentRefs =
          manifest.segments.take(maxSegments).toList(growable: false);
      final maxFramesPerSegment =
          segmentRefs.length <= 1 ? 12 : (segmentRefs.length <= 2 ? 8 : 4);

      final ocrBlocks = <String>[];
      final ocrEngines = <String>[];
      var totalFrameCount = 0;
      var totalProcessedFrames = 0;
      var ocrTruncated = manifest.segments.length > segmentRefs.length;
      var processedSegments = 0;

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
        final detail = PlatformPdfOcr.lastErrorMessage;
        if (detail != null && detail.isNotEmpty) {
          debugPrint('Video manifest OCR returned null: $detail');
        }
        final failedText =
            _buildOcrFailedStatus(detail ?? 'video_ocr_result_null');
        if (!mounted) return;
        _updateViewerState(() {
          _runningDocumentOcr = false;
          _documentOcrStatusText = failedText;
        });
        return;
      }

      final ocrFullText = ocrBlocks.join('\n\n').trim();
      final ocrExcerpt = _truncateUtf8(ocrFullText, 8 * 1024);
      final ocrEngine = _dominantString(ocrEngines);

      final transcriptPayload = await _loadAttachmentAnnotationPayloadBySha(
        backend,
        sessionKey,
        manifest.audioSha256,
      );
      final transcriptFull =
          (transcriptPayload?['transcript_full'] ?? '').toString().trim();
      final transcriptExcerptRaw =
          (transcriptPayload?['transcript_excerpt'] ?? '').toString().trim();
      final transcriptExcerpt = transcriptExcerptRaw.isNotEmpty
          ? transcriptExcerptRaw
          : _truncateUtf8(transcriptFull, 8 * 1024);

      final readableTextFull = _joinNonEmptyBlocks([
        transcriptFull,
        ocrFullText,
      ]);
      final readableTextExcerpt = _joinNonEmptyBlocks([
        transcriptExcerpt,
        ocrExcerpt,
      ]);

      final videoContentKind = inferVideoContentKind(
        transcriptFull: transcriptFull,
        ocrTextFull: ocrFullText,
        readableTextFull: readableTextFull,
      );
      final videoSummary = buildVideoSummaryText(
        readableTextExcerpt.isNotEmpty ? readableTextExcerpt : readableTextFull,
        maxBytes: 2048,
      );
      final knowledgeMarkdownFull =
          videoContentKind == 'knowledge' ? readableTextFull : '';
      final knowledgeMarkdownExcerpt = videoContentKind == 'knowledge'
          ? _truncateUtf8(
              readableTextExcerpt.isNotEmpty
                  ? readableTextExcerpt
                  : readableTextFull,
              8 * 1024,
            )
          : '';
      final videoDescriptionFull =
          videoContentKind == 'non_knowledge' ? readableTextFull : '';
      final videoDescriptionExcerpt = videoContentKind == 'non_knowledge'
          ? _truncateUtf8(
              readableTextExcerpt.isNotEmpty
                  ? readableTextExcerpt
                  : readableTextFull,
              8 * 1024,
            )
          : '';

      final payloadJson = jsonEncode(<String, Object?>{
        'schema': 'secondloop.video_extract.v1',
        'mime_type': widget.attachment.mimeType,
        'original_sha256': manifest.originalSha256,
        'original_mime_type': manifest.originalMimeType,
        'video_content_kind': videoContentKind,
        if (videoSummary.isNotEmpty) 'video_summary': videoSummary,
        if (knowledgeMarkdownFull.isNotEmpty)
          'knowledge_markdown_full': knowledgeMarkdownFull,
        if (knowledgeMarkdownExcerpt.isNotEmpty)
          'knowledge_markdown_excerpt': knowledgeMarkdownExcerpt,
        if (videoDescriptionFull.isNotEmpty)
          'video_description_full': videoDescriptionFull,
        if (videoDescriptionExcerpt.isNotEmpty)
          'video_description_excerpt': videoDescriptionExcerpt,
        'video_segment_count': manifest.segments.length,
        'video_processed_segment_count': processedSegments,
        'video_ocr_segment_limit': maxSegments,
        if (manifest.audioSha256 != null) 'audio_sha256': manifest.audioSha256,
        if (manifest.audioMimeType != null)
          'audio_mime_type': manifest.audioMimeType,
        if (transcriptFull.isNotEmpty) 'transcript_full': transcriptFull,
        if (transcriptExcerpt.isNotEmpty)
          'transcript_excerpt': transcriptExcerpt,
        'needs_ocr': ocrFullText.isEmpty,
        'readable_text_full': readableTextFull,
        'readable_text_excerpt': readableTextExcerpt,
        'ocr_text_full': ocrFullText,
        'ocr_text_excerpt': ocrExcerpt,
        'ocr_engine': ocrEngine,
        'ocr_lang_hints': languageHints,
        'ocr_is_truncated': ocrTruncated,
        'ocr_page_count': totalFrameCount,
        'ocr_processed_pages': totalProcessedFrames,
      });
      await backend.markAttachmentAnnotationOkJson(
        sessionKey,
        attachmentSha256: widget.attachment.sha256,
        lang: localeTag,
        modelName: 'video_extract.v1',
        payloadJson: payloadJson,
        nowMs: now,
      );

      final updatedPayload = await _loadAnnotationPayload();
      if (!mounted) return;
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      final ocrText = ((updatedPayload?['ocr_text_excerpt'] ??
                  updatedPayload?['ocr_text_full'] ??
                  updatedPayload?['readable_text_excerpt'] ??
                  updatedPayload?['readable_text_full']) ??
              '')
          .toString()
          .trim();
      final needsOcr = updatedPayload?['needs_ocr'] == true;
      final failedReason = (() {
        if (!needsOcr || ocrText.isNotEmpty) return '';
        final engine = (updatedPayload?['ocr_engine'] ?? '').toString().trim();
        if (engine.isNotEmpty) return 'ocr_empty_text(engine=$engine)';
        return 'ocr_result_without_engine_or_text';
      })();
      _updateViewerState(() {
        _runningDocumentOcr = false;
        _annotationPayload = updatedPayload;
        _annotationPayloadFuture = Future.value(updatedPayload);
        _documentOcrStatusText = (!needsOcr || ocrText.isNotEmpty)
            ? context.t.attachments.content.ocrFinished
            : _buildOcrFailedStatus(failedReason);
      });
    } catch (error, stackTrace) {
      debugPrint('Video manifest OCR failed: $error');
      debugPrint('$stackTrace');
      final failedText = _buildOcrFailedStatus(error);
      if (!mounted) return;
      _updateViewerState(() {
        _runningDocumentOcr = false;
        _documentOcrStatusText = failedText;
      });
    }
  }

  Future<Map<String, Object?>?> _loadAttachmentAnnotationPayloadBySha(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String? attachmentSha256,
  ) async {
    final sha = (attachmentSha256 ?? '').trim();
    if (sha.isEmpty) return null;
    try {
      final payloadJson = await backend.readAttachmentAnnotationPayloadJson(
        sessionKey,
        sha256: sha,
      );
      final raw = payloadJson?.trim();
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, Object?>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  String _joinNonEmptyBlocks(List<String> parts) {
    final values = parts
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (values.isEmpty) return '';
    return values.join('\n\n');
  }

  String _truncateUtf8(String text, int maxBytes) {
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

  String _dominantString(List<String> values) {
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

  Future<void> _runDocumentOcr() async {
    if (_runningDocumentOcr) return;
    if (!_supportsDocumentOcrAttachment()) return;
    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) return;
    final backend = backendAny;
    final sessionKey = SessionScope.of(context).sessionKey;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    final now = DateTime.now().millisecondsSinceEpoch;
    final localeTag = Localizations.localeOf(context).toLanguageTag();

    int? asInt(Object? raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw.trim());
      return null;
    }

    _updateViewerState(() {
      _runningDocumentOcr = true;
      _documentOcrStatusText = context.t.attachments.content.ocrRunning;
    });

    try {
      await backend.processPendingDocumentExtractions(sessionKey, limit: 500);
      final existingPayload =
          await _loadAnnotationPayload() ?? <String, Object?>{};
      const maxPages = 10000;
      const dpi = 180;
      final languageHints = _effectiveDocumentOcrLanguageHints;
      final bytes = await (_bytesFuture ??= _loadBytes());
      final mediaConfig = await const RustMediaAnnotationConfigStore()
          .read(sessionKey)
          .catchError(
            (_) => const MediaAnnotationConfig(
              annotateEnabled: false,
              searchEnabled: false,
              allowCellular: false,
              providerMode: 'follow_ask_ai',
            ),
          );
      final llmProfiles =
          await backend.listLlmProfiles(sessionKey).catchError((_) {
        return const <LlmProfile>[];
      });
      final gatewayConfig =
          cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;
      String? idToken;
      if (subscriptionStatus == SubscriptionStatus.entitled) {
        try {
          idToken = await cloudAuthScope?.controller.getIdToken();
        } catch (_) {
          idToken = null;
        }
      }

      final isPdf = _isPdfAttachment();
      final pageCountHint = asInt(existingPayload['page_count']) ?? 1;
      PlatformPdfOcrResult? platformOcr;
      if (isPdf) {
        platformOcr = await tryConfiguredMultimodalPdfOcr(
          backend: backend,
          sessionKey: sessionKey,
          pdfBytes: bytes,
          pageCountHint: pageCountHint,
          languageHints: languageHints,
          subscriptionStatus: subscriptionStatus,
          mediaAnnotationConfig: mediaConfig,
          llmProfiles: llmProfiles,
          cloudGatewayBaseUrl: gatewayConfig.baseUrl,
          cloudIdToken: idToken?.trim() ?? '',
          cloudModelName: gatewayConfig.modelName,
        );
        platformOcr ??= await PlatformPdfOcr.tryOcrPdfBytes(
          bytes,
          maxPages: maxPages,
          dpi: dpi,
          languageHints: languageHints,
        );
      } else if (_isDocxAttachment()) {
        platformOcr = await tryConfiguredDocxOcr(
          backend: backend,
          sessionKey: sessionKey,
          docxBytes: bytes,
          pageCountHint: pageCountHint,
          languageHints: languageHints,
          subscriptionStatus: subscriptionStatus,
          mediaAnnotationConfig: mediaConfig,
          llmProfiles: llmProfiles,
          cloudGatewayBaseUrl: gatewayConfig.baseUrl,
          cloudIdToken: idToken?.trim() ?? '',
          cloudModelName: gatewayConfig.modelName,
        );
      }

      if (platformOcr == null) {
        final detail = PlatformPdfOcr.lastErrorMessage;
        if (detail != null && detail.isNotEmpty) {
          debugPrint('Document OCR returned null: $detail');
        }
        final failedText = _buildOcrFailedStatus(detail ?? 'ocr_result_null');
        if (!mounted) return;
        _updateViewerState(() {
          _runningDocumentOcr = false;
          _documentOcrStatusText = failedText;
        });
        return;
      }

      final extractedFull =
          existingPayload['extracted_text_full']?.toString() ?? '';
      final extractedExcerpt =
          existingPayload['extracted_text_excerpt']?.toString() ?? '';
      if (isPdf) {
        platformOcr = maybePreferExtractedTextForRuntimeOcr(
          ocr: platformOcr,
          extractedFull: extractedFull,
          extractedExcerpt: extractedExcerpt,
        );
      }

      final pageCount =
          asInt(existingPayload['page_count']) ?? platformOcr.pageCount;
      final hasExtractedText =
          extractedExcerpt.trim().isNotEmpty || extractedFull.trim().isNotEmpty;
      final payloadJson = jsonEncode(<String, Object?>{
        'schema': 'secondloop.document_extract.v1',
        'mime_type': widget.attachment.mimeType,
        'extracted_text_full': extractedFull,
        'extracted_text_excerpt': extractedExcerpt,
        'needs_ocr': platformOcr.fullText.trim().isEmpty && !hasExtractedText,
        'page_count': pageCount,
        'ocr_text_full': platformOcr.fullText,
        'ocr_text_excerpt': platformOcr.excerpt,
        'ocr_engine': platformOcr.engine,
        'ocr_lang_hints': languageHints,
        'ocr_dpi': isPdf ? dpi : 0,
        'ocr_retry_attempted': platformOcr.retryAttempted,
        'ocr_retry_attempts': platformOcr.retryAttempts,
        'ocr_retry_hints': platformOcr.retryHintsTried.join(','),
        'ocr_is_truncated': platformOcr.isTruncated,
        'ocr_page_count': platformOcr.pageCount,
        'ocr_processed_pages': platformOcr.processedPages,
      });
      await backend.markAttachmentAnnotationOkJson(
        sessionKey,
        attachmentSha256: widget.attachment.sha256,
        lang: localeTag,
        modelName: 'document_extract.v1',
        payloadJson: payloadJson,
        nowMs: now,
      );

      await backend.processPendingDocumentExtractions(sessionKey, limit: 500);
      final updatedPayload = await _loadAnnotationPayload();
      if (!mounted) return;
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      final ocrText = ((updatedPayload?['ocr_text_excerpt'] ??
                  updatedPayload?['ocr_text_full']) ??
              '')
          .toString()
          .trim();
      final needsOcr = updatedPayload?['needs_ocr'] == true;
      final failedReason = (() {
        if (!needsOcr || ocrText.isNotEmpty) return '';
        final engine = (updatedPayload?['ocr_engine'] ?? '').toString().trim();
        final processedPages =
            (updatedPayload?['ocr_processed_pages'] ?? '').toString().trim();
        final pageCount =
            (updatedPayload?['ocr_page_count'] ?? '').toString().trim();
        final pagePart = (processedPages.isNotEmpty || pageCount.isNotEmpty)
            ? ', pages=$processedPages/$pageCount'
            : '';
        if (engine.isNotEmpty) {
          return 'ocr_empty_text(engine=$engine$pagePart)';
        }
        return 'ocr_result_without_engine_or_text$pagePart';
      })();
      _updateViewerState(() {
        _runningDocumentOcr = false;
        _annotationPayload = updatedPayload;
        _annotationPayloadFuture = Future.value(updatedPayload);
        _documentOcrStatusText = (!needsOcr || ocrText.isNotEmpty)
            ? context.t.attachments.content.ocrFinished
            : _buildOcrFailedStatus(failedReason);
      });
    } catch (error, stackTrace) {
      debugPrint('Document OCR failed: $error');
      debugPrint('$stackTrace');
      final failedText = _buildOcrFailedStatus(error);
      if (!mounted) return;
      _updateViewerState(() {
        _runningDocumentOcr = false;
        _documentOcrStatusText = failedText;
      });
    }
  }
}
