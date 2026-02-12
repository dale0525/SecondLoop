import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/content_enrichment/docx_ocr_policy.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import 'attachment_detail_text_content.dart';
import 'attachment_text_editor_card.dart';
import 'attachment_text_source_policy.dart';
import 'video_keyframe_ocr_worker.dart';

String fileExtensionForSystemOpenMimeType(String mimeType) {
  final normalized = mimeType.trim().toLowerCase();
  if (normalized == 'application/pdf') return '.pdf';
  if (normalized == 'text/plain') return '.txt';
  if (normalized == kDocxMimeType) return '.docx';
  if (normalized == 'text/markdown') return '.md';
  if (normalized == 'application/json') return '.json';
  if (normalized == 'application/xml') return '.xml';
  if (normalized.startsWith('image/jpeg')) return '.jpg';
  if (normalized.startsWith('image/png')) return '.png';
  if (normalized.startsWith('image/webp')) return '.webp';
  if (normalized.startsWith('audio/mpeg')) return '.mp3';
  if (normalized.startsWith('audio/mp4')) return '.m4a';
  if (normalized.startsWith('audio/')) return '.audio';
  if (normalized.startsWith('video/mp4')) return '.mp4';
  if (normalized.startsWith('video/quicktime')) return '.mov';
  if (normalized.startsWith('video/')) return '.video';
  return '.bin';
}

@visibleForTesting
String? buildPdfOcrDebugMarker({
  required bool isPdf,
  required bool debugEnabled,
  required String source,
  required String autoStatus,
  required bool needsOcr,
  required String ocrEngine,
  required String ocrLangHints,
  required int ocrDpi,
  required bool ocrRetryAttempted,
  required int ocrRetryAttempts,
  required String ocrRetryHints,
  required int processedPages,
  required int pageCount,
}) {
  if (!isPdf || !debugEnabled) return null;
  return [
    'debug.ocr',
    'source=$source',
    'auto=$autoStatus',
    'needs_ocr=$needsOcr',
    'engine=${ocrEngine.isEmpty ? "none" : ocrEngine}',
    'hints=${ocrLangHints.isEmpty ? "none" : ocrLangHints}',
    'dpi=$ocrDpi',
    'retry=$ocrRetryAttempted',
    'retry_attempts=$ocrRetryAttempts',
    'retry_hints=${ocrRetryHints.isEmpty ? "none" : ocrRetryHints}',
    'pages=$processedPages/$pageCount',
  ].join(' | ');
}

const List<String> kAttachmentOcrLanguageHintOptions = <String>[
  'device_plus_en',
  'en',
  'zh_en',
  'ja_en',
  'ko_en',
  'fr_en',
  'de_en',
  'es_en',
];

String normalizeAttachmentOcrLanguageHint(String value) {
  final normalized = value.trim();
  if (kAttachmentOcrLanguageHintOptions.contains(normalized)) {
    return normalized;
  }
  return 'device_plus_en';
}

String attachmentOcrLanguageHintLabel(BuildContext context, String hint) {
  final labels =
      context.t.settings.mediaAnnotation.documentOcr.languageHints.labels;
  switch (hint) {
    case 'en':
      return labels.en;
    case 'zh_en':
      return labels.zhEn;
    case 'ja_en':
      return labels.jaEn;
    case 'ko_en':
      return labels.koEn;
    case 'fr_en':
      return labels.frEn;
    case 'de_en':
      return labels.deEn;
    case 'es_en':
      return labels.esEn;
    case 'device_plus_en':
    default:
      return labels.devicePlusEn;
  }
}

Future<String?> showAttachmentOcrLanguageHintDialog(
  BuildContext context, {
  required String initialHint,
  String? title,
  String? confirmLabel,
}) async {
  var selectedHint = normalizeAttachmentOcrLanguageHint(initialHint);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            key: const ValueKey('attachment_ocr_regenerate_dialog'),
            title: Text(title ?? context.t.attachments.content.rerunOcr),
            content: DropdownButtonFormField<String>(
              key: const ValueKey('attachment_ocr_language_hint_dialog_field'),
              value: selectedHint,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context
                    .t.settings.mediaAnnotation.documentOcr.languageHints.title,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final hint in kAttachmentOcrLanguageHintOptions)
                  DropdownMenuItem<String>(
                    value: hint,
                    child: Text(
                      attachmentOcrLanguageHintLabel(context, hint),
                    ),
                  ),
              ],
              onChanged: (next) {
                if (next == null) return;
                setDialogState(() {
                  selectedHint = next;
                });
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(context.t.common.actions.cancel),
              ),
              FilledButton(
                key: const ValueKey('attachment_ocr_regenerate_confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(
                    confirmLabel ?? context.t.attachments.content.rerunOcr),
              ),
            ],
          );
        },
      );
    },
  );

  if (confirmed != true) return null;
  return selectedHint;
}

