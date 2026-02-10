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

  bool _isRuntimeOcrEngine(String engine) {
    final normalized = engine.trim().toLowerCase();
    return normalized.startsWith('desktop_rust_');
  }

  String _buildExcerpt(String fullText, {int maxChars = 1200}) {
    final trimmed = fullText.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return '${trimmed.substring(0, maxChars).trimRight()}…';
  }

  PlatformPdfOcrResult _preferExtractedTextIfRuntimeOcr(
    PlatformPdfOcrResult ocr,
    Map<String, Object?> payload,
  ) {
    if (!_isRuntimeOcrEngine(ocr.engine)) return ocr;

    final extractedFull =
        (payload['extracted_text_full'] ?? '').toString().trim();
    if (extractedFull.isEmpty) return ocr;
    if (!shouldPreferExtractedTextOverOcr(
      extractedText: extractedFull,
      ocrText: ocr.fullText,
    )) {
      return ocr;
    }

    final extractedExcerpt =
        (payload['extracted_text_excerpt'] ?? '').toString().trim();
    return ocr.copyWith(
      fullText: extractedFull,
      excerpt: extractedExcerpt.isNotEmpty
          ? extractedExcerpt
          : _buildExcerpt(extractedFull),
      engine: '${ocr.engine}+prefer_extracted',
    );
  }

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

      final originalVideoBytes = await backend.readAttachmentBytes(
        sessionKey,
        sha256: manifest.originalSha256,
      );
      if (originalVideoBytes.isEmpty) {
        final failedText = _buildOcrFailedStatus('original_video_missing');
        if (!mounted) return;
        _updateViewerState(() {
          _runningDocumentOcr = false;
          _documentOcrStatusText = failedText;
        });
        return;
      }

      final ocr = await VideoKeyframeOcrWorker.runOnVideoBytes(
        originalVideoBytes,
        sourceMimeType: manifest.originalMimeType,
        maxFrames: 12,
        frameIntervalSeconds: 5,
        languageHints: languageHints,
      );
      if (ocr == null) {
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

      final payloadJson = jsonEncode(<String, Object?>{
        'schema': 'secondloop.video_extract.v1',
        'mime_type': widget.attachment.mimeType,
        'original_sha256': manifest.originalSha256,
        'original_mime_type': manifest.originalMimeType,
        'needs_ocr': ocr.fullText.trim().isEmpty,
        'readable_text_full': ocr.fullText,
        'readable_text_excerpt': ocr.excerpt,
        'ocr_text_full': ocr.fullText,
        'ocr_text_excerpt': ocr.excerpt,
        'ocr_engine': ocr.engine,
        'ocr_lang_hints': languageHints,
        'ocr_is_truncated': ocr.isTruncated,
        'ocr_page_count': ocr.frameCount,
        'ocr_processed_pages': ocr.processedFrames,
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

      platformOcr =
          _preferExtractedTextIfRuntimeOcr(platformOcr, existingPayload);

      final extractedFull =
          existingPayload['extracted_text_full']?.toString() ?? '';
      final extractedExcerpt =
          existingPayload['extracted_text_excerpt']?.toString() ?? '';
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
