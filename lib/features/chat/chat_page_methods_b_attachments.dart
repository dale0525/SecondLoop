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

  Future<void> _sendDesktopFilePayloads(
    List<({String filename, Uint8List bytes})> payloads,
  ) async {
    for (final payload in payloads) {
      final safeName = payload.filename.trim().isEmpty
          ? 'attachment.bin'
          : payload.filename.trim();
      final inferredMimeType = _inferMimeTypeFromFilename(safeName);
      if (inferredMimeType.startsWith('image/')) {
        await _sendImageAttachment(
          payload.bytes,
          inferredMimeType,
          filename: safeName,
        );
      } else {
        await _sendFileAttachment(
          payload.bytes,
          inferredMimeType,
          filename: safeName,
        );
      }
    }
  }

  Future<void> _sendDroppedDesktopFiles(List<XFile> droppedFiles) async {
    if (_sending) return;
    if (_asking) return;
    if (!_isDesktopPlatform) return;
    if (droppedFiles.isEmpty) return;

    _setState(() {
      _sending = true;
      _showAttachmentSendFeedback = true;
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
      await _sendDesktopFilePayloads(payloads);
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
          _sending = false;
          _showAttachmentSendFeedback = false;
        });
      }
    }
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

  Future<void> _maybeEnqueueAudioTranscribeEnrichment(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256, {
    required String mimeType,
  }) async {
    final normalizedMimeType = mimeType.trim().toLowerCase();
    final canTranscribe = normalizedMimeType.startsWith('audio/') ||
        normalizedMimeType.startsWith('video/');
    if (!canTranscribe) {
      return;
    }

    ContentEnrichmentConfig? contentConfig;
    try {
      contentConfig = await const RustContentEnrichmentConfigStore()
          .readContentEnrichment(sessionKey);
    } catch (_) {
      contentConfig = null;
    }

    if (!(contentConfig?.audioTranscribeEnabled ?? true)) {
      return;
    }

    try {
      await backend.enqueueAttachmentAnnotation(
        sessionKey,
        attachmentSha256: attachmentSha256,
        lang: 'und',
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      return;
    }
  }

  Future<String?> _sendFileAttachment(
    Uint8List rawBytes,
    String mimeType, {
    required String filename,
  }) async {
    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) return null;
    final backend = backendAny;
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final useLocalAudioTranscode = shouldUseLocalAudioTranscode(
      subscriptionStatus: subscriptionStatus,
    );

    final normalizedMimeType = mimeType.trim();
    Message? message;
    try {
      message = await backend.insertMessage(
        sessionKey,
        widget.conversation.id,
        role: 'user',
        content: '',
      );
      final messageId = message.id;

      if (mounted) {
        final pendingAttachment = Attachment(
          sha256: 'pending_$messageId',
          mimeType: normalizedMimeType,
          path: '',
          byteLen: rawBytes.length,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        _setState(() {
          _attachmentLinkingMessageIds.add(messageId);
          _attachmentsCacheByMessageId[messageId] = [pendingAttachment];
        });
      }
      syncEngine?.notifyLocalMutation();
      if (mounted) {
        _refreshAfterAttachmentMutation();
      }

      var videoProxyEnabled = true;
      var configuredVideoProxyMaxDurationMs =
          kAttachmentVideoProxyMaxDurationMs;
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

      final shaToLink = await ingestFileAttachmentBytes(
        backend: backend,
        sessionKey: sessionKey,
        rawBytes: rawBytes,
        mimeType: normalizedMimeType,
        options: FileAttachmentIngestOptions(
          useLocalAudioTranscode: useLocalAudioTranscode,
          videoProxyEnabled: videoProxyEnabled,
          videoProxyMaxDurationMs: configuredVideoProxyMaxDurationMs,
          videoProxyMaxBytes: configuredVideoProxyMaxBytes,
        ),
        onBackupCandidate: (backupSha) => _maybeEnqueueCloudMediaBackup(
          backend,
          sessionKey,
          backupSha,
        ),
        onMaybeEnqueueAudioTranscribe: (attachmentSha, candidateMimeType) =>
            _maybeEnqueueAudioTranscribeEnrichment(
          backend,
          sessionKey,
          attachmentSha,
          mimeType: candidateMimeType,
        ),
      );

      await backend.linkAttachmentToMessage(
        sessionKey,
        message.id,
        attachmentSha256: shaToLink,
      );
      unawaited(
        const RustAttachmentMetadataStore().upsert(
          sessionKey,
          attachmentSha256: shaToLink,
          filenames: [filename],
        ).catchError((_) {}),
      );

      syncEngine?.notifyLocalMutation();
      if (!mounted) return shaToLink;
      _setState(() {
        _attachmentLinkingMessageIds.remove(messageId);
      });
      _refreshAfterAttachmentMutation();

      return shaToLink;
    } catch (_) {
      if (message != null) {
        try {
          await backend.purgeMessageAttachments(sessionKey, message.id);
          syncEngine?.notifyLocalMutation();
          if (mounted) {
            _refreshAfterAttachmentMutation();
          }
        } catch (_) {
          // ignore cleanup failures
        }
      }
      rethrow;
    } finally {
      if (message != null && mounted) {
        final messageId = message.id;
        _setState(() {
          _attachmentLinkingMessageIds.remove(messageId);
          if (_attachmentsCacheByMessageId[messageId]
                  ?.any((item) => item.sha256.startsWith('pending_')) ==
              true) {
            _attachmentsCacheByMessageId.remove(messageId);
          }
        });
      }
    }
  }
}
