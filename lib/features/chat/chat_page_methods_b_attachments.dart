part of 'chat_page.dart';

extension _ChatPageStateMethodsBAttachments on _ChatPageState {
  bool _looksLikeHttpUrlText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    return true;
  }

  String _buildSharedUrlDraftFilename(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return 'shared-link.url';
    final uri = Uri.tryParse(trimmed);
    final host = uri?.host.trim() ?? '';
    if (host.isNotEmpty) return host;
    if (trimmed.length <= 96) return trimmed;
    return '${trimmed.substring(0, 93)}...';
  }

  String? _readUrlFromManifestDraft(AttachmentDraftPayload draft) {
    final mimeType = draft.normalizedMimeType.trim().toLowerCase();
    if (mimeType != kSecondLoopUrlManifestMimeType) return null;

    try {
      final decoded =
          jsonDecode(utf8.decode(draft.bytes, allowMalformed: false));
      if (decoded is! Map) return null;
      final schema = decoded['schema'];
      if (schema is! String || schema.trim() != kSecondLoopUrlManifestSchema) {
        return null;
      }
      final url = decoded['url'];
      if (url is! String) return null;
      final normalized = url.trim();
      if (!_looksLikeHttpUrlText(normalized)) return null;
      return normalized;
    } catch (_) {
      return null;
    }
  }

  Future<void> _consumePendingSharedUrlDrafts() async {
    if (!mounted) return;
    if (!_supportsCamera) return;
    if (widget.conversation.id != 'loop_home') return;

    final urls = await ShareDraftInbox.consumePendingUrls();
    if (urls.isEmpty) return;

    final drafts = <AttachmentDraftPayload>[];
    for (final url in urls) {
      final normalized = url.trim();
      if (!_looksLikeHttpUrlText(normalized)) continue;
      drafts.add(
        AttachmentDraftPayload(
          localId: _nextComposerAttachmentDraftLocalId(),
          filename: _buildSharedUrlDraftFilename(normalized),
          mimeType: kSecondLoopUrlManifestMimeType,
          bytes: buildUrlManifestAttachmentBytes(normalized),
        ),
      );
    }
    if (drafts.isEmpty || !mounted) return;
    _appendComposerAttachmentDrafts(drafts);
  }

  String _inferMimeTypeFromFilename(String filename) {
    final lower = filename.toLowerCase();

    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif')) {
      return _inferImageMimeTypeFromPath(filename);
    }

    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.ini')) return 'text/plain';
    if (lower.endsWith('.md')) return 'text/markdown';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.xml')) return 'application/xml';
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return 'application/x-yaml';
    }
    if (lower.endsWith('.toml')) return 'application/toml';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }

    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.opus')) return 'audio/opus';

    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.m4v')) return 'video/x-m4v';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.avi')) return 'video/x-msvideo';
    if (lower.endsWith('.wmv')) return 'video/x-ms-wmv';
    if (lower.endsWith('.flv')) return 'video/x-flv';
    if (lower.endsWith('.mpeg') || lower.endsWith('.mpg')) {
      return 'video/mpeg';
    }
    if (lower.endsWith('.ts') ||
        lower.endsWith('.m2ts') ||
        lower.endsWith('.mts')) {
      return 'video/mp2t';
    }
    if (lower.endsWith('.3gp')) return 'video/3gpp';
    if (lower.endsWith('.3g2')) return 'video/3gpp2';
    if (lower.endsWith('.asf')) return 'video/x-ms-asf';
    if (lower.endsWith('.ogv')) return 'video/ogg';

    return 'application/octet-stream';
  }

  Future<bool> _trySendTextAsUrlAttachment(String text) async {
    final trimmed = text.trim();
    if (!_looksLikeHttpUrlText(trimmed)) return false;

    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) return false;
    final backend = backendAny;
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);

    try {
      final attachment = await backend.insertAttachment(
        sessionKey,
        bytes: buildUrlManifestAttachmentBytes(trimmed),
        mimeType: kSecondLoopUrlManifestMimeType,
      );
      final message = await backend.insertMessage(
        sessionKey,
        widget.conversation.id,
        role: 'user',
        content: trimmed,
      );
      await backend.linkAttachmentToMessage(
        sessionKey,
        message.id,
        attachmentSha256: attachment.sha256,
      );

      unawaited(
        const RustAttachmentMetadataStore().upsert(
          sessionKey,
          attachmentSha256: attachment.sha256,
          title: trimmed,
          sourceUrls: [trimmed],
        ).catchError((_) {}),
      );

      syncEngine?.notifyLocalMutation();
      if (!mounted) return true;
      _refreshAfterAttachmentMutation();
      return true;
    } catch (_) {
      return false;
    }
  }

  String _nextComposerAttachmentDraftLocalId() {
    _composerAttachmentDraftSeq += 1;
    return 'chat_draft_$_composerAttachmentDraftSeq';
  }

  void _removeComposerAttachmentDraft(String localId) {
    if (_composerDraftAttachments.isEmpty) return;
    _setState(() {
      _composerDraftAttachments = _composerDraftAttachments
          .where((draft) => draft.localId != localId)
          .toList(growable: false);
      _failedComposerDraftLocalIds.remove(localId);
    });
  }

  void _appendComposerAttachmentDrafts(List<AttachmentDraftPayload> drafts) {
    if (drafts.isEmpty) return;
    final merged = dedupeAttachmentDraftPayloads(
      <AttachmentDraftPayload>[..._composerDraftAttachments, ...drafts],
    );
    final incomingIds = drafts.map((draft) => draft.localId).toSet();
    _setState(() {
      _composerDraftAttachments = merged;
      _failedComposerDraftLocalIds
          .removeWhere((localId) => incomingIds.contains(localId));
    });
  }

  Future<void> _addDesktopFilePayloadsToComposerDraft(
    List<({String filename, Uint8List bytes})> payloads,
  ) async {
    final drafts = <AttachmentDraftPayload>[];
    for (final payload in payloads) {
      final safeName = payload.filename.trim().isEmpty
          ? 'attachment.bin'
          : payload.filename.trim();
      final inferredMimeType = _inferMimeTypeFromFilename(safeName);
      drafts.add(
        AttachmentDraftPayload(
          localId: _nextComposerAttachmentDraftLocalId(),
          filename: safeName,
          mimeType: inferredMimeType,
          bytes: payload.bytes,
        ),
      );
    }
    _appendComposerAttachmentDrafts(drafts);
  }

  Future<void> _addDroppedDesktopFilesToComposerDraft(
    List<XFile> droppedFiles,
  ) async {
    if (_isComposerBusy) return;
    if (!_isDesktopPlatform) return;
    if (droppedFiles.isEmpty) return;

    _setState(() {
      _attachingMedia = true;
      _desktopDropActive = false;
    });
    try {
      final payloads = <({String filename, Uint8List bytes})>[];
      for (final dropped in droppedFiles) {
        final bytes = await dropped.readAsBytes();
        if (bytes.isEmpty) continue;
        final filename = dropped.name.trim().isEmpty
            ? 'attachment.bin'
            : dropped.name.trim();
        payloads.add((filename: filename, bytes: bytes));
      }
      if (payloads.isEmpty) {
        throw Exception('drop payload contains no readable files');
      }
      await _addDesktopFilePayloadsToComposerDraft(payloads);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.chat.photoFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        _setState(() {
          _attachingMedia = false;
        });
      }
    }
  }

  Future<String> _ingestComposerDraftAttachment(
    NativeAppBackend backend,
    Uint8List sessionKey,
    AttachmentDraftPayload draft,
  ) async {
    final normalizedMimeType = draft.normalizedMimeType;
    if (normalizedMimeType.toLowerCase().startsWith('image/')) {
      final lang = Localizations.localeOf(context).toLanguageTag();
      final ingested = await ingestImageAttachmentBytes(
        backend: backend,
        sessionKey: sessionKey,
        rawBytes: draft.bytes,
        inferredMimeType: normalizedMimeType,
        lang: lang,
        onBackupCandidate: (attachmentSha256) async {
          try {
            await _maybeEnqueueCloudMediaBackup(
              backend,
              sessionKey,
              attachmentSha256,
            );
          } catch (_) {}
        },
      );
      return ingested.attachmentSha256;
    }

    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final useLocalAudioTranscode = shouldUseLocalAudioTranscode(
      subscriptionStatus: subscriptionStatus,
    );

    var videoProxyEnabled = true;
    var configuredVideoProxyMaxDurationMs = kAttachmentVideoProxyMaxDurationMs;
    var configuredVideoProxyMaxBytes = kAttachmentVideoProxyMaxBytes;
    if (normalizedMimeType.toLowerCase().startsWith('video/')) {
      ContentEnrichmentConfig? contentConfig;
      try {
        contentConfig = await const RustContentEnrichmentConfigStore()
            .readContentEnrichment(sessionKey);
      } catch (_) {
        contentConfig = null;
      }

      videoProxyEnabled = contentConfig?.videoProxyEnabled ?? true;
      configuredVideoProxyMaxDurationMs = sanitizeAttachmentIngestLimit(
        (contentConfig?.videoProxyMaxDurationMs ??
                kAttachmentVideoProxyMaxDurationMs)
            .toInt(),
        kAttachmentVideoProxyMaxDurationMs,
      );
      configuredVideoProxyMaxBytes = sanitizeAttachmentIngestLimit(
        (contentConfig?.videoProxyMaxBytes ?? kAttachmentVideoProxyMaxBytes)
            .toInt(),
        kAttachmentVideoProxyMaxBytes,
      );
    }

    return ingestFileAttachmentBytes(
      backend: backend,
      sessionKey: sessionKey,
      rawBytes: draft.bytes,
      mimeType: normalizedMimeType,
      options: FileAttachmentIngestOptions(
        useLocalAudioTranscode: useLocalAudioTranscode,
        videoProxyEnabled: videoProxyEnabled,
        videoProxyMaxDurationMs: configuredVideoProxyMaxDurationMs,
        videoProxyMaxBytes: configuredVideoProxyMaxBytes,
      ),
      onBackupCandidate: (backupSha) async {
        try {
          await _maybeEnqueueCloudMediaBackup(backend, sessionKey, backupSha);
        } catch (_) {}
      },
    );
  }

  Future<void> _enqueueDraftAttachmentPostLinkEnrichment(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256,
    AttachmentDraftPayload draft,
  ) async {
    final normalizedMimeType = draft.normalizedMimeType.trim().toLowerCase();
    if (normalizedMimeType.isEmpty) return;

    if (normalizedMimeType.startsWith('image/')) {
      final lang = Localizations.localeOf(context).toLanguageTag();
      try {
        await _maybeEnqueueAttachmentAnnotationEnrichment(
          backend,
          sessionKey,
          attachmentSha256,
          lang: lang,
        );
      } catch (_) {}

      try {
        final exif = await backend.readAttachmentExifMetadata(
          sessionKey,
          sha256: attachmentSha256,
        );
        final lat = exif?.latitude;
        final lon = exif?.longitude;
        final hasValidLocation = lat != null &&
            lon != null &&
            !(lat == 0.0 && lon == 0.0) &&
            !lat.isNaN &&
            !lon.isNaN;
        if (!hasValidLocation) return;

        await _maybeEnqueueAttachmentPlaceEnrichment(
          backend,
          sessionKey,
          attachmentSha256,
          lang: lang,
        );
      } catch (_) {}
      return;
    }

    if (isAudioTranscribeCandidateMimeType(normalizedMimeType)) {
      try {
        await maybeEnqueueAudioTranscribe(
          backend: backend,
          sessionKey: sessionKey,
          attachmentSha256: attachmentSha256,
          mimeType: normalizedMimeType,
          lang: 'und',
          beforeEnqueue: () async {
            await CloudAuthScope.maybeOf(context)?.controller.getIdToken();
          },
        );
      } catch (_) {}
      return;
    }

    return;
  }

  void _refreshAfterAttachmentMutation() {
    _refresh();
    if (!_usePagination) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      unawaited(
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }
}
