part of 'chat_page.dart';

extension _ChatPageStateMethodsBAttachments on _ChatPageState {
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
    try {
      await const RustAttachmentMetadataStore().upsert(
        sessionKey,
        attachmentSha256: shaToLink,
        filenames: [filename],
      );
    } catch (_) {
      // ignore
    }

    syncEngine?.notifyLocalMutation();
    if (!mounted) return shaToLink;
    _refresh();

    if (_usePagination) {
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

    return shaToLink;
  }
}
