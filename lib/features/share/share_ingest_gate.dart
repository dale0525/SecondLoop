import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/attachments/attachment_metadata_store.dart';
import '../../core/backend/app_backend.dart';
import '../../core/backend/native_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/cloud_capability_auth.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../../i18n/strings.g.dart';
import '../attachments/attachment_ingest_options_resolver.dart';
import '../attachments/attachment_ingest_pipeline.dart';
import '../attachments/attachment_processing_status.dart';
import '../attachments/attachment_post_link_enrichment.dart';
import '../attachments/attachment_url_sender.dart';
import '../attachments/attachment_send_feedback_banner.dart';
import '../attachments/platform_exif_metadata.dart';
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
  AttachmentProcessingStage? _feedbackStage;
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

  void _setFeedbackStage(AttachmentProcessingStage? stage) {
    if (!mounted) return;
    if (_feedbackStage == stage) return;
    setState(() => _feedbackStage = stage);
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
      _setFeedbackStage(AttachmentProcessingStage.preparing);
      _setDrainFeedbackVisible(true);
      await Future<void>.delayed(Duration.zero);
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

        onUrlManifest = (url) => insertUrlManifestAttachment(
              backend: backend,
              sessionKey: sessionKey,
              url: url,
            );

        onFile = (path, mimeType, _) async {
          final bytes = await compute(_readFileBytes, path);
          final normalizedMimeType = mimeType.trim();
          final ingestOptions = await resolveFileAttachmentIngestOptions(
            sessionKey: sessionKey,
            mimeType: normalizedMimeType,
            subscriptionStatus: subscriptionStatus,
          );
          try {
            final attachmentSha256 = await ingestFileAttachmentBytes(
              backend: backend,
              sessionKey: sessionKey,
              rawBytes: bytes,
              mimeType: normalizedMimeType,
              options: ingestOptions,
              onStage: _setFeedbackStage,
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
            _setFeedbackStage(AttachmentProcessingStage.preparing);
            final ingested = await ingestImageAttachmentBytes(
              backend: backend,
              sessionKey: sessionKey,
              rawBytes: bytes,
              inferredMimeType: mimeType,
              lang: lang,
              platformExif: platformExif,
              onStage: _setFeedbackStage,
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
            runAttachmentPostLinkEnrichmentForMimeType(
              backend: backend,
              sessionKey: sessionKey,
              attachmentSha256: attachmentSha256,
              mimeType: candidateMimeType,
              lang: lang,
              beforeEnqueueImageAnnotation: () =>
                  bestEffortWarmCloudCapabilityAuth(
                CloudAuthScope.maybeOf(context)?.controller,
              ),
              beforeEnqueueAudioTranscribe: () =>
                  bestEffortWarmCloudCapabilityAuth(
                CloudAuthScope.maybeOf(context)?.controller,
              ),
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
        _setFeedbackStage(null);
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
                            text: _feedbackStage == null
                                ? context.t.sync.progressDialog.uploadingMedia
                                : attachmentProcessingStageLabel(
                                    context.t,
                                    _feedbackStage!,
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
