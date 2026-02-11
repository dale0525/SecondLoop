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
import '../../core/backend/native_backend.dart';
import '../../core/attachments/attachment_metadata_store.dart';
import '../../core/ai/ai_routing.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/content_enrichment/content_enrichment_config_store.dart';
import '../../core/content_enrichment/docx_ocr.dart';
import '../../core/content_enrichment/docx_ocr_policy.dart';
import '../../core/content_enrichment/multimodal_ocr.dart';
import '../../core/content_enrichment/ocr_result_preference.dart';
import '../../core/media_annotation/media_annotation_config_store.dart';
import '../../core/session/session_scope.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_gate.dart';
import '../media_backup/cloud_media_download.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import 'audio_attachment_player.dart';
import 'attachment_detail_text_content.dart';
import 'attachment_text_editor_card.dart';
import 'attachment_payload_refresh_policy.dart';
import 'attachment_text_source_policy.dart';
import 'non_image_attachment_view.dart';
import 'platform_pdf_ocr.dart';
import 'video_keyframe_ocr_worker.dart';

part 'attachment_viewer_page_image.dart';
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
  bool _retryingAttachmentRecognition = false;
  bool _awaitingAttachmentRecognitionResult = false;
  String? _placeDisplayName;
  String? _annotationCaption;
  AttachmentMetadata? _metadata;
  Map<String, Object?>? _annotationPayload;
  Map<String, Object?>? _lastNonEmptyAnnotationPayload;
  bool _runningDocumentOcr = false;
  String? _documentOcrStatusText;
  String _documentOcrLanguageHints = 'device_plus_en';
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
            content: Text(context.t.errors
                .loadFailed(error: 'could not open externally')),
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
    _bytesFuture ??= _loadBytes();
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
  }

  @override
  void dispose() {
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
      payload,
      annotationCaption: null,
    );
  }

  String _payloadOcrAutoStatus(Map<String, Object?>? payload) {
    return (payload?['ocr_auto_status'] ?? '').toString().trim().toLowerCase();
  }

  bool _payloadOcrTerminalWithoutText(Map<String, Object?>? payload) {
    final status = _payloadOcrAutoStatus(payload);
    return status == 'ok' || status == 'failed';
  }

  String? _preserveAnnotationCaptionWhileRecognition(String? nextCaption) {
    final normalized = (nextCaption ?? '').trim();
    if (normalized.isNotEmpty) return normalized;
    if (!_awaitingAttachmentRecognitionResult) return null;
    final existing = (_annotationCaption ?? '').trim();
    return existing.isEmpty ? null : existing;
  }

  Map<String, Object?>? _resolveDisplayAnnotationPayload(
    Map<String, Object?>? nextPayload,
  ) {
    final nextTextContent = _resolveIntrinsicTextContentForPayload(nextPayload);
    if (nextTextContent.hasAny) {
      _awaitingAttachmentRecognitionResult = false;
      _documentOcrStatusText = null;
      _lastNonEmptyAnnotationPayload = nextPayload;
      return nextPayload;
    }

    if (_awaitingAttachmentRecognitionResult &&
        _payloadOcrTerminalWithoutText(nextPayload)) {
      _awaitingAttachmentRecognitionResult = false;
      final status = _payloadOcrAutoStatus(nextPayload);
      if (status == 'failed') {
        _documentOcrStatusText = context.t.attachments.content.ocrFailed;
      }
    }

    final fallbackPayload =
        _lastNonEmptyAnnotationPayload ?? _annotationPayload;
    final fallbackTextContent =
        _resolveIntrinsicTextContentForPayload(fallbackPayload);
    final shouldPreserveCurrentText = (_awaitingAttachmentRecognitionResult ||
            _retryingAttachmentRecognition) &&
        !nextTextContent.hasAny &&
        fallbackTextContent.hasAny;

    if (shouldPreserveCurrentText) {
      return fallbackPayload;
    }

    return nextPayload;
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
    _annotationPayloadFuture = _loadAnnotationPayload().then((value) {
      final displayPayload = _resolveDisplayAnnotationPayload(value);
      _annotationPayload = displayPayload;
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

  bool get _canRetryAttachmentRecognition =>
      AppBackendScope.of(context) is NativeAppBackend;

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
      const store = RustContentEnrichmentConfigStore();
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
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lang = Localizations.localeOf(context).toLanguageTag();

    setState(() {
      _retryingAttachmentRecognition = true;
      _awaitingAttachmentRecognitionResult = true;
      _documentOcrStatusText = context.t.attachments.content.ocrRunning;
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
      await backend.enqueueAttachmentAnnotation(
        sessionKey,
        attachmentSha256: widget.attachment.sha256,
        lang: lang,
        nowMs: nowMs,
      );

      if (!mounted) return;
      _startAnnotationCaptionLoad();
      _startAnnotationPayloadLoad();
      SyncEngineScope.maybeOf(context)?.notifyLocalMutation();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _awaitingAttachmentRecognitionResult = false;
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
      AppBackendScope.of(context) is AttachmentAnnotationMutationsBackend;

  AttachmentDetailTextContent _currentAttachmentTextContent() {
    return resolveAttachmentDetailTextContent(
      _annotationPayload,
      annotationCaption: _annotationCaption,
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

  String _filenameFromAttachmentPath(Attachment attachment) {
    final raw = attachment.path.trim();
    if (raw.isEmpty) return '';
    final normalized = raw.replaceAll('\\', '/');
    final filename = normalized.split('/').last.trim();
    return filename;
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

    final pathFilename = _filenameFromAttachmentPath(attachment);
    if (pathFilename.isNotEmpty) return pathFilename;

    final fallbackStem = attachment.sha256.trim();
    if (fallbackStem.isNotEmpty) {
      return '$fallbackStem${fileExtensionForSystemOpenMimeType(attachment.mimeType)}';
    }

    return 'Attachment';
  }

  @override
  Widget build(BuildContext context) {
    final bytesFuture = _bytesFuture;
    final metadataFuture = _metadataFuture;

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
                      key: const ValueKey('attachment_viewer_open_with_system'),
                      tooltip: context.t.attachments.content.openWithSystem,
                      onPressed: disabled
                          ? null
                          : () => unawaited(_openAttachmentWithSystem(bytes)),
                      icon: const Icon(Icons.open_in_new_rounded),
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
                                    : context.t.errors
                                        .loadFailed(error: '$err'),
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

                    final isImage =
                        widget.attachment.mimeType.startsWith('image/');
                    final isAudio =
                        widget.attachment.mimeType.startsWith('audio/');
                    if (isAudio) {
                      return AudioAttachmentPlayerView(
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
                        displayTitle: appBarTitle,
                        metadataFuture: _metadataFuture,
                        initialMetadata: metadata,
                        annotationPayloadFuture: _annotationPayloadFuture,
                        initialAnnotationPayload: _annotationPayload,
                        onRunOcr: runOcr,
                        ocrRunning: _runningDocumentOcr,
                        ocrStatusText: _documentOcrStatusText,
                        ocrLanguageHints: _effectiveDocumentOcrLanguageHints,
                        onOcrLanguageHintsChanged:
                            _updateDocumentOcrLanguageHints,
                        onSaveFull:
                            _canEditAttachmentText ? _saveAttachmentFull : null,
                      );
                    }

                    return _buildImageAttachmentDetail(
                      bytes,
                      title: appBarTitle,
                    );
                  },
                ),
        );
      },
    );
  }
}
