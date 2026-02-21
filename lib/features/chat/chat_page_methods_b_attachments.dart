part of 'chat_page.dart';

const String _kSecondLoopUrlManifestMimeType =
    'application/x.secondloop.url+json';
const String kSecondLoopVideoManifestMimeType =
    'application/x.secondloop.video+json';
const String _kSecondLoopUrlManifestSchema = 'secondloop.url_manifest.v1';
const int _kChatVideoProxySegmentDurationSeconds = 20 * 60;
const int _kChatVideoProxySegmentDurationMs =
    _kChatVideoProxySegmentDurationSeconds * 1000;
const int _kChatVideoProxySegmentMaxBytes = 50 * 1024 * 1024;
const int _kChatVideoProxyMaxDurationMs = 60 * 60 * 1000;
const int _kChatVideoProxyMaxBytes = 200 * 1024 * 1024;

Map<String, Object?> buildVideoManifestPayload({
  required String videoSha256,
  required String videoMimeType,
  String? videoProxySha256,
  String? posterSha256,
  String? posterMimeType,
  List<({int index, String sha256, String mimeType, int tMs, String kind})>?
      keyframes,
  String? audioSha256,
  String? audioMimeType,
  int? segmentCount,
  List<({int index, String sha256, String mimeType})>? videoSegments,
  int videoProxyMaxDurationMs = _kChatVideoProxyMaxDurationMs,
  int videoProxyMaxBytes = _kChatVideoProxyMaxBytes,
  int? videoProxyTotalBytes,
  bool videoProxyTruncated = false,
}) {
  return <String, Object?>{
    'schema': 'secondloop.video_manifest.v2',
    'video_sha256': videoSha256,
    'video_mime_type': videoMimeType,
    'original_sha256': videoSha256,
    'original_mime_type': videoMimeType,
    if (videoProxySha256 != null && videoProxySha256.trim().isNotEmpty)
      'video_proxy_sha256': videoProxySha256,
    if (posterSha256 != null && posterSha256.trim().isNotEmpty)
      'poster_sha256': posterSha256,
    if (posterMimeType != null && posterMimeType.trim().isNotEmpty)
      'poster_mime_type': posterMimeType,
    if (keyframes != null && keyframes.isNotEmpty)
      'keyframes': keyframes
          .map(
            (frame) => <String, Object?>{
              'index': frame.index,
              'sha256': frame.sha256,
              'mime_type': frame.mimeType,
              't_ms': frame.tMs,
              'kind': frame.kind,
            },
          )
          .toList(growable: false),
    if (segmentCount != null && segmentCount > 0) 'segment_count': segmentCount,
    'segment_max_duration_ms': _kChatVideoProxySegmentDurationMs,
    'segment_max_bytes': _kChatVideoProxySegmentMaxBytes,
    'video_proxy_max_duration_ms': videoProxyMaxDurationMs,
    'video_proxy_max_bytes': videoProxyMaxBytes,
    if (videoProxyTotalBytes != null && videoProxyTotalBytes > 0)
      'video_proxy_total_bytes': videoProxyTotalBytes,
    if (videoProxyTruncated) 'video_proxy_truncated': true,
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
        ContentEnrichmentConfig? contentConfig;
        try {
          contentConfig = await const RustContentEnrichmentConfigStore()
              .readContentEnrichment(sessionKey);
        } catch (_) {
          contentConfig = null;
        }

        int sanitizeVideoProxyLimit(int value, int fallback) {
          if (value <= 0) return fallback;
          return value;
        }

        final videoProxyEnabled = contentConfig?.videoProxyEnabled ?? true;
        final configuredVideoProxyMaxDurationMs = sanitizeVideoProxyLimit(
          (contentConfig?.videoProxyMaxDurationMs ??
                  _kChatVideoProxyMaxDurationMs)
              .toInt(),
          _kChatVideoProxyMaxDurationMs,
        );
        final configuredVideoProxyMaxBytes = sanitizeVideoProxyLimit(
          (contentConfig?.videoProxyMaxBytes ?? _kChatVideoProxyMaxBytes)
              .toInt(),
          _kChatVideoProxyMaxBytes,
        );

        if (!videoProxyEnabled) {
          final attachment = await backend.insertAttachment(
            sessionKey,
            bytes: rawBytes,
            mimeType: normalizedMimeType,
          );
          shaToLink = attachment.sha256;
          backupShas.add(attachment.sha256);
        } else {
          final videoProxy =
              await VideoTranscodeWorker.transcodeToSegmentedMp4Proxy(
            rawBytes,
            sourceMimeType: normalizedMimeType,
            maxSegmentDurationSeconds: _kChatVideoProxySegmentDurationSeconds,
            maxSegmentBytes: _kChatVideoProxySegmentMaxBytes,
          );
          final selectedSegments =
              selectVideoProxySegments(videoProxy.segments);
          if (!selectedSegments.hasSegments) {
            throw StateError('video_proxy_segments_empty');
          }

          final videoSegments =
              <({int index, String sha256, String mimeType})>[];
          for (final segment in selectedSegments.segments) {
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

          final primarySegment = selectedSegments.segments.first;
          final primaryVideo = videoSegments.first;

          String? posterSha256;
          String? posterMimeType;
          final keyframeRefs = <({
            int index,
            String sha256,
            String mimeType,
            int tMs,
            String kind
          })>[];
          final preview = await VideoTranscodeWorker.extractPreviewFrames(
            primarySegment.bytes,
            sourceMimeType: primarySegment.mimeType,
          );
          const resolvedKeyframeKind = 'scene';
          final posterBytes = preview.posterBytes;
          if (posterBytes != null && posterBytes.isNotEmpty) {
            final posterAttachment = await backend.insertAttachment(
              sessionKey,
              bytes: posterBytes,
              mimeType: preview.posterMimeType,
            );
            posterSha256 = posterAttachment.sha256;
            posterMimeType = posterAttachment.mimeType;
            backupShas.add(posterAttachment.sha256);
          }

          for (final frame in preview.keyframes) {
            final frameAttachment = await backend.insertAttachment(
              sessionKey,
              bytes: frame.bytes,
              mimeType: frame.mimeType,
            );
            keyframeRefs.add(
              (
                index: frame.index,
                sha256: frameAttachment.sha256,
                mimeType: frameAttachment.mimeType,
                tMs: frame.tMs,
                kind: resolvedKeyframeKind,
              ),
            );
            backupShas.add(frameAttachment.sha256);
          }

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
              videoProxySha256: primaryVideo.sha256,
              posterSha256: posterSha256,
              posterMimeType: posterMimeType,
              keyframes: keyframeRefs,
              audioSha256: audioSha256,
              audioMimeType: audioMimeType,
              segmentCount: videoSegments.length,
              videoSegments: videoSegments,
              videoProxyMaxDurationMs: configuredVideoProxyMaxDurationMs,
              videoProxyMaxBytes: configuredVideoProxyMaxBytes,
              videoProxyTotalBytes: selectedSegments.totalBytes,
              videoProxyTruncated: selectedSegments.isTruncated,
            ),
          });
          final manifestBytes = Uint8List.fromList(utf8.encode(manifest));
          final manifestAttachment = await backend.insertAttachment(
            sessionKey,
            bytes: manifestBytes,
            mimeType: kSecondLoopVideoManifestMimeType,
          );
          shaToLink = manifestAttachment.sha256;
        }
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
