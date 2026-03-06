import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/attachments/attachment_metadata_store.dart';
import '../../core/backend/app_backend.dart';
import '../../core/backend/native_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/content_enrichment/content_enrichment_config_store.dart';
import '../../core/media_annotation/media_annotation_config_store.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../attachments/attachment_ingest_pipeline.dart';
import '../attachments/attachment_send_feedback_banner.dart';
import '../attachments/platform_exif_metadata.dart';
import '../audio_transcribe/audio_transcribe_enqueue.dart';
import '../media_backup/audio_transcode_policy.dart';
import 'share_ingest.dart';

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

  Future<void> _maybeEnqueueAttachmentPlaceEnrichment(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256, {
    required String lang,
  }) async {
    try {
      await backend.enqueueAttachmentPlace(
        sessionKey,
        attachmentSha256: attachmentSha256,
        lang: lang,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      return;
    }
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

  Future<void> _enqueueShareAttachmentPostLinkEnrichment(
    NativeAppBackend backend,
    Uint8List sessionKey,
    String attachmentSha256, {
    required String candidateMimeType,
    required String lang,
  }) async {
    final normalizedMimeType = candidateMimeType.trim().toLowerCase();
    if (normalizedMimeType.isEmpty) return;

    if (normalizedMimeType.startsWith('image/')) {
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

      final videoProxyEnabled = contentConfig?.videoProxyEnabled ?? true;
      final configuredVideoProxyMaxDurationMs = sanitizeAttachmentIngestLimit(
        (contentConfig?.videoProxyMaxDurationMs ??
                kAttachmentVideoProxyMaxDurationMs)
            .toInt(),
        kAttachmentVideoProxyMaxDurationMs,
      );
      final configuredVideoProxyMaxBytes = sanitizeAttachmentIngestLimit(
        (contentConfig?.videoProxyMaxBytes ?? kAttachmentVideoProxyMaxBytes)
            .toInt(),
        kAttachmentVideoProxyMaxBytes,
      );

      Future<String> Function(String path, String mimeType, String? filename)?
          onImage;
      Future<String> Function(String path, String mimeType, String? filename)?
          onFile;
      Future<String> Function(String url)? onUrlManifest;
      Future<void> Function(String attachmentSha256)? onAttachmentLinked;
      Future<void> Function(
        String attachmentSha256,
        ShareIngestAttachmentMetadata metadata,
      )? onUpsertAttachmentMetadata;
      if (backend is NativeAppBackend) {
        final candidateMimeTypeBySha = <String, String>{};
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
          final attachment = await backend.insertAttachment(
            sessionKey,
            bytes: buildUrlManifestAttachmentBytes(url),
            mimeType: kSecondLoopUrlManifestMimeType,
          );
          return attachment.sha256;
        };

        onFile = (path, mimeType, _) async {
          final bytes = await compute(_readFileBytes, path);
          final normalizedMimeType = mimeType.trim();
          try {
            final attachmentSha256 = await ingestFileAttachmentBytes(
              backend: backend,
              sessionKey: sessionKey,
              rawBytes: bytes,
              mimeType: normalizedMimeType,
              options: FileAttachmentIngestOptions(
                useLocalAudioTranscode: useLocalAudioTranscode,
                videoProxyEnabled: videoProxyEnabled,
                videoProxyMaxDurationMs: configuredVideoProxyMaxDurationMs,
                videoProxyMaxBytes: configuredVideoProxyMaxBytes,
              ),
              onBackupCandidate: (attachmentSha256) =>
                  _maybeEnqueueCloudMediaBackup(
                backend,
                sessionKey,
                attachmentSha256,
              ),
            );
            candidateMimeTypeBySha.putIfAbsent(
              attachmentSha256,
              () => normalizedMimeType,
            );
            return attachmentSha256;
          } finally {
            try {
              await File(path).delete();
            } catch (_) {
              // ignore
            }
          }
        };

        onImage = (path, mimeType, _) async {
          final bytes = await compute(_readFileBytes, path);
          PlatformExifMetadata? platformExif;
          try {
            platformExif =
                await PlatformExifReader.tryReadImageMetadataFromPath(path);
          } catch (_) {
            platformExif = null;
          }

          try {
            final ingested = await ingestImageAttachmentBytes(
              backend: backend,
              sessionKey: sessionKey,
              rawBytes: bytes,
              inferredMimeType: mimeType,
              lang: lang,
              platformExif: platformExif,
              onBackupCandidate: (attachmentSha256) =>
                  _maybeEnqueueCloudMediaBackup(
                backend,
                sessionKey,
                attachmentSha256,
              ),
            );
            candidateMimeTypeBySha.putIfAbsent(
              ingested.attachmentSha256,
              () => mimeType.trim(),
            );
            return ingested.attachmentSha256;
          } finally {
            try {
              await File(path).delete();
            } catch (_) {
              // ignore
            }
          }
        };

        onAttachmentLinked = (attachmentSha256) async {
          final candidateMimeType =
              candidateMimeTypeBySha[attachmentSha256]?.trim();
          if (candidateMimeType == null || candidateMimeType.isEmpty) return;
          unawaited(
            _enqueueShareAttachmentPostLinkEnrichment(
              backend,
              sessionKey,
              attachmentSha256,
              candidateMimeType: candidateMimeType,
              lang: lang,
            ).catchError((_) {}),
          );
        };
      }

      await ShareIngest.drainQueue(
        backend,
        sessionKey,
        onMutation: syncEngine?.notifyLocalMutation,
        onImage: onImage,
        onFile: onFile,
        onUrlManifest: onUrlManifest,
        onAttachmentLinked: onAttachmentLinked,
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
                          child: AttachmentSendFeedbackBanner(
                            text: context.t.sync.progressDialog.uploadingMedia,
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
