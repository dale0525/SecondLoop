import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/attachments/attachment_metadata_store.dart';
import '../../core/backend/app_backend.dart';
import '../../core/backend/native_backend.dart';
import '../../core/content_enrichment/content_enrichment_config_store.dart';
import '../../core/media_annotation/media_annotation_config_store.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../audio_transcribe/audio_transcribe_runner.dart';
import '../media_backup/audio_transcode_policy.dart';
import '../media_backup/audio_transcode_worker.dart';
import '../media_backup/image_compression.dart';
import '../media_backup/video_proxy_segment_policy.dart';
import '../media_backup/video_transcode_worker.dart';
import 'share_ingest.dart';

const int _kVideoProxySegmentDurationSeconds = 20 * 60;
const int _kVideoProxySegmentDurationMs =
    _kVideoProxySegmentDurationSeconds * 1000;
const int _kVideoProxySegmentMaxBytes = 50 * 1024 * 1024;
const int _kVideoProxyMaxDurationMs = 60 * 60 * 1000;
const int _kVideoProxyMaxBytes = 200 * 1024 * 1024;

final class ShareIngestGate extends StatefulWidget {
  const ShareIngestGate({required this.child, super.key});

  final Widget child;

  @override
  State<ShareIngestGate> createState() => _ShareIngestGateState();
}