class NonImageAttachmentView extends StatefulWidget {
  const NonImageAttachmentView({
    required this.attachment,
    required this.bytes,
    required this.displayTitle,
    this.metadataFuture,
    this.initialMetadata,
    this.annotationPayloadFuture,
    this.initialAnnotationPayload,
    this.onRunOcr,
    this.ocrRunning = false,
    this.ocrStatusText,
    this.ocrLanguageHints = 'device_plus_en',
    this.onOcrLanguageHintsChanged,
    this.onSaveFull,
    super.key,
  });

  final Attachment attachment;
  final Uint8List bytes;
  final String displayTitle;
  final Future<AttachmentMetadata?>? metadataFuture;
  final AttachmentMetadata? initialMetadata;
  final Future<Map<String, Object?>?>? annotationPayloadFuture;
  final Map<String, Object?>? initialAnnotationPayload;
  final Future<void> Function()? onRunOcr;
  final bool ocrRunning;
  final String? ocrStatusText;
  final String ocrLanguageHints;
  final ValueChanged<String>? onOcrLanguageHintsChanged;
  final Future<void> Function(String value)? onSaveFull;

  @override
  State<NonImageAttachmentView> createState() => _NonImageAttachmentViewState();
}

class _NonImageAttachmentViewState extends State<NonImageAttachmentView> {
  static IconData _previewIconForMime(String mime) {
    if (mime.startsWith('application/pdf') || isDocxMimeType(mime)) {
      return Icons.description_outlined;
    }
    if (mime.startsWith('video/') || mime == kSecondLoopVideoManifestMimeType) {
      return Icons.smart_display_outlined;
    }
    if (mime.startsWith('text/')) return Icons.article_outlined;
    if (mime.contains('json')) return Icons.data_object_rounded;
    return Icons.insert_drive_file_outlined;
  }

