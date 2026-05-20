import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/backend/attachments_backend.dart';
import '../../core/backend/app_backend.dart';
import '../../core/backend/native_backend.dart';
import '../../core/attachments/attachment_metadata_store.dart';
import '../../core/ai/ai_routing.dart';
import '../../core/ai/media_capability_source_prefs.dart';
import '../../core/ai/media_source_prefs.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/cloud_capability_auth.dart';
import '../../core/content_enrichment/content_enrichment_config_store.dart';
import '../../core/content_enrichment/docx_ocr.dart';
import '../../core/content_enrichment/docx_ocr_policy.dart';
import '../../core/content_enrichment/multimodal_ocr.dart';
import '../../core/content_enrichment/ocr_result_preference.dart';
import '../../core/content_enrichment/video_ocr_auto_policy.dart';
import '../../core/media_annotation/media_annotation_config_store.dart';
import '../../core/content_enrichment/audio_transcribe_failure_reason.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../audio_transcribe/audio_transcribe_chunk_progress.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../audio_transcribe/audio_transcribe_enqueue.dart';
import '../media_backup/cloud_media_download.dart';
import '../media_backup/cloud_media_download_ui.dart';
import '../../i18n/strings.g.dart';
import 'package:secondloop/core/models/app_models.dart';
import '../../ui/sl_surface.dart';
import 'audio_attachment_player.dart';
import 'attachment_detail_workspace.dart';
import 'attachment_detail_text_content.dart';
import 'attachment_text_editor_card.dart';
import 'attachment_payload_refresh_policy.dart';
import 'attachment_text_source_policy.dart';
import 'non_image_attachment_view.dart';
import 'platform_pdf_ocr.dart';
import 'video_keyframe_ocr_worker.dart';
import 'web_media_processing_notice.dart';

part 'attachment_viewer_page_image.dart';
part 'attachment_viewer_page_ocr.dart';
part 'attachment_viewer_page_title.dart';
part 'attachment_viewer_page_error.dart';
part 'attachment_viewer_page_recognition.dart';

class AttachmentViewerPage extends StatefulWidget {
  const AttachmentViewerPage({
    required this.attachment,
    this.cloudMediaDownload,
    this.isWebOverride,
    this.initialBytes,
    this.initialContentKind,
    this.initialChunkIndex,
    super.key,
  });

  final Attachment attachment;
  final CloudMediaDownload? cloudMediaDownload;
  final bool? isWebOverride;
  final Uint8List? initialBytes;
  final String? initialContentKind;
  final int? initialChunkIndex;

  static Future<void> openBySha(
    BuildContext context, {
    required String attachmentSha256,
    String? initialContentKind,
    int? initialChunkIndex,
  }) async {
    final backend = AppBackendScope.of(context);
    final attachment = await backend.readAttachmentBySha256(attachmentSha256);
    if (!context.mounted || attachment == null) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          AttachmentViewerPage(
            attachment: attachment,
            initialContentKind: initialContentKind,
            initialChunkIndex: initialChunkIndex,
          ),
        ),
      ),
    );
  }

  @override
  State<AttachmentViewerPage> createState() => _AttachmentViewerPageState();
}

class _AttachmentViewerPageState extends State<AttachmentViewerPage> {
  static const String _kSecondLoopUrlManifestMimeType =
      'application/x.secondloop.url+json';

  final Uint8List _nonImagePlaceholderBytes = Uint8List(0);
  Future<Uint8List>? _bytesFuture;
  Future<AttachmentExifMetadata?>? _exifFuture;
  Future<String?>? _placeFuture;
  Future<String?>? _annotationCaptionFuture;
  Future<AttachmentMetadata?>? _metadataFuture;
  Future<Map<String, Object?>?>? _annotationPayloadFuture;
  bool _loadingPlace = false;
  bool _loadingAnnotation = false;
  bool _loadingMetadata = false;
  bool _loadingAnnotationPayload = false;
  bool _retryingAttachmentRecognition = false;
  bool _awaitingAttachmentRecognitionResult = false;
  bool _preserveRetryFallbackText = false;
  String? _placeDisplayName;
  String? _annotationCaption;
  AttachmentMetadata? _metadata;
  Map<String, Object?>? _annotationPayload;
  Map<String, Object?>? _lastNonEmptyAnnotationPayload;
  AttachmentAnnotationJob? _annotationJob;
  bool _loadingAnnotationJob = false;
  bool _runningDocumentOcr = false;
  String? _documentOcrStatusText;
  String _documentOcrLanguageHints = 'device_plus_en';
  bool _attemptedSyncDownload = false;
  bool? _retryRouteAvailable;
  bool _probingRetryRoute = false;
  SyncEngine? _syncEngine;
  VoidCallback? _syncListener;
  Timer? _annotationRetryPollTimer;
  int _annotationRetryPollAttempts = 0;

