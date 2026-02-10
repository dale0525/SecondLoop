import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/backend/attachments_backend.dart';
import '../../core/backend/app_backend.dart';
import '../../core/backend/native_app_dir.dart';
import '../../core/backend/native_backend.dart';
import '../../core/attachments/attachment_metadata_store.dart';
import '../../core/ai/ai_routing.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/content_enrichment/docx_ocr.dart';
import '../../core/content_enrichment/docx_ocr_policy.dart';
import '../../core/content_enrichment/multimodal_ocr.dart';
import '../../core/content_enrichment/ocr_result_preference.dart';
import '../../core/media_annotation/media_annotation_config_store.dart';
import '../../core/media_enrichment/media_enrichment_availability.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../media_backup/cloud_media_download.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/api/content_extract.dart' as rust_content_extract;
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import 'audio_attachment_player.dart';
import 'attachment_payload_refresh_policy.dart';
import 'image_exif_metadata.dart';
import 'non_image_attachment_view.dart';
import 'platform_pdf_ocr.dart';
import 'video_keyframe_ocr_worker.dart';

part 'attachment_viewer_page_ocr.dart';

class AttachmentViewerPage extends StatefulWidget {
  const AttachmentViewerPage({
    required this.attachment,
    this.cloudMediaDownload,
    super.key,
  });

  final Attachment attachment;
  final CloudMediaDownload? cloudMediaDownload;

  @override
  State<AttachmentViewerPage> createState() => _AttachmentViewerPageState();
}