  static String _sourceLabel(AttachmentTextSource source) {
    switch (source) {
      case AttachmentTextSource.extracted:
        return 'extracted';
      case AttachmentTextSource.readable:
        return 'readable';
      case AttachmentTextSource.ocr:
        return 'ocr';
      case AttachmentTextSource.none:
        return 'none';
    }
  }

  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
    return 0;
  }

  Future<void> _runOcrWithDialogOptions({
    required String initialHint,
    required ValueChanged<String>? onOcrLanguageHintsChanged,
    required Future<void> Function() run,
  }) async {
    final selectedHint = await showAttachmentOcrLanguageHintDialog(
      context,
      initialHint: initialHint,
      title: context.t.attachments.content.rerunOcr,
      confirmLabel: context.t.attachments.content.rerunOcr,
    );
    if (selectedHint == null) return;

    onOcrLanguageHintsChanged?.call(selectedHint);
    await run();
  }

  Future<void> _onRegeneratePressed({
    required bool supportsOcr,
    required bool ocrInProgress,
    required String ocrLanguageHints,
    required ValueChanged<String>? onOcrLanguageHintsChanged,
    required Future<void> Function()? run,
  }) async {
    if (run == null || ocrInProgress) return;
    if (!supportsOcr) {
      await run();
      return;
    }

    await _runOcrWithDialogOptions(
      initialHint: ocrLanguageHints,
      onOcrLanguageHintsChanged: onOcrLanguageHintsChanged,
      run: run,
    );
  }

  Widget _buildView(
    BuildContext context, {
    required Attachment attachment,
    required Map<String, Object?>? payload,
    required Future<void> Function()? onRunOcr,
    required bool ocrRunning,
    required String? ocrStatusText,
    required String ocrLanguageHints,
    required ValueChanged<String>? onOcrLanguageHintsChanged,
  }) {
    final selectedTextContent = selectAttachmentDisplayText(payload);
    final textContent = resolveAttachmentDetailTextContent(payload);
    final fullText = textContent.full;
    final hasFullText = fullText.trim().isNotEmpty;

    final needsOcr = payload?['needs_ocr'] == true;
    final ocrStatus = (ocrStatusText ?? '').trim();
    final autoOcrStatus =
        (payload?['ocr_auto_status'] ?? '').toString().trim().toLowerCase();
    final autoOcrRunning = autoOcrStatus == 'running';
    final ocrInProgress = ocrRunning || autoOcrRunning;

    final mime = attachment.mimeType.trim().toLowerCase();
    final isPdf = mime == 'application/pdf';
    final isDocx = isDocxMimeType(mime);
    final isVideoManifest = mime == kSecondLoopVideoManifestMimeType;
    final supportsOcr = isPdf || isDocx || isVideoManifest;
    final canRunOcr = supportsOcr && onRunOcr != null;

    final hasOcrEngine =
        (payload?['ocr_engine'] ?? '').toString().trim().isNotEmpty;
    final showNeedsOcrState = needsOcr || (!hasFullText && !hasOcrEngine);
    final showPreparingTextState = !hasFullText &&
        (ocrInProgress ||
            autoOcrStatus == 'queued' ||
            autoOcrStatus == 'retrying' ||
            payload == null);

    final hasPreviewSignal = ocrStatus.isNotEmpty ||
        showPreparingTextState ||
        (supportsOcr && showNeedsOcrState);
    final previewHint = () {
      if (ocrStatus.isNotEmpty) return ocrStatus;
      if (showPreparingTextState) {
        return context.t.sync.progressDialog.preparing;
      }
      if (supportsOcr && showNeedsOcrState) {
        return context.t.attachments.content.needsOcrSubtitle;
      }
      return '';
    }();

    final ocrEngine = (payload?['ocr_engine'] ?? '').toString().trim();
    final ocrLangHints = (payload?['ocr_lang_hints'] ?? '').toString().trim();
    final ocrDpi = _asInt(payload?['ocr_dpi']);
    final ocrRetryAttempted = payload?['ocr_retry_attempted'] == true;
    final ocrRetryAttempts = _asInt(payload?['ocr_retry_attempts']);
    final ocrRetryHints = (payload?['ocr_retry_hints'] ?? '').toString().trim();
    final pageCount = _asInt(payload?['page_count']);
    final processedPages = _asInt(payload?['ocr_processed_pages']);
    final autoStatus = autoOcrStatus.isEmpty ? 'none' : autoOcrStatus;

    final debugMarker = buildPdfOcrDebugMarker(
      isPdf: isPdf,
      debugEnabled: kDebugMode,
      source: _sourceLabel(selectedTextContent.source),
      autoStatus: autoStatus,
      needsOcr: needsOcr,
      ocrEngine: ocrEngine,
      ocrLangHints: ocrLangHints,
      ocrDpi: ocrDpi,
      ocrRetryAttempted: ocrRetryAttempted,
      ocrRetryAttempts: ocrRetryAttempts,
      ocrRetryHints: ocrRetryHints,
      processedPages: processedPages,
      pageCount: pageCount,
    );

    final regenerateButton = canRunOcr
        ? IconButton(
            key: const ValueKey('attachment_text_full_regenerate'),
            tooltip: context.t.attachments.content.rerunOcr,
            onPressed: ocrInProgress
                ? null
                : () => unawaited(
                      _onRegeneratePressed(
                        supportsOcr: supportsOcr,
                        ocrInProgress: ocrInProgress,
                        ocrLanguageHints: ocrLanguageHints,
                        onOcrLanguageHintsChanged: onOcrLanguageHintsChanged,
                        run: onRunOcr,
                      ),
                    ),
            icon: const Icon(Icons.auto_awesome_rounded),
          )
        : null;

    Widget buildSection(
      Widget child, {
      required double maxWidth,
      Alignment alignment = Alignment.center,
    }) {
      return Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasPreviewSignal || debugMarker != null) ...[
                buildSection(
                  SlSurface(
                    key: const ValueKey('attachment_non_image_preview_surface'),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            _previewIconForMime(mime),
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mime,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              if (previewHint.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                if (showPreparingTextState)
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          previewHint,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Text(
                                    previewHint,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                              ],
                              if (debugMarker != null) ...[
                                const SizedBox(height: 6),
                                SelectableText(
                                  debugMarker,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  maxWidth: 860,
                ),
                const SizedBox(height: 14),
              ],
              buildSection(
                AttachmentTextEditorCard(
                  fieldKeyPrefix: 'attachment_text_full',
                  label: context.t.attachments.content.fullText,
                  showLabel: false,
                  text: fullText,
                  markdown: true,
                  emptyText: attachmentDetailEmptyTextLabel(context),
                  trailing: regenerateButton,
                  onSave: widget.onSaveFull,
                ),
                maxWidth: 820,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget buildWith(AttachmentMetadata? _, Map<String, Object?>? payload) {
      return _buildView(
        context,
        attachment: widget.attachment,
        payload: payload,
        onRunOcr: widget.onRunOcr,
        ocrRunning: widget.ocrRunning,
        ocrStatusText: widget.ocrStatusText,
        ocrLanguageHints: widget.ocrLanguageHints,
        onOcrLanguageHintsChanged: widget.onOcrLanguageHintsChanged,
      );
    }

    if (widget.metadataFuture == null &&
        widget.annotationPayloadFuture == null) {
      return buildWith(widget.initialMetadata, widget.initialAnnotationPayload);
    }

    return FutureBuilder<AttachmentMetadata?>(
      future: widget.metadataFuture,
      initialData: widget.initialMetadata,
      builder: (context, metaSnapshot) {
        return FutureBuilder<Map<String, Object?>?>(
          future: widget.annotationPayloadFuture,
          initialData: widget.initialAnnotationPayload,
          builder: (context, payloadSnapshot) {
            return buildWith(metaSnapshot.data, payloadSnapshot.data);
          },
        );
      },
    );
  }
}
