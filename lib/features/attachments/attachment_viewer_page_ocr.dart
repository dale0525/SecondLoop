part of 'attachment_viewer_page.dart';

extension _AttachmentViewerPageOcr on _AttachmentViewerPageState {
  bool _isPdfAttachment() =>
      widget.attachment.mimeType.trim().toLowerCase() == 'application/pdf';

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

    setState(() {
      _runningDocumentOcr = true;
      _documentOcrStatusText = context.t.attachments.content.ocrRunning;
    });

    try {
      final manifestBytes = await (_bytesFuture ??= _loadBytes());
      final manifest = parseVideoManifestPayload(manifestBytes);
      if (manifest == null) {
        if (!mounted) return;
        setState(() {
          _runningDocumentOcr = false;
          _documentOcrStatusText = context.t.attachments.content.ocrFailed;
        });
        return;
      }

      final languageHints = _effectiveDocumentOcrLanguageHints;

      final originalVideoBytes = await backend.readAttachmentBytes(
        sessionKey,
        sha256: manifest.originalSha256,
      );
      if (originalVideoBytes.isEmpty) {
        if (!mounted) return;
        setState(() {
          _runningDocumentOcr = false;
          _documentOcrStatusText = context.t.attachments.content.ocrFailed;
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
        if (!mounted) return;
        setState(() {
          _runningDocumentOcr = false;
          _documentOcrStatusText = context.t.attachments.content.ocrFailed;
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
      setState(() {
        _runningDocumentOcr = false;
        _annotationPayload = updatedPayload;
        _annotationPayloadFuture = Future.value(updatedPayload);
        _documentOcrStatusText = (!needsOcr || ocrText.isNotEmpty)
            ? context.t.attachments.content.ocrFinished
            : context.t.attachments.content.ocrFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _runningDocumentOcr = false;
        _documentOcrStatusText = context.t.attachments.content.ocrFailed;
      });
    }
  }

  Future<void> _runDocumentOcr() async {
    if (_runningDocumentOcr) return;
    if (!_isPdfAttachment()) return;
    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) return;
    final backend = backendAny;
    final sessionKey = SessionScope.of(context).sessionKey;
    final now = DateTime.now().millisecondsSinceEpoch;
    final localeTag = Localizations.localeOf(context).toLanguageTag();

    int? asInt(Object? raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw.trim());
      return null;
    }

    setState(() {
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
      final platformOcr = await PlatformPdfOcr.tryOcrPdfBytes(
        bytes,
        maxPages: maxPages,
        dpi: dpi,
        languageHints: languageHints,
      );

      if (platformOcr == null) {
        if (!mounted) return;
        setState(() {
          _runningDocumentOcr = false;
          _documentOcrStatusText = context.t.attachments.content.ocrFailed;
        });
        return;
      }

      final extractedFull =
          existingPayload['extracted_text_full']?.toString() ?? '';
      final extractedExcerpt =
          existingPayload['extracted_text_excerpt']?.toString() ?? '';
      final pageCount =
          asInt(existingPayload['page_count']) ?? platformOcr.pageCount;
      final payloadJson = jsonEncode(<String, Object?>{
        'schema': 'secondloop.document_extract.v1',
        'mime_type': widget.attachment.mimeType,
        'extracted_text_full': extractedFull,
        'extracted_text_excerpt': extractedExcerpt,
        'needs_ocr': platformOcr.fullText.trim().isEmpty,
        'page_count': pageCount,
        'ocr_text_full': platformOcr.fullText,
        'ocr_text_excerpt': platformOcr.excerpt,
        'ocr_engine': platformOcr.engine,
        'ocr_lang_hints': languageHints,
        'ocr_dpi': dpi,
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
      setState(() {
        _runningDocumentOcr = false;
        _annotationPayload = updatedPayload;
        _annotationPayloadFuture = Future.value(updatedPayload);
        _documentOcrStatusText = (!needsOcr || ocrText.isNotEmpty)
            ? context.t.attachments.content.ocrFinished
            : context.t.attachments.content.ocrFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _runningDocumentOcr = false;
        _documentOcrStatusText = context.t.attachments.content.ocrFailed;
      });
    }
  }
}