class _AttachmentViewerPageState extends State<AttachmentViewerPage> {
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
  String? _placeDisplayName;
  String? _annotationCaption;
  AttachmentMetadata? _metadata;
  Map<String, Object?>? _annotationPayload;
  bool _editingAnnotationCaption = false;
  bool _savingAnnotationCaption = false;
  bool _runningDocumentOcr = false;
  String? _documentOcrStatusText;
  String _documentOcrLanguageHints = 'device_plus_en';
  TextEditingController? _annotationCaptionController;
  Timer? _inlinePlaceResolveTimer;
  bool _inlinePlaceResolveScheduled = false;
  bool _attemptedSyncDownload = false;
  SyncEngine? _syncEngine;
  VoidCallback? _syncListener;

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
    _bytesFuture ??= _loadBytes();
    final isImage = widget.attachment.mimeType.startsWith('image/');
    if (isImage) {
      _exifFuture ??= _loadPersistedExif();
      if (_placeFuture == null) {
        _startPlaceLoad();
      }
      if (_annotationCaptionFuture == null) {
        _startAnnotationCaptionLoad();
      }
    } else {
      if (_metadataFuture == null) {
        _startMetadataLoad();
      }
      if (_annotationPayloadFuture == null) {
        _startAnnotationPayloadLoad();
      }
    }
    _attachSyncEngine();
  }

  @override
  void dispose() {
    _inlinePlaceResolveTimer?.cancel();
    _annotationCaptionController?.dispose();
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

  void _startAnnotationCaptionLoad() {
    _loadingAnnotation = true;
    _annotationCaptionFuture = _loadAnnotationCaptionLong().then((value) {
      _annotationCaption = value?.trim();
      return value;
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
    _annotationPayloadFuture = _loadAnnotationPayload().then((value) {
      _annotationPayload = value;
      final ocrText =
          ((value?['ocr_text_excerpt'] ?? value?['ocr_text_full']) ?? '')
              .toString()
              .trim();
      if (ocrText.isNotEmpty) {
        _documentOcrStatusText = null;
      }
      return value;
    }).whenComplete(() {
      _loadingAnnotationPayload = false;
    });
  }

  void _maybeScheduleInlinePlaceResolve({
    required double? latitude,
    required double? longitude,
  }) {
    if (_inlinePlaceResolveScheduled) return;
    if (latitude == null || longitude == null) return;
    if (latitude == 0.0 && longitude == 0.0) return;
    final existing = _placeDisplayName?.trim();
    if (existing != null && existing.isNotEmpty) return;
    if (_loadingPlace) return;

    _inlinePlaceResolveScheduled = true;
    _inlinePlaceResolveTimer?.cancel();
    _inlinePlaceResolveTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted) return;
      final current = _placeDisplayName?.trim();
      if (current != null && current.isNotEmpty) return;
      if (_loadingPlace) return;
      unawaited(_resolvePlaceInline(latitude: latitude, longitude: longitude));
    });
  }

  Future<void> _resolvePlaceInline({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final backendAny = AppBackendScope.of(context);
      if (backendAny is! NativeAppBackend) return;
      final backend = backendAny;
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);
      final lang = Localizations.localeOf(context).toLanguageTag();
      final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
          SubscriptionStatus.unknown;
      final cloudAuthScope = CloudAuthScope.maybeOf(context);
      final gatewayConfig =
          cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;

      String? idToken;
      try {
        idToken = await cloudAuthScope?.controller.getIdToken();
      } catch (_) {
        idToken = null;
      }
      if (!mounted) return;

      final availability = resolveMediaEnrichmentAvailability(
        subscriptionStatus: subscriptionStatus,
        cloudIdToken: idToken?.trim(),
        gatewayBaseUrl: gatewayConfig.baseUrl,
      );
      if (!availability.geoReverseAvailable) return;

      final payloadJson = await backend.geoReverseCloudGateway(
        gatewayBaseUrl: gatewayConfig.baseUrl,
        idToken: idToken!.trim(),
        lat: latitude,
        lon: longitude,
        lang: lang,
      );
      await backend.markAttachmentPlaceOkJson(
        Uint8List.fromList(sessionKey),
        attachmentSha256: widget.attachment.sha256,
        lang: lang,
        payloadJson: payloadJson,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );

      if (!mounted) return;
      syncEngine?.notifyExternalChange();
      setState(() => _startPlaceLoad());
    } catch (_) {
      // Best-effort fallback; background runner will keep retrying.
      return;
    }
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
      if (result.needsCellularConfirmation) {
        throw StateError('media_download_requires_wifi');
      }
      if (!result.didDownload) rethrow;

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
      return await const RustAttachmentMetadataStore().read(
        sessionKey,
        attachmentSha256: widget.attachment.sha256,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>?> _loadAnnotationPayload() async {
    final backend = AppBackendScope.of(context);
    if (backend is! NativeAppBackend) return null;
    final sessionKey = SessionScope.of(context).sessionKey;
    final appDir = await getNativeAppDir();
    try {
      final json =
          await rust_content_extract.dbReadAttachmentAnnotationPayloadJson(
        appDir: appDir,
        key: sessionKey,
        attachmentSha256: widget.attachment.sha256,
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

  void _updateDocumentOcrLanguageHints(String value) {
    final normalized = normalizeAttachmentOcrLanguageHint(value);
    if (normalized == _documentOcrLanguageHints) return;
    setState(() {
      _documentOcrLanguageHints = normalized;
    });
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }

  Widget _buildMetadataCard(
    BuildContext context, {
    required int byteLen,
    required DateTime? capturedAt,
    required double? latitude,
    required double? longitude,
    required String? placeDisplayName,
  }) {
    final placeName = placeDisplayName?.trim();
    final hasPlaceName = placeName != null && placeName.isNotEmpty;
    final hasLocation = latitude != null &&
        longitude != null &&
        !(latitude == 0.0 && longitude == 0.0);

    return SlSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.t.attachments.metadata.size,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _formatBytes(byteLen),
            key: const ValueKey('attachment_metadata_size'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (capturedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              context.t.attachments.metadata.capturedAt,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Text(
              formatCapturedAt(capturedAt),
              key: const ValueKey('attachment_metadata_captured_at'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (hasLocation || hasPlaceName) ...[
            const SizedBox(height: 10),
            Text(
              context.t.attachments.metadata.location,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            if (hasPlaceName)
              Text(
                placeName,
                key: const ValueKey('attachment_metadata_location_name'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (hasPlaceName && hasLocation) const SizedBox(height: 2),
            if (hasLocation)
              Text(
                formatLatLon(latitude, longitude),
                key: const ValueKey('attachment_metadata_location'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnnotationCard(
    BuildContext context, {
    required String captionLong,
  }) {
    final caption = captionLong.trim();
    if (caption.isEmpty) return const SizedBox.shrink();

    Future<void> save() async {
      if (_savingAnnotationCaption) return;
      final controller = _annotationCaptionController;
      if (controller == null) return;

      final nextCaption = controller.text.trim();
      if (nextCaption.isEmpty) return;

      final backend = AppBackendScope.of(context);
      if (backend is! AttachmentAnnotationMutationsBackend) return;
      final annotationsBackend =
          backend as AttachmentAnnotationMutationsBackend;
      final sessionKey = SessionScope.of(context).sessionKey;
      final syncEngine = SyncEngineScope.maybeOf(context);

      setState(() => _savingAnnotationCaption = true);
      try {
        final payload = jsonEncode({
          'caption_long': nextCaption,
          'tags': null,
          'ocr_text': null,
        });
        await annotationsBackend.markAttachmentAnnotationOkJson(
          sessionKey,
          attachmentSha256: widget.attachment.sha256,
          lang: Localizations.localeOf(context).toLanguageTag(),
          modelName: 'manual_edit',
          payloadJson: payload,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );
        syncEngine?.notifyLocalMutation();

        if (!mounted) return;
        setState(() {
          _savingAnnotationCaption = false;
          _editingAnnotationCaption = false;
          _annotationCaptionController?.dispose();
          _annotationCaptionController = null;
          _startAnnotationCaptionLoad();
        });
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t.errors.saveFailed(error: '$e')),
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() => _savingAnnotationCaption = false);
      }
    }

    void beginEdit() {
      _annotationCaptionController?.dispose();
      _annotationCaptionController = TextEditingController(text: caption);
      setState(() => _editingAnnotationCaption = true);
    }

    void cancelEdit() {
      _annotationCaptionController?.dispose();
      _annotationCaptionController = null;
      setState(() => _editingAnnotationCaption = false);
    }

    final canEdit =
        AppBackendScope.of(context) is AttachmentAnnotationMutationsBackend;

    return SlSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t.settings.mediaAnnotation.title,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              if (!_editingAnnotationCaption && canEdit)
                IconButton(
                  key: const ValueKey('attachment_annotation_edit'),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: context.t.common.actions.edit,
                  onPressed: beginEdit,
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (!_editingAnnotationCaption)
            Text(
              caption,
              key: const ValueKey('attachment_annotation_caption'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (_editingAnnotationCaption) ...[
            TextField(
              key: const ValueKey('attachment_annotation_edit_field'),
              controller: _annotationCaptionController,
              enabled: !_savingAnnotationCaption,
              maxLines: null,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const ValueKey('attachment_annotation_edit_cancel'),
                  onPressed: _savingAnnotationCaption ? null : cancelEdit,
                  child: Text(context.t.common.actions.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('attachment_annotation_edit_save'),
                  onPressed:
                      _savingAnnotationCaption ? null : () => unawaited(save()),
                  child: Text(context.t.common.actions.save),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _resolveAppBarTitle(
    Attachment attachment, {
    required AttachmentMetadata? metadata,
  }) {
    final filename = metadata?.filenames.isNotEmpty == true
        ? metadata!.filenames.first.trim()
        : '';
    if (filename.isNotEmpty) return filename;

    final title = (metadata?.title ?? '').trim();
    if (title.isNotEmpty) return title;

    final firstUrl = metadata?.sourceUrls.isNotEmpty == true
        ? metadata!.sourceUrls.first.trim()
        : '';
    if (firstUrl.isNotEmpty) return firstUrl;

    final mime = attachment.mimeType.trim().toLowerCase();
    if (mime.startsWith('image/')) return 'Image attachment';
    if (mime.startsWith('video/')) return 'Video attachment';
    if (mime.startsWith('audio/')) return 'Audio attachment';
    if (mime == 'application/pdf') return 'PDF attachment';
    return 'Attachment';
  }

  @override
  Widget build(BuildContext context) {
    final bytesFuture = _bytesFuture;
    final exifFuture = _exifFuture;
    final appBarTitle = _resolveAppBarTitle(
      widget.attachment,
      metadata: _metadata,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: [
          if (bytesFuture != null)
            FutureBuilder<Uint8List>(
              future: bytesFuture,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                final disabled = bytes == null;
                return IconButton(
                  key: const ValueKey('attachment_viewer_share'),
                  tooltip: context.t.common.actions.share,
                  onPressed: disabled
                      ? null
                      : () => unawaited(_shareAttachment(bytes)),
                  icon: const Icon(Icons.share_rounded),
                );
              },
            ),
          if (bytesFuture != null)
            FutureBuilder<Uint8List>(
              future: bytesFuture,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                final disabled = bytes == null;
                return IconButton(
                  key: const ValueKey('attachment_viewer_download'),
                  tooltip: context.t.common.actions.pull,
                  onPressed: disabled
                      ? null
                      : () => unawaited(_downloadAttachment(bytes)),
                  icon: const Icon(Icons.download_rounded),
                );
              },
            ),
        ],
      ),
      body: bytesFuture == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder(
              future: bytesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final err = snapshot.error;
                  final isWifiConsentError = err is StateError &&
                      err.message == 'media_download_requires_wifi';
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.broken_image_outlined, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            isWifiConsentError
                                ? context.t.sync.mediaPreview
                                    .chatThumbnailsWifiOnlySubtitle
                                : context.t.errors.loadFailed(error: '$err'),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _bytesFuture = _loadBytes();
                              });
                            },
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

                final isImage = widget.attachment.mimeType.startsWith('image/');
                final isAudio = widget.attachment.mimeType.startsWith('audio/');
                if (isAudio) {
                  return AudioAttachmentPlayerView(
                    attachment: widget.attachment,
                    bytes: bytes,
                    metadataFuture: _metadataFuture,
                    initialMetadata: _metadata,
                    annotationPayloadFuture: _annotationPayloadFuture,
                    initialAnnotationPayload: _annotationPayload,
                  );
                }
                if (!isImage) {
                  Future<void> Function()? runOcr;
                  if (_supportsDocumentOcrAttachment()) {
                    runOcr = _runDocumentOcr;
                  } else if (_isVideoManifestAttachment()) {
                    runOcr = _runVideoManifestOcr;
                  }

                  return NonImageAttachmentView(
                    attachment: widget.attachment,
                    bytes: bytes,
                    metadataFuture: _metadataFuture,
                    initialMetadata: _metadata,
                    annotationPayloadFuture: _annotationPayloadFuture,
                    initialAnnotationPayload: _annotationPayload,
                    onRunOcr: runOcr,
                    ocrRunning: _runningDocumentOcr,
                    ocrStatusText: _documentOcrStatusText,
                    ocrLanguageHints: _effectiveDocumentOcrLanguageHints,
                    onOcrLanguageHintsChanged: _updateDocumentOcrLanguageHints,
                  );
                }

                final exifFromBytes = tryReadImageExifMetadata(bytes);

                Widget buildContent(
                  AttachmentExifMetadata? persisted,
                  String? placeDisplayName,
                  String? annotationCaption,
                ) {
                  final persistedCapturedAtMs = persisted?.capturedAtMs;
                  final persistedCapturedAt = persistedCapturedAtMs == null
                      ? null
                      : DateTime.fromMillisecondsSinceEpoch(
                          persistedCapturedAtMs.toInt(),
                          isUtc: true,
                        ).toLocal();

                  final persistedLatitude = persisted?.latitude;
                  final persistedLongitude = persisted?.longitude;
                  final hasPersistedLocation = persistedLatitude != null &&
                      persistedLongitude != null &&
                      !(persistedLatitude == 0.0 && persistedLongitude == 0.0);

                  final capturedAt =
                      persistedCapturedAt ?? exifFromBytes?.capturedAt;
                  final latitude = hasPersistedLocation
                      ? persistedLatitude
                      : exifFromBytes?.latitude;
                  final longitude = hasPersistedLocation
                      ? persistedLongitude
                      : exifFromBytes?.longitude;
                  _maybeScheduleInlinePlaceResolve(
                    latitude: latitude,
                    longitude: longitude,
                  );

                  return Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: InteractiveViewer(
                            child: Image.memory(bytes, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildMetadataCard(
                                context,
                                byteLen: widget.attachment.byteLen.toInt(),
                                capturedAt: capturedAt,
                                latitude: latitude,
                                longitude: longitude,
                                placeDisplayName: placeDisplayName,
                              ),
                              if ((annotationCaption ?? '').trim().isNotEmpty)
                                const SizedBox(height: 12),
                              if ((annotationCaption ?? '').trim().isNotEmpty)
                                _buildAnnotationCard(
                                  context,
                                  captionLong: annotationCaption!,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }

                Widget buildWithAnnotation(
                  AttachmentExifMetadata? persisted,
                  String? placeDisplayName,
                ) {
                  final annotationFuture = _annotationCaptionFuture;
                  if (annotationFuture == null) {
                    return buildContent(persisted, placeDisplayName, null);
                  }

                  return FutureBuilder<String?>(
                    future: annotationFuture,
                    initialData: _annotationCaption,
                    builder: (context, annotationSnapshot) {
                      return buildContent(
                        persisted,
                        placeDisplayName,
                        annotationSnapshot.data,
                      );
                    },
                  );
                }

                Widget buildWithPlace(AttachmentExifMetadata? persisted) {
                  final placeFuture = _placeFuture;
                  if (placeFuture == null) {
                    return buildWithAnnotation(persisted, null);
                  }

                  return FutureBuilder<String?>(
                    future: placeFuture,
                    initialData: _placeDisplayName,
                    builder: (context, placeSnapshot) {
                      return buildWithAnnotation(persisted, placeSnapshot.data);
                    },
                  );
                }

                if (exifFuture == null) {
                  return buildWithPlace(null);
                }

                return FutureBuilder<AttachmentExifMetadata?>(
                  future: exifFuture,
                  builder: (context, metaSnapshot) {
                    return buildWithPlace(metaSnapshot.data);
                  },
                );
              },
            ),
    );
  }
}