final class _ShareIngestGateState extends State<ShareIngestGate>
    with WidgetsBindingObserver {
  bool _draining = false;
  bool _showDrainFeedback = false;
  Object? _backendIdentity;
  Uint8List? _sessionKey;
  StreamSubscription<void>? _drainSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _drainSubscription = ShareIngest.drainRequests.listen((_) {
      unawaited(_drain());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _drainSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_drain());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    final shouldReuse = identical(_backendIdentity, backend) &&
        _bytesEqual(_sessionKey, sessionKey);
    if (shouldReuse) return;

    _backendIdentity = backend;
    _sessionKey = Uint8List.fromList(sessionKey);

    unawaited(_drain());
  }

  bool _bytesEqual(Uint8List? a, Uint8List b) {
    if (a == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _setDrainFeedbackVisible(bool visible) {
    if (!mounted) return;
    if (_showDrainFeedback == visible) return;
    setState(() => _showDrainFeedback = visible);
  }

  Future<void> _maybeEnqueueCloudMediaBackup(
    AppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256,
  ) async {
    if (backend is! NativeAppBackend) return;

    final store = SyncConfigStore();
    final backendType = await store.readBackendType();
    if (backendType != SyncBackendType.managedVault &&
        backendType != SyncBackendType.webdav) {
      return;
    }

    final enabled = await store.readCloudMediaBackupEnabled();
    if (!enabled) return;

    await backend.enqueueCloudMediaBackup(
      sessionKey,
      attachmentSha256: attachmentSha256,
      desiredVariant: 'original',
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _maybeEnqueueAttachmentAnnotationEnrichment(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256, {
    required String lang,
  }) async {
    MediaAnnotationConfig? config;
    try {
      config = await const RustMediaAnnotationConfigStore().read(sessionKey);
    } catch (_) {
      config = null;
    }
    if (config == null || !config.annotateEnabled) return;

    await backend.enqueueAttachmentAnnotation(
      sessionKey,
      attachmentSha256: attachmentSha256,
      lang: lang,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _maybeEnqueueAudioTranscribeEnrichment(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256, {
    required String mimeType,
  }) async {
    if (!looksLikeAudioMimeType(mimeType)) return;

    ContentEnrichmentConfig? config;
    try {
      config = await const RustContentEnrichmentConfigStore()
          .readContentEnrichment(sessionKey);
    } catch (_) {
      config = null;
    }
    if (config == null || !config.audioTranscribeEnabled) return;

    await backend.enqueueAttachmentAnnotation(
      sessionKey,
      attachmentSha256: attachmentSha256,
      lang: 'und',
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final lang = Localizations.localeOf(context).toLanguageTag();
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;

    var feedbackVisible = false;
    try {
      feedbackVisible = await ShareIngest.hasPendingPayloads();
      if (!feedbackVisible) return;
      _setDrainFeedbackVisible(true);
      final useLocalAudioTranscode = shouldUseLocalAudioTranscode(
        subscriptionStatus: subscriptionStatus,
      );

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
        (contentConfig?.videoProxyMaxDurationMs ?? _kVideoProxyMaxDurationMs)
            .toInt(),
        _kVideoProxyMaxDurationMs,
      );
      final configuredVideoProxyMaxBytes = sanitizeVideoProxyLimit(
        (contentConfig?.videoProxyMaxBytes ?? _kVideoProxyMaxBytes).toInt(),
        _kVideoProxyMaxBytes,
      );

      Future<String> Function(String path, String mimeType, String? filename)?
          onImage;
      Future<String> Function(String path, String mimeType, String? filename)?
          onFile;
      Future<String> Function(String url)? onUrlManifest;
      Future<void> Function(
        String attachmentSha256,
        ShareIngestAttachmentMetadata metadata,
      )? onUpsertAttachmentMetadata;
      if (backend is NativeAppBackend) {
        const metadataStore = RustAttachmentMetadataStore();
        onUpsertAttachmentMetadata = (sha256, metadata) async {
          try {
            await metadataStore.upsert(
              sessionKey,
              attachmentSha256: sha256,
              title: metadata.title,
              filenames: metadata.filenames,
              sourceUrls: metadata.sourceUrls,
            );
          } catch (_) {
            // ignore
          }
        };

        onUrlManifest = (url) async {
          final manifest = jsonEncode({
            'schema': 'secondloop.url_manifest.v1',
            'url': url.trim(),
          });
          final bytes = Uint8List.fromList(utf8.encode(manifest));
          final attachment = await backend.insertAttachment(
            sessionKey,
            bytes: bytes,
            mimeType: 'application/x.secondloop.url+json',
          );
          return attachment.sha256;
        };

        onFile = (path, mimeType, filename) async {
          final bytes = await compute(_readFileBytes, path);
          final normalizedMimeType = mimeType.trim();

          if (normalizedMimeType.startsWith('video/')) {
            if (!videoProxyEnabled) {
              final attachment = await backend.insertAttachment(
                sessionKey,
                bytes: bytes,
                mimeType: normalizedMimeType,
              );
              unawaited(_maybeEnqueueCloudMediaBackup(
                backend,
                sessionKey,
                attachment.sha256,
              ));

              try {
                await File(path).delete();
              } catch (_) {
                // ignore
              }

              return attachment.sha256;
            }

            final videoProxy =
                await VideoTranscodeWorker.transcodeToSegmentedMp4Proxy(
              bytes,
              sourceMimeType: normalizedMimeType,
              maxSegmentDurationSeconds: _kVideoProxySegmentDurationSeconds,
              maxSegmentBytes: _kVideoProxySegmentMaxBytes,
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
              unawaited(_maybeEnqueueCloudMediaBackup(
                backend,
                sessionKey,
                segmentAttachment.sha256,
              ));
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
              unawaited(_maybeEnqueueCloudMediaBackup(
                backend,
                sessionKey,
                posterAttachment.sha256,
              ));
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
              unawaited(_maybeEnqueueCloudMediaBackup(
                backend,
                sessionKey,
                frameAttachment.sha256,
              ));
            }

            String? audioSha256;
            String? audioMimeType;
            final audioProxy = await AudioTranscodeWorker.transcodeToM4aProxy(
              bytes,
              sourceMimeType: normalizedMimeType,
            );
            if (audioProxy.didTranscode &&
                audioProxy.bytes.isNotEmpty &&
                looksLikeAudioMimeType(audioProxy.mimeType)) {
              final audioAttachment = await backend.insertAttachment(
                sessionKey,
                bytes: audioProxy.bytes,
                mimeType: audioProxy.mimeType,
              );
              audioSha256 = audioAttachment.sha256;
              audioMimeType = audioAttachment.mimeType;
              unawaited(_maybeEnqueueCloudMediaBackup(
                backend,
                sessionKey,
                audioAttachment.sha256,
              ));
              unawaited(
                _maybeEnqueueAudioTranscribeEnrichment(
                  backend,
                  sessionKey,
                  audioAttachment.sha256,
                  mimeType: audioAttachment.mimeType,
                ).catchError((_) {}),
              );
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
              mimeType: 'application/x.secondloop.video+json',
            );

            try {
              await File(path).delete();
            } catch (_) {
              // ignore
            }

            return manifestAttachment.sha256;
          }

          if (normalizedMimeType.startsWith('audio/')) {
            final proxy = useLocalAudioTranscode
                ? await AudioTranscodeWorker.transcodeToM4aProxy(
                    bytes,
                    sourceMimeType: normalizedMimeType,
                  )
                : AudioTranscodeResult(
                    bytes: bytes,
                    mimeType: normalizedMimeType,
                    didTranscode: false,
                  );
            final attachment = await backend.insertAttachment(
              sessionKey,
              bytes: proxy.bytes,
              mimeType: proxy.mimeType,
            );
            unawaited(_maybeEnqueueCloudMediaBackup(
              backend,
              sessionKey,
              attachment.sha256,
            ));
            unawaited(
              _maybeEnqueueAudioTranscribeEnrichment(
                backend,
                sessionKey,
                attachment.sha256,
                mimeType: proxy.mimeType,
              ).catchError((_) {}),
            );

            try {
              await File(path).delete();
            } catch (_) {
              // ignore
            }

            return attachment.sha256;
          }

          final attachment = await backend.insertAttachment(
            sessionKey,
            bytes: bytes,
            mimeType: normalizedMimeType,
          );
          unawaited(_maybeEnqueueCloudMediaBackup(
            backend,
            sessionKey,
            attachment.sha256,
          ));

          try {
            await File(path).delete();
          } catch (_) {
            // ignore
          }

          return attachment.sha256;
        };

        onImage = (path, mimeType, _) async {
          final bytes = await compute(_readFileBytes, path);
          final compressed =
              await compressImageForStorage(bytes, mimeType: mimeType);
          final attachment = await backend.insertAttachment(
            sessionKey,
            bytes: compressed.bytes,
            mimeType: compressed.mimeType,
          );
          unawaited(_maybeEnqueueCloudMediaBackup(
            backend,
            sessionKey,
            attachment.sha256,
          ));
          unawaited(
            _maybeEnqueueAttachmentAnnotationEnrichment(
              backend,
              sessionKey,
              attachment.sha256,
              lang: lang,
            ).catchError((_) {}),
          );
          try {
            await File(path).delete();
          } catch (_) {
            // ignore
          }
          return attachment.sha256;
        };
      }

      await ShareIngest.drainQueue(
        backend,
        sessionKey,
        onMutation: syncEngine?.notifyLocalMutation,
        onImage: onImage,
        onFile: onFile,
        onUrlManifest: onUrlManifest,
        onUpsertAttachmentMetadata: onUpsertAttachmentMetadata,
      );
    } finally {
      _draining = false;
      if (feedbackVisible) {
        _setDrainFeedbackVisible(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          ignoring: !_showDrainFeedback,
          child: SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: !_showDrainFeedback
                      ? const SizedBox.shrink()
                      : ConstrainedBox(
                          key: const ValueKey('share_ingest_feedback'),
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: colorScheme.outlineVariant,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.shadow.withOpacity(0.14),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      context.t.sync.progressDialog.preparing,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: colorScheme.onSurface,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Uint8List _readFileBytes(String path) => File(path).readAsBytesSync();

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
  int videoProxyMaxDurationMs = _kVideoProxyMaxDurationMs,
  int videoProxyMaxBytes = _kVideoProxyMaxBytes,
  int? videoProxyTotalBytes,
  bool videoProxyTruncated = false,
}) {
  return <String, Object?>{
    'schema': 'secondloop.video_manifest.v2',
    'video_sha256': videoSha256,
    'video_mime_type': videoMimeType,
    // Backward-compatible fields for readers that still expect v1 keys.
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
    'segment_max_duration_ms': _kVideoProxySegmentDurationMs,
    'segment_max_bytes': _kVideoProxySegmentMaxBytes,
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
