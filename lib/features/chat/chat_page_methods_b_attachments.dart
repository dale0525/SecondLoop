part of 'chat_page.dart';

const String _kSecondLoopUrlManifestMimeType =
    'application/x.secondloop.url+json';
const String _kSecondLoopUrlManifestSchema = 'secondloop.url_manifest.v1';

Map<String, Object?> buildVideoManifestPayload({
  required String videoSha256,
  required String videoMimeType,
  String? audioSha256,
  String? audioMimeType,
  int? segmentCount,
  List<({int index, String sha256, String mimeType})>? videoSegments,
}) {
  return <String, Object?>{
    'schema': 'secondloop.video_manifest.v2',
    'video_sha256': videoSha256,
    'video_mime_type': videoMimeType,
    'original_sha256': videoSha256,
    'original_mime_type': videoMimeType,
    if (segmentCount != null && segmentCount > 0) 'segment_count': segmentCount,
    'segment_max_duration_ms': 20 * 60 * 1000,
    'segment_max_bytes': 50 * 1024 * 1024,
    if (videoSegments != null && videoSegments.isNotEmpty)
      'video_segments': videoSegments
          .map(
            (segment) => <String, Object?>{
              'index': segment.index,
              'sha256': segment.sha256,
              'mime_type': segment.mimeType,
            },
          )
          .toList(growable: false),
    if (audioSha256 != null && audioSha256.trim().isNotEmpty)
      'audio_sha256': audioSha256,
    if (audioMimeType != null && audioMimeType.trim().isNotEmpty)
      'audio_mime_type': audioMimeType,
  };
}

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

      String shaToLink;
      final backupShas = <String>[];
      if (normalizedMimeType.startsWith('video/')) {
        final videoProxy =
            await VideoTranscodeWorker.transcodeToSegmentedMp4Proxy(
          rawBytes,
          sourceMimeType: normalizedMimeType,
          maxSegmentDurationSeconds: 20 * 60,
          maxSegmentBytes: 50 * 1024 * 1024,
        );
        if (!videoProxy.isStrictVideoProxy) {
          throw StateError('video_proxy_transcode_failed');
        }

        final videoSegments = <({int index, String sha256, String mimeType})>[];
        for (final segment in videoProxy.segments) {
          final segmentAttachment = await backend.insertAttachment(
            sessionKey,
            bytes: segment.bytes,
            mimeType: segment.mimeType,
          );
          videoSegments.add(
            (
              index: segment.index,
              sha256: segmentAttachment.sha256,
              mimeType: segmentAttachment.mimeType,
            ),
          );
          backupShas.add(segmentAttachment.sha256);
        }
        if (videoSegments.isEmpty) {
          throw StateError('video_proxy_segments_empty');
        }

        final primaryVideo = videoSegments.first;

        String? audioSha256;
        String? audioMimeType;
        final audioProxy = await AudioTranscodeWorker.transcodeToM4aProxy(
          rawBytes,
          sourceMimeType: normalizedMimeType,
        );
        if (audioProxy.didTranscode &&
            audioProxy.bytes.isNotEmpty &&
            audioProxy.mimeType.trim().toLowerCase().startsWith('audio/')) {
          final audioAttachment = await backend.insertAttachment(
            sessionKey,
            bytes: audioProxy.bytes,
            mimeType: audioProxy.mimeType,
          );
          audioSha256 = audioAttachment.sha256;
          audioMimeType = audioAttachment.mimeType;
          backupShas.add(audioAttachment.sha256);
        }

        final manifest = jsonEncode({
          ...buildVideoManifestPayload(
            videoSha256: primaryVideo.sha256,
            videoMimeType: primaryVideo.mimeType,
            audioSha256: audioSha256,
            audioMimeType: audioMimeType,
            segmentCount: videoSegments.length,
            videoSegments: videoSegments,
          ),
        });
        final manifestBytes = Uint8List.fromList(utf8.encode(manifest));
        final manifestAttachment = await backend.insertAttachment(
          sessionKey,
          bytes: manifestBytes,
          mimeType: 'application/x.secondloop.video+json',
        );
        shaToLink = manifestAttachment.sha256;
      } else if (normalizedMimeType.startsWith('audio/')) {
        final proxy = useLocalAudioTranscode
            ? await AudioTranscodeWorker.transcodeToM4aProxy(
                rawBytes,
                sourceMimeType: normalizedMimeType,
              )
            : AudioTranscodeResult(
                bytes: rawBytes,
                mimeType: normalizedMimeType,
                didTranscode: false,
              );
        final attachment = await backend.insertAttachment(
          sessionKey,
          bytes: proxy.bytes,
          mimeType: proxy.mimeType,
        );
        shaToLink = attachment.sha256;
        backupShas.add(attachment.sha256);
      } else {
        final attachment = await backend.insertAttachment(
          sessionKey,
          bytes: rawBytes,
          mimeType: normalizedMimeType,
        );
        shaToLink = attachment.sha256;
        backupShas.add(attachment.sha256);
      }

      for (final backupSha in backupShas.toSet()) {
        unawaited(
          _maybeEnqueueCloudMediaBackup(
            backend,
            sessionKey,
            backupSha,
          ),
        );
      }

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