  static const Duration _annotationRetryPollInterval = Duration(seconds: 2);
  static const int _annotationRetryPollMaxAttempts = 8;

  String _fileExtensionForDownload() {
    final extension =
        fileExtensionForSystemOpenMimeType(widget.attachment.mimeType);
    return extension.isEmpty ? '.bin' : extension;
  }

  String _downloadFilename() {
    final stem = widget.attachment.sha256.trim().isEmpty
        ? DateTime.now().millisecondsSinceEpoch.toString()
        : widget.attachment.sha256.trim();
    return '$stem${_fileExtensionForDownload()}';
  }

  Future<File> _materializeTempDownloadFile(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_downloadFilename()}');
    await outFile.writeAsBytes(bytes, flush: true);
    return outFile;
  }

  Future<void> _shareAttachment(Uint8List bytes) async {
    try {
      final file = await _materializeTempDownloadFile(bytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: widget.attachment.mimeType)],
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _openAttachmentWithSystem(Uint8List bytes) async {
    try {
      final file = await _materializeTempDownloadFile(bytes);
      final launched = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t.errors.couldNotOpenExternally),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _downloadAttachment(Uint8List bytes) async {
    try {
      final file = await _materializeTempDownloadFile(bytes);
      final launched = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(file.path),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytesFuture ??= _initialBytesFuture();
    final isImage = widget.attachment.mimeType.startsWith('image/');
    if (_metadataFuture == null) {
      _startMetadataLoad();
    }
    if (isImage) {
      _exifFuture ??= _loadPersistedExif();
      if (_placeFuture == null) {
        _startPlaceLoad();
      }
      if (_annotationCaptionFuture == null) {
        _startAnnotationCaptionLoad();
      }
      if (_annotationPayloadFuture == null) {
        _startAnnotationPayloadLoad();
      }
    } else {
      if (_annotationPayloadFuture == null) {
        _startAnnotationPayloadLoad();
      }
    }
    _attachSyncEngine();
    _probeRetryRouteAvailability();
  }

  Future<Uint8List> _initialBytesFuture() {
    final bytes = widget.initialBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Future<Uint8List>.value(bytes);
    }
    return _loadBytes();
  }

  void _retryLoadBytesAfterError() {
    final completer = Completer<Uint8List>();
    setState(() {
      _bytesFuture = completer.future;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('attachment_viewer_disposed'));
        }
        return;
      }
      unawaited(
        _loadBytes().then(
          (bytes) {
            if (!completer.isCompleted) completer.complete(bytes);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _stopAnnotationRetryPolling(clearState: false);
    _detachSyncEngine();
    super.dispose();
  }

  void _attachSyncEngine() {
    final engine = SyncEngineScope.maybeOf(context);
    if (identical(engine, _syncEngine)) return;
    _detachSyncEngine();

    _syncEngine = engine;
    if (engine == null) return;

    void onChange() {
      if (!mounted) return;
      final isImage = widget.attachment.mimeType.startsWith('image/');
      var didSchedule = false;
      if (isImage) {
        if (!_loadingPlace) {
          final existing = _placeDisplayName?.trim();
          if (existing == null || existing.isEmpty) {
            didSchedule = true;
            _startPlaceLoad();
          }
        }

        if (!_loadingAnnotation) {
          final existing = _annotationCaption?.trim();
          if (existing == null || existing.isEmpty) {
            didSchedule = true;
            _startAnnotationCaptionLoad();
          }
        }

        if (!_loadingAnnotationPayload &&
            shouldRefreshAttachmentAnnotationPayloadOnSync(
              payload: _annotationPayload,
              ocrRunning: false,
              ocrStatusText: null,
            )) {
          didSchedule = true;
          _startAnnotationPayloadLoad();
        }
      } else {
        if (!_loadingMetadata && _metadata == null) {
          didSchedule = true;
          _startMetadataLoad();
        }
        if (!_loadingAnnotationPayload &&
            shouldRefreshAttachmentAnnotationPayloadOnSync(
              payload: _annotationPayload,
              ocrRunning: _runningDocumentOcr,
              ocrStatusText: _documentOcrStatusText,
            )) {
          didSchedule = true;
          _startAnnotationPayloadLoad();
        }
      }

      if (didSchedule) {
        setState(() {});
      }
    }

    _syncListener = onChange;
    engine.changes.addListener(onChange);
  }

  void _detachSyncEngine() {
    final engine = _syncEngine;
    final listener = _syncListener;
    if (engine != null && listener != null) {
      engine.changes.removeListener(listener);
    }
    _syncEngine = null;
    _syncListener = null;
  }

  void _startAnnotationRetryPollingIfNeeded() {
    _stopAnnotationRetryPolling(clearState: false);
    _annotationRetryPollAttempts = 0;

    _annotationRetryPollTimer =
        Timer.periodic(_annotationRetryPollInterval, (timer) {
      if (!mounted) {
        _stopAnnotationRetryPolling(clearState: false);
        return;
      }

      _annotationRetryPollAttempts += 1;

      if (!_loadingAnnotation) {
        _startAnnotationCaptionLoad();
      }
      if (!_loadingAnnotationPayload) {
        _startAnnotationPayloadLoad();
      }
      setState(() {});

      if (!_awaitingAttachmentRecognitionResult) {
        _stopAnnotationRetryPolling(clearState: false);
        return;
      }

      if (_annotationRetryPollAttempts >= _annotationRetryPollMaxAttempts) {
        _stopAnnotationRetryPolling(clearState: true);
      }
    });
  }

  void _stopAnnotationRetryPolling({
    required bool clearState,
  }) {
    _annotationRetryPollTimer?.cancel();
    _annotationRetryPollTimer = null;
    _annotationRetryPollAttempts = 0;

    if (clearState && mounted) {
      setState(() {
        _awaitingAttachmentRecognitionResult = false;
        _documentOcrStatusText = null;
      });
    }
  }

  void _updateViewerState(VoidCallback updater) {
    if (!mounted) return;
    setState(updater);
  }

  void _startPlaceLoad() {
    _loadingPlace = true;
    _placeFuture = _loadPlaceDisplayName().then((value) {
      _placeDisplayName = value?.trim();
      return value;
    }).whenComplete(() {
      _loadingPlace = false;
    });
  }

  AttachmentDetailTextContent _resolveIntrinsicTextContentForPayload(
    Map<String, Object?>? payload,
  ) {
    return resolveAttachmentDetailTextContent(
      _decoratePayloadWithCitationTarget(payload),
      annotationCaption: null,
      mimeTypeOverride: widget.attachment.mimeType,
    );
  }

  Map<String, Object?>? _decoratePayloadWithCitationTarget(
    Map<String, Object?>? payload,
  ) {
    final initialContentKind = widget.initialContentKind?.trim() ?? '';
    final initialChunkIndex = widget.initialChunkIndex;
    if (payload == null ||
        (initialContentKind.isEmpty && initialChunkIndex == null)) {
      return payload;
    }

    final next = Map<String, Object?>.from(payload);
    if (initialContentKind.isNotEmpty) {
      next[kPreferredAttachmentContentKindKey] = initialContentKind;
    }
    if (initialChunkIndex != null) {
      next[kPreferredAttachmentChunkIndexKey] = initialChunkIndex;
    }
    return next;
  }

  void _startAnnotationCaptionLoad() {
    _loadingAnnotation = true;
    _annotationCaptionFuture = _loadAnnotationCaptionLong().then((value) {
      final nextCaption = _preserveAnnotationCaptionWhileRecognition(value);
      _annotationCaption = nextCaption;
      return nextCaption;
    }).whenComplete(() {
      _loadingAnnotation = false;
    });
  }

  void _startMetadataLoad() {
    _loadingMetadata = true;
    _metadataFuture = _loadAttachmentMetadata().then((value) {
      _metadata = value;
      return value;
    }).whenComplete(() {
      _loadingMetadata = false;
    });
  }

  void _startAnnotationPayloadLoad() {
    _loadingAnnotationPayload = true;
    _startAnnotationJobLoad();
    _annotationPayloadFuture = _loadAnnotationPayload().then((value) {
      final displayPayload = _resolveDisplayAnnotationPayload(value);
      if (!mounted) {
        _annotationPayload = displayPayload;
        return displayPayload;
      }

      _updateViewerState(() {
        _annotationPayload = displayPayload;
      });
      if (!_awaitingAttachmentRecognitionResult) {
        _stopAnnotationRetryPolling(clearState: false);
      }
      return displayPayload;
    }).whenComplete(() {
      _loadingAnnotationPayload = false;
    });
  }

  Future<Uint8List> _loadBytes() async {
    final backend = AppBackendScope.of(context);
    if (backend is! AttachmentsBackend) {
      throw StateError('Attachments backend not available');
    }
    final attachmentsBackend = backend as AttachmentsBackend;
    final sessionKey = SessionScope.of(context).sessionKey;
    try {
      return await attachmentsBackend.readAttachmentBytes(
        sessionKey,
        sha256: widget.attachment.sha256,
      );
    } catch (_) {
      if (_attemptedSyncDownload) rethrow;
      _attemptedSyncDownload = true;
      if (!mounted) rethrow;

      final downloader = widget.cloudMediaDownload ?? CloudMediaDownload();
      final idTokenGetter =
          CloudAuthScope.maybeOf(context)?.controller.getIdToken;

      var result =
          await downloader.downloadAttachmentBytesFromConfiguredSyncWithPolicy(
        backend: backend,
        sessionKey: sessionKey,
        idTokenGetter: idTokenGetter,
        sha256: widget.attachment.sha256,
        allowCellular: false,
      );
      if (!result.didDownload) {
        throw CloudMediaDownloadFailureException(result.failureReason);
      }

      return attachmentsBackend.readAttachmentBytes(
        sessionKey,
        sha256: widget.attachment.sha256,
      );
    }
  }

  Future<AttachmentExifMetadata?> _loadPersistedExif() async {
    final backend = AppBackendScope.of(context);
    if (backend is! AttachmentsBackend) return null;
    final attachmentsBackend = backend as AttachmentsBackend;
    final sessionKey = SessionScope.of(context).sessionKey;
    try {
      return await attachmentsBackend.readAttachmentExifMetadata(
        sessionKey,
        sha256: widget.attachment.sha256,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _loadPlaceDisplayName() async {
    final backend = AppBackendScope.of(context);
    if (backend is! AttachmentsBackend) return null;
    final attachmentsBackend = backend as AttachmentsBackend;
    final sessionKey = SessionScope.of(context).sessionKey;
    try {
      return await attachmentsBackend.readAttachmentPlaceDisplayName(
        sessionKey,
        sha256: widget.attachment.sha256,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _loadAnnotationCaptionLong() async {
    final backend = AppBackendScope.of(context);
    if (backend is! AttachmentsBackend) return null;
    final attachmentsBackend = backend as AttachmentsBackend;
    final sessionKey = SessionScope.of(context).sessionKey;
    try {
      return await attachmentsBackend.readAttachmentAnnotationCaptionLong(
        sessionKey,
        sha256: widget.attachment.sha256,
      );
    } catch (_) {
      return null;
    }
  }

  Future<AttachmentMetadata?> _loadAttachmentMetadata() async {
    final backend = AppBackendScope.of(context);
    if (backend is! NativeAppBackend) return null;
    final sessionKey = SessionScope.of(context).sessionKey;
    try {
      return await const DartAttachmentMetadataStore().read(
        sessionKey,
        attachmentSha256: widget.attachment.sha256,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>?> _loadAnnotationPayload() async {
    final backend = AppBackendScope.maybeOf(context);
    if (backend is! NativeAppBackend) return null;
    final sessionKey = SessionScope.of(context).sessionKey;
    try {
      final json = await backend.readAttachmentAnnotationPayloadJson(
        sessionKey,
        sha256: widget.attachment.sha256,
      );
      final raw = json?.trim();
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, Object?>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  String get _effectiveDocumentOcrLanguageHints =>
      normalizeAttachmentOcrLanguageHint(_documentOcrLanguageHints);

  bool get _canRetryAttachmentRecognition {
    if (AppBackendScope.maybeOf(context) is! NativeAppBackend) return false;
    return _retryRouteAvailable ?? true;
  }

  bool _hasAvailableMediaRoute(
    MediaSourcePreference preference, {
    required bool cloudAvailable,
    required bool hasByokProfile,
    required bool hasLocalCapability,
  }) {
    final orderedRoutes = mediaSourceFallbackOrder(preference);
    for (final route in orderedRoutes) {
      switch (route) {
        case MediaSourceRouteKind.cloudGateway:
          if (cloudAvailable) return true;
          break;
        case MediaSourceRouteKind.byok:
          if (hasByokProfile) return true;
          break;
        case MediaSourceRouteKind.needsSetup:
          break;
        case MediaSourceRouteKind.local:
          if (hasLocalCapability) return true;
          break;
      }
    }
    return false;
  }

  bool _isCloudRouteAvailableNow() {
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    if (subscriptionStatus != SubscriptionStatus.entitled) {
      return false;
    }

    final cloudScope = CloudAuthScope.maybeOf(context);
    final hasGateway =
        (cloudScope?.gatewayConfig.baseUrl ?? '').trim().isNotEmpty;
    final hasCloudAccount =
        (cloudScope?.controller.uid ?? '').trim().isNotEmpty;
    return hasGateway && hasCloudAccount;
  }

  Future<bool> _hasOpenAiByokProfile({
    required NativeAppBackend backend,
    required Uint8List sessionKey,
    required String selectedProfileId,
  }) async {
    List<LlmProfile> profiles = const <LlmProfile>[];
    try {
      profiles = await backend.listLlmProfiles(Uint8List.fromList(sessionKey));
    } catch (_) {
      return false;
    }

    final selectedId = selectedProfileId.trim();
    if (selectedId.isNotEmpty) {
      for (final profile in profiles) {
        if (profile.id != selectedId) continue;
        return profile.providerType == 'openai-compatible';
      }
    }

    for (final profile in profiles) {
      if (!profile.isActive) continue;
      if (profile.providerType != 'openai-compatible') continue;
      return true;
    }
    return false;
  }

  Future<bool> _computeRetryRouteAvailability() async {
    final backendAny = AppBackendScope.maybeOf(context);
    final sessionScope = SessionScope.maybeOf(context);
    if (backendAny is! NativeAppBackend || sessionScope == null) {
      return false;
    }

    final sessionKey = Uint8List.fromList(sessionScope.sessionKey);
    final mime = widget.attachment.mimeType.trim().toLowerCase();
    final isImage = mime.startsWith('image/');
    final isAudio = isAudioTranscribeCandidateMimeType(mime);
    final isUrlManifest = mime == _kSecondLoopUrlManifestMimeType;
    if (!isImage && !isAudio && !isUrlManifest) {
      return false;
    }

    ContentEnrichmentConfig? contentConfig;
    try {
      contentConfig = await const DartContentEnrichmentConfigStore()
          .readContentEnrichment(Uint8List.fromList(sessionKey));
    } catch (_) {
      contentConfig = null;
    }

    final backgroundEnabled = contentConfig?.mobileBackgroundEnabled ?? true;
    if (!backgroundEnabled) {
      return false;
    }

    MediaAnnotationConfig? mediaConfig;
    try {
      mediaConfig =
          await const DartMediaAnnotationConfigStore().read(sessionKey);
    } catch (_) {
      mediaConfig = null;
    }

    final hasCloudRoute = _isCloudRouteAvailableNow();
    final hasByokRoute = await _hasOpenAiByokProfile(
      backend: backendAny,
      sessionKey: sessionKey,
      selectedProfileId: mediaConfig?.byokProfileId ?? '',
    );

    if (isUrlManifest) {
      final urlFetchEnabled = contentConfig?.urlFetchEnabled ?? true;
      if (!urlFetchEnabled) return false;
      MediaSourcePreference preference;
      try {
        preference = await MediaCapabilitySourcePrefs.readUrlFetch();
      } catch (_) {
        preference = MediaSourcePreference.auto;
      }
      return _hasAvailableMediaRoute(
        preference,
        cloudAvailable: hasCloudRoute,
        hasByokProfile: hasByokRoute,
        hasLocalCapability: true,
      );
    }

    if (isAudio) {
      final audioEnabled = contentConfig?.audioTranscribeEnabled ?? false;
      if (!audioEnabled) return false;
      MediaSourcePreference preference;
      try {
        preference = await MediaCapabilitySourcePrefs.readAudio();
      } catch (_) {
        preference = MediaSourcePreference.auto;
      }
      return _hasAvailableMediaRoute(
        preference,
        cloudAvailable: hasCloudRoute,
        hasByokProfile: hasByokRoute,
        hasLocalCapability:
            MediaCapabilitySourcePrefs.supportsPlatformLocalAudioTranscribe(),
      );
    }

    final ocrEnabled = contentConfig?.ocrEnabled ?? true;
    MediaSourcePreference preference;
    try {
      preference = await MediaSourcePrefs.read();
    } catch (_) {
      preference = MediaSourcePreference.auto;
    }
    return _hasAvailableMediaRoute(
      preference,
      cloudAvailable: hasCloudRoute,
      hasByokProfile: hasByokRoute,
      hasLocalCapability: ocrEnabled,
    );
  }

  void _probeRetryRouteAvailability() {
    if (_retryRouteAvailable != null || _probingRetryRoute) return;
    _probingRetryRoute = true;
    Future<bool>.sync(_computeRetryRouteAvailability)
        .then((available) {
          if (!mounted) return;
          setState(() {
            _retryRouteAvailable = available;
          });
        })
        .catchError((_) {})
        .whenComplete(() {
          _probingRetryRoute = false;
        });
  }

  void _updateDocumentOcrLanguageHints(String value) {
    final normalized = normalizeAttachmentOcrLanguageHint(value);
    if (normalized == _documentOcrLanguageHints) return;
    setState(() {
      _documentOcrLanguageHints = normalized;
    });
  }

  Future<void> _persistContentOcrLanguageHint(
    Uint8List sessionKey,
    String languageHint,
  ) async {
    final normalized = normalizeAttachmentOcrLanguageHint(languageHint);
    try {
      const store = DartContentEnrichmentConfigStore();
      final current = await store.readContentEnrichment(sessionKey);
      if (normalizeAttachmentOcrLanguageHint(current.ocrLanguageHints) ==
          normalized) {
        return;
      }
      final next = ContentEnrichmentConfig(
        urlFetchEnabled: current.urlFetchEnabled,
        documentExtractEnabled: current.documentExtractEnabled,
        documentKeepOriginalMaxBytes: current.documentKeepOriginalMaxBytes,
        audioTranscribeEnabled: current.audioTranscribeEnabled,
        audioTranscribeEngine: current.audioTranscribeEngine,
        videoExtractEnabled: current.videoExtractEnabled,
        videoProxyEnabled: current.videoProxyEnabled,
        videoProxyMaxDurationMs: current.videoProxyMaxDurationMs,
        videoProxyMaxBytes: current.videoProxyMaxBytes,
        ocrEnabled: current.ocrEnabled,
        ocrEngineMode: current.ocrEngineMode,
        ocrLanguageHints: normalized,
        ocrPdfDpi: current.ocrPdfDpi,
        ocrPdfAutoMaxPages: current.ocrPdfAutoMaxPages,
        ocrPdfMaxPages: current.ocrPdfMaxPages,
        mobileBackgroundEnabled: current.mobileBackgroundEnabled,
        mobileBackgroundRequiresWifi: current.mobileBackgroundRequiresWifi,
        mobileBackgroundRequiresCharging:
            current.mobileBackgroundRequiresCharging,
      );
      await store.writeContentEnrichment(sessionKey, next);
    } catch (_) {
      // Best-effort preference update.
    }
  }

  bool _imageRetryNeedsOcrOptions(Map<String, Object?>? payload) {
    if (payload == null) return false;
    final selectedText = selectAttachmentDisplayText(payload);
    if (selectedText.source == AttachmentTextSource.ocr) {
      return true;
    }

    final hasOcrText = ((payload['ocr_text'] ??
                payload['ocr_text_full'] ??
                payload['ocr_text_excerpt']) ??
            '')
        .toString()
        .trim()
        .isNotEmpty;
    final hasOcrEngine =
        (payload['ocr_engine'] ?? '').toString().trim().isNotEmpty;
    return hasOcrText || hasOcrEngine;
  }

  String _resolveImageRetryOcrLanguageHint(Map<String, Object?>? payload) {
    final fromPayload = (payload?['ocr_lang_hints'] ?? '').toString().trim();
    if (fromPayload.isNotEmpty) {
      return normalizeAttachmentOcrLanguageHint(fromPayload);
    }
    return _effectiveDocumentOcrLanguageHints;
  }

  Future<void> _retryImageRecognitionWithOptionalOcrDialog(
    Map<String, Object?>? payload,
  ) async {
    if (!_imageRetryNeedsOcrOptions(payload)) {
      await _retryAttachmentRecognition();
      return;
    }

    final selectedHint = await showAttachmentOcrLanguageHintDialog(
      context,
      initialHint: _resolveImageRetryOcrLanguageHint(payload),
      title: context.t.attachments.content.rerunOcr,
      confirmLabel: context.t.attachments.content.rerunOcr,
    );
    if (selectedHint == null) return;

    _updateDocumentOcrLanguageHints(selectedHint);
    await _retryAttachmentRecognition(ocrLanguageHints: selectedHint);
  }

  Future<void> _retryAttachmentRecognition({
    String? ocrLanguageHints,
  }) async {
    if (_retryingAttachmentRecognition) return;
    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) return;

    final backend = backendAny;
    final sessionKey = SessionScope.of(context).sessionKey;
    final cloudAuthController = CloudAuthScope.maybeOf(context)?.controller;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lang = Localizations.localeOf(context).toLanguageTag();
    final normalizedMimeType = widget.attachment.mimeType.trim().toLowerCase();

    _stopAnnotationRetryPolling(clearState: false);
    setState(() {
      _retryingAttachmentRecognition = true;
      _awaitingAttachmentRecognitionResult = true;
      _preserveRetryFallbackText = true;
      _documentOcrStatusText = context.t.attachments.content.ocrRunning;
      _annotationJob = null;
    });
    try {
      final hint = (ocrLanguageHints ?? '').trim();
      if (hint.isNotEmpty) {
        unawaited(_persistContentOcrLanguageHint(sessionKey, hint));
      }

      await backend.markAttachmentAnnotationFailed(
        sessionKey,
        attachmentSha256: widget.attachment.sha256,
        attempts: 0,
        nextRetryAtMs: nowMs,
        lastError: 'manual_retry',
        nowMs: nowMs,
      );
      if (isAudioTranscribeCandidateMimeType(normalizedMimeType)) {
        await maybeEnqueueAudioTranscribe(
          backend: backend,
          sessionKey: sessionKey,
          attachmentSha256: widget.attachment.sha256,
          mimeType: normalizedMimeType,
          lang: 'und',
          respectFeatureToggle: false,
          nowMs: nowMs,
          beforeEnqueue: () =>
              bestEffortWarmCloudCapabilityAuth(cloudAuthController),
        );
      } else {
        await bestEffortWarmCloudCapabilityAuth(cloudAuthController);
        await backend.enqueueAttachmentAnnotation(
          sessionKey,
          attachmentSha256: widget.attachment.sha256,
          lang: lang,
          nowMs: nowMs,
        );
      }

      if (!mounted) return;
      _startAnnotationCaptionLoad();
      _startAnnotationPayloadLoad();
      _startAnnotationRetryPollingIfNeeded();
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      setState(() {});
    } catch (e) {
      _stopAnnotationRetryPolling(clearState: false);
      if (!mounted) return;
      setState(() {
        _awaitingAttachmentRecognitionResult = false;
        _preserveRetryFallbackText = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _retryingAttachmentRecognition = false);
      }
    }
  }

  bool get _canEditAttachmentText =>
      AppBackendScope.maybeOf(context) is AttachmentAnnotationMutationsBackend;

  AttachmentDetailTextContent _currentAttachmentTextContent() {
    return resolveAttachmentDetailTextContent(
      _decoratePayloadWithCitationTarget(_annotationPayload),
      annotationCaption: _annotationCaption,
      mimeTypeOverride: widget.attachment.mimeType,
    );
  }

  Future<void> _saveAttachmentText({
    String? summary,
    String? full,
  }) async {
    final backendAny = AppBackendScope.of(context);
    if (backendAny is! AttachmentAnnotationMutationsBackend) return;
    final annotationsBackend =
        backendAny as AttachmentAnnotationMutationsBackend;

    final current = _currentAttachmentTextContent();
    final nextSummary = summary ?? current.summary;
    final nextFull = full ?? current.full;
    final nextPayload = buildManualAttachmentTextPayload(
      existingPayload: _annotationPayload,
      summary: nextSummary,
      full: nextFull,
      mimeType: widget.attachment.mimeType,
    );

    final sessionKey = SessionScope.of(context).sessionKey;
    final lang = Localizations.localeOf(context).toLanguageTag();
    final syncEngine = SyncEngineScope.maybeOf(context);

    try {
      await annotationsBackend.markAttachmentAnnotationOkJson(
        sessionKey,
        attachmentSha256: widget.attachment.sha256,
        lang: lang,
        modelName: 'manual_edit',
        payloadJson: jsonEncode(nextPayload),
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );

      if (!mounted) return;
      syncEngine?.notifyLocalMutation();
      setState(() {
        _annotationPayload = nextPayload;
        _annotationPayloadFuture = Future.value(nextPayload);
        final nextTextContent = _resolveIntrinsicTextContentForPayload(
          nextPayload,
        );
        if (nextTextContent.hasAny) {
          _lastNonEmptyAnnotationPayload = nextPayload;
        }
        if (widget.attachment.mimeType.startsWith('image/')) {
          final nextCaption =
              (nextPayload['caption_long'] ?? '').toString().trim();
          _annotationCaption = nextCaption;
          _annotationCaptionFuture = Future.value(nextCaption);
        }
      });

      if (!mounted) return;
      if (backendAny is NativeAppBackend) {
        _startAnnotationPayloadLoad();
      }
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _saveAttachmentFull(String value) {
    return _saveAttachmentText(full: value);
  }

  List<AttachmentDetailAction> _buildWorkspaceActions(Uint8List? bytes) {
    final disabled = bytes == null || bytes.isEmpty;
    return [
      AttachmentDetailAction(
        key: const ValueKey('attachment_detail_action_share'),
        label: context.t.common.actions.share,
        icon: Icons.share_rounded,
        onPressed: disabled ? null : () => _shareAttachment(bytes),
      ),
      AttachmentDetailAction(
        key: const ValueKey('attachment_detail_action_open_with_system'),
        label: context.t.attachments.content.openWithSystem,
        icon: Icons.open_in_new_rounded,
        onPressed: disabled ? null : () => _openAttachmentWithSystem(bytes),
      ),
      AttachmentDetailAction(
        key: const ValueKey('attachment_detail_action_download'),
        label: context.t.common.actions.pull,
        icon: Icons.download_rounded,
        primary: true,
        onPressed: disabled ? null : () => _downloadAttachment(bytes),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bytesFuture = _bytesFuture;
    final metadataFuture = _metadataFuture;
    final isImage = widget.attachment.mimeType.startsWith('image/');
    final isAudio = widget.attachment.mimeType.startsWith('audio/');

    return FutureBuilder<AttachmentMetadata?>(
      future: metadataFuture,
      initialData: _metadata,
      builder: (context, metadataSnapshot) {
        final metadata = metadataSnapshot.data ?? _metadata;
        final appBarTitle = _resolveAppBarTitle(
          widget.attachment,
          metadata: metadata,
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(
              appBarTitle,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: () {
            if (!isImage && !isAudio) {
              Future<void> Function()? runOcr;
              if (_supportsDocumentOcrAttachment()) {
                runOcr = _runDocumentOcr;
              } else if (_isVideoManifestAttachment()) {
                runOcr = _runVideoManifestOcr;
              }

              Widget buildNonImageDetail(Uint8List bytes) {
                return _wrapWithRecognitionIssueBanner(
                  NonImageAttachmentView(
                    attachment: widget.attachment,
                    bytes: bytes,
                    displayTitle: appBarTitle,
                    metadataFuture: _metadataFuture,
                    initialMetadata: metadata,
                    annotationPayloadFuture: _annotationPayloadFuture,
                    initialAnnotationPayload: _annotationPayload,
                    annotationJob: _annotationJob,
                    onRunOcr: runOcr,
                    onRetryRecognition: _canRetryAttachmentRecognition
                        ? _retryAttachmentRecognition
                        : null,
                    ocrRunning: _runningDocumentOcr,
                    ocrStatusText: _documentOcrStatusText,
                    ocrLanguageHints: _effectiveDocumentOcrLanguageHints,
                    onOcrLanguageHintsChanged: _updateDocumentOcrLanguageHints,
                    onSaveFull:
                        _canEditAttachmentText ? _saveAttachmentFull : null,
                    isWebOverride: widget.isWebOverride,
                    actions: _buildWorkspaceActions(
                      bytes.isEmpty ? null : bytes,
                    ),
                    initialContentKind: widget.initialContentKind,
                    initialChunkIndex: widget.initialChunkIndex,
                  ),
                );
              }

              if (bytesFuture == null) {
                return buildNonImageDetail(_nonImagePlaceholderBytes);
              }

              return FutureBuilder<Uint8List>(
                future: bytesFuture,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null || bytes.isEmpty) {
                    return buildNonImageDetail(_nonImagePlaceholderBytes);
                  }
                  return buildNonImageDetail(bytes);
                },
              );
            }

            if (bytesFuture == null) {
              return const Center(child: CircularProgressIndicator());
            }

            return FutureBuilder(
              future: bytesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final err = snapshot.error;
                  final errorText = _attachmentLoadErrorText(err);
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.broken_image_outlined, size: 48),
                          const SizedBox(height: 12),
                          Text(errorText, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _retryLoadBytesAfterError,
                            icon: const Icon(Icons.refresh),
                            label: Text(context.t.common.actions.refresh),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final bytes = snapshot.data;
                if (bytes == null) return const SizedBox.shrink();

                if (isAudio) {
                  return _wrapWithRecognitionIssueBanner(
                    AudioAttachmentPlayerView(
                      attachment: widget.attachment,
                      bytes: bytes,
                      displayTitle: appBarTitle,
                      metadataFuture: _metadataFuture,
                      initialMetadata: metadata,
                      annotationPayloadFuture: _annotationPayloadFuture,
                      initialAnnotationPayload: _annotationPayload,
                      onRetryRecognition: _canRetryAttachmentRecognition
                          ? _retryAttachmentRecognition
                          : null,
                      onSaveFull:
                          _canEditAttachmentText ? _saveAttachmentFull : null,
                      actions: _buildWorkspaceActions(bytes),
                    ),
                  );
                }

                return _buildImageAttachmentDetail(
                  bytes,
                  actions: _buildWorkspaceActions(bytes),
                );
              },
            );
          }(),
        );
      },
    );
  }
}
