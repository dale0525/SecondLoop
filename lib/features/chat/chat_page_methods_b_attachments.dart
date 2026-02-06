part of 'chat_page.dart';

const String _kSecondLoopUrlManifestMimeType =
    'application/x.secondloop.url+json';
const String _kSecondLoopUrlManifestSchema = 'secondloop.url_manifest.v1';

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
      final manifest = jsonEncode({
        'schema': _kSecondLoopUrlManifestSchema,
        'url': trimmed,
      });
      final manifestBytes = Uint8List.fromList(utf8.encode(manifest));
      final attachment = await backend.insertAttachment(
        sessionKey,
        bytes: manifestBytes,
        mimeType: _kSecondLoopUrlManifestMimeType,
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
        await _sendImageAttachment(payload.bytes, inferredMimeType);
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
      if (mounted) _setState(() => _sending = false);
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

    final normalizedMimeType = mimeType.trim();

    String shaToLink;
    late final String shaToBackup;
    if (normalizedMimeType.startsWith('video/')) {
      final original = await backend.insertAttachment(
        sessionKey,
        bytes: rawBytes,
        mimeType: normalizedMimeType,
      );
      shaToBackup = original.sha256;

      final manifest = jsonEncode({
        'schema': 'secondloop.video_manifest.v1',
        'original_sha256': original.sha256,
        'original_mime_type': normalizedMimeType,
      });
      final manifestBytes = Uint8List.fromList(utf8.encode(manifest));
      final manifestAttachment = await backend.insertAttachment(
        sessionKey,
        bytes: manifestBytes,
        mimeType: 'application/x.secondloop.video+json',
      );
      shaToLink = manifestAttachment.sha256;
    } else {
      final attachment = await backend.insertAttachment(
        sessionKey,
        bytes: rawBytes,
        mimeType: normalizedMimeType,
      );
      shaToLink = attachment.sha256;
      shaToBackup = attachment.sha256;
    }

    unawaited(
      _maybeEnqueueCloudMediaBackup(
        backend,
        sessionKey,
        shaToBackup,
      ),
    );

    final message = await backend.insertMessage(
      sessionKey,
      widget.conversation.id,
      role: 'user',
      content: '',
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
    _refreshAfterAttachmentMutation();

    return shaToLink;
  }
}
