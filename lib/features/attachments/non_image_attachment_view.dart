import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/content_enrichment/docx_ocr_policy.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import '../url_enrichment/url_enrichment_runner.dart';
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

String _attachmentOcrLanguageHintLabel(BuildContext context, String hint) {
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

class NonImageAttachmentView extends StatefulWidget {
  const NonImageAttachmentView({
    required this.attachment,
    required this.bytes,
    this.metadataFuture,
    this.initialMetadata,
    this.annotationPayloadFuture,
    this.initialAnnotationPayload,
    this.onRunOcr,
    this.ocrRunning = false,
    this.ocrStatusText,
    this.ocrLanguageHints = 'device_plus_en',
    this.onOcrLanguageHintsChanged,
    this.onSaveSummary,
    this.onSaveFull,
    super.key,
  });

  final Attachment attachment;
  final Uint8List bytes;
  final Future<AttachmentMetadata?>? metadataFuture;
  final AttachmentMetadata? initialMetadata;
  final Future<Map<String, Object?>?>? annotationPayloadFuture;
  final Map<String, Object?>? initialAnnotationPayload;
  final Future<void> Function()? onRunOcr;
  final bool ocrRunning;
  final String? ocrStatusText;
  final String ocrLanguageHints;
  final ValueChanged<String>? onOcrLanguageHintsChanged;
  final Future<void> Function(String value)? onSaveSummary;
  final Future<void> Function(String value)? onSaveFull;

  @override
  State<NonImageAttachmentView> createState() => _NonImageAttachmentViewState();
}

class _NonImageAttachmentViewState extends State<NonImageAttachmentView> {
  static String? _tryParseUrlManifestUrl(Uint8List bytes) {
    try {
      final raw = utf8.decode(bytes, allowMalformed: false);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final schema = decoded['schema'];
      final url = decoded['url'];
      if (schema is! String || schema.trim() != kSecondLoopUrlManifestSchema) {
        return null;
      }
      if (url is! String) return null;
      final trimmed = url.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  static Widget _buildLabeledValueCard(
    BuildContext context, {
    required String label,
    required String value,
    bool markdown = false,
  }) {
    final v = value.trim();
    if (v.isEmpty) return const SizedBox.shrink();
    return SlSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          if (markdown)
            MarkdownBody(
              data: v,
              selectable: true,
              styleSheet:
                  MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: Theme.of(context).textTheme.bodySmall,
                listBullet: Theme.of(context).textTheme.bodySmall,
                code: Theme.of(context).textTheme.bodySmall,
                codeblockPadding: const EdgeInsets.all(8),
              ),
            )
          else
            SelectableText(
              v,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _buildView(
    BuildContext context, {
    required Attachment attachment,
    required Uint8List bytes,
    required AttachmentMetadata? meta,
    required Map<String, Object?>? payload,
    required Future<void> Function()? onRunOcr,
    required Future<void> Function()? onOpenWithSystem,
    required bool ocrRunning,
    required String? ocrStatusText,
    required String ocrLanguageHints,
    required ValueChanged<String>? onOcrLanguageHintsChanged,
  }) {
    int asInt(Object? raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw.trim()) ?? 0;
      return 0;
    }

    String sourceLabel(AttachmentTextSource source) {
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

    final title = (meta?.title ?? payload?['title'])?.toString().trim();
    final manifestUrl = attachment.mimeType == kSecondLoopUrlManifestMimeType
        ? _tryParseUrlManifestUrl(bytes)
        : null;
    final canonicalUrl = payload?['canonical_url']?.toString().trim();

    final selectedTextContent = selectAttachmentDisplayText(payload);
    final textContent = resolveAttachmentDetailTextContent(payload);
    final summaryText = textContent.summary;
    final fullText = textContent.full;
    final needsOcr = payload?['needs_ocr'] == true;
    final ocrStatus = (ocrStatusText ?? '').trim();
    final autoOcrStatus =
        (payload?['ocr_auto_status'] ?? '').toString().trim().toLowerCase();
    final autoOcrRunning = autoOcrStatus == 'running';
    final mime = attachment.mimeType.trim().toLowerCase();
    final isPdf = mime == 'application/pdf';
    final isDocx = isDocxMimeType(mime);
    final isVideoManifest = mime == kSecondLoopVideoManifestMimeType;
    final runOcr = onRunOcr;
    final runOcrAction = runOcr;
    final openWithSystem = onOpenWithSystem;
    final supportsOcr = isPdf || isDocx || isVideoManifest;
    final canRunOcr = supportsOcr && runOcr != null;
    final canOpenWithSystem = isPdf && openWithSystem != null;
    final ocrInProgress = ocrRunning || autoOcrRunning;
    final hasAnyText = textContent.hasAny;
    final hasOcrEngine =
        (payload?['ocr_engine'] ?? '').toString().trim().isNotEmpty;
    final showNeedsOcrState = needsOcr || (!hasAnyText && !hasOcrEngine);
    final showOcrCard = supportsOcr &&
        (needsOcr || ocrInProgress || ocrStatus.isNotEmpty || canRunOcr);
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final ocrEngine = (payload?['ocr_engine'] ?? '').toString().trim();
    final ocrLangHints = (payload?['ocr_lang_hints'] ?? '').toString().trim();
    final ocrDpi = asInt(payload?['ocr_dpi']);
    final ocrRetryAttempted = payload?['ocr_retry_attempted'] == true;
    final ocrRetryAttempts = asInt(payload?['ocr_retry_attempts']);
    final ocrRetryHints = (payload?['ocr_retry_hints'] ?? '').toString().trim();
    final pageCount = asInt(payload?['page_count']);
    final processedPages = asInt(payload?['ocr_processed_pages']);
    final autoStatus = autoOcrStatus.isEmpty ? 'none' : autoOcrStatus;
    final selectedHint = normalizeAttachmentOcrLanguageHint(ocrLanguageHints);
    final showPreparingTextState = !hasAnyText &&
        (ocrInProgress ||
            autoStatus == 'queued' ||
            autoStatus == 'retrying' ||
            payload == null);
    final debugMarker = buildPdfOcrDebugMarker(
      isPdf: isPdf,
      debugEnabled: kDebugMode,
      source: sourceLabel(selectedTextContent.source),
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SlSurface(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canOpenWithSystem)
                      OutlinedButton.icon(
                        onPressed: () => unawaited(openWithSystem()),
                        icon: const Icon(Icons.open_in_new_outlined),
                        label: Text(
                          context.t.attachments.content.openWithSystem,
                        ),
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('attachment_content_share_button'),
                      onPressed: () => unawaited(_shareAttachment(context)),
                      icon: const Icon(Icons.share_outlined),
                      label: Text(context.t.common.actions.share),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('attachment_content_download_button'),
                      onPressed: () => unawaited(_downloadAttachment(context)),
                      icon: const Icon(Icons.download_rounded),
                      label: Text(context.t.common.actions.pull),
                    ),
                  ],
                ),
              ),
              if ((title ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                SlSurface(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    title!,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
              if ((manifestUrl ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildLabeledValueCard(
                  context,
                  label: context.t.attachments.url.originalUrl,
                  value: manifestUrl!,
                ),
              ],
              if ((canonicalUrl ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildLabeledValueCard(
                  context,
                  label: context.t.attachments.url.canonicalUrl,
                  value: canonicalUrl!,
                ),
              ],
              if (debugMarker != null) ...[
                const SizedBox(height: 12),
                SlSurface(
                  key: const ValueKey('pdf_ocr_debug_marker'),
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    debugMarker,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              if (showOcrCard) ...[
                const SizedBox(height: 12),
                SlSurface(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        showNeedsOcrState
                            ? context.t.attachments.content.needsOcrTitle
                            : context.t.attachments.content.ocrTitle,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      if (ocrInProgress)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                ocrStatus.isNotEmpty
                                    ? ocrStatus
                                    : context.t.attachments.content.ocrRunning,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          ocrStatus.isNotEmpty
                              ? ocrStatus
                              : showNeedsOcrState
                                  ? context
                                      .t.attachments.content.needsOcrSubtitle
                                  : context
                                      .t.attachments.content.ocrReadySubtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (ocrInProgress && isMobile) ...[
                        const SizedBox(height: 6),
                        Text(
                          context.t.attachments.content.keepForegroundHint,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (canRunOcr) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 240,
                              child: Material(
                                color: Colors.transparent,
                                child: DropdownButtonFormField<String>(
                                  key: const ValueKey(
                                    'attachment_ocr_language_hint_field',
                                  ),
                                  value: selectedHint,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: context
                                        .t
                                        .settings
                                        .mediaAnnotation
                                        .documentOcr
                                        .languageHints
                                        .title,
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: [
                                    for (final hint
                                        in kAttachmentOcrLanguageHintOptions)
                                      DropdownMenuItem<String>(
                                        value: hint,
                                        child: Text(
                                          _attachmentOcrLanguageHintLabel(
                                            context,
                                            hint,
                                          ),
                                        ),
                                      ),
                                  ],
                                  onChanged: ocrInProgress ||
                                          onOcrLanguageHintsChanged == null
                                      ? null
                                      : (next) {
                                          if (next == null) return;
                                          onOcrLanguageHintsChanged(next);
                                        },
                                ),
                              ),
                            ),
                            FilledButton.icon(
                              key: const ValueKey('attachment_run_ocr_button'),
                              onPressed: ocrInProgress || runOcrAction == null
                                  ? null
                                  : () => unawaited(runOcrAction()),
                              icon: const Icon(Icons.document_scanner_outlined),
                              label: Text(
                                showNeedsOcrState
                                    ? context.t.attachments.content.runOcr
                                    : context.t.common.actions.retry,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (!hasAnyText) ...[
                const SizedBox(height: 12),
                SlSurface(
                  padding: const EdgeInsets.all(12),
                  child: showPreparingTextState
                      ? Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              context.t.sync.progressDialog.preparing,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        )
                      : Text(
                          ocrStatus.isNotEmpty
                              ? ocrStatus
                              : showNeedsOcrState
                                  ? context.t.attachments.content.ocrTitle
                                  : context.t.attachments.content.ocrFailed,
                          style: Theme.of(context).textTheme.bodySmall,
                          key: const ValueKey('attachment_no_text_status'),
                        ),
                ),
              ],
              const SizedBox(height: 12),
              AttachmentTextEditorCard(
                fieldKeyPrefix: 'attachment_text_summary',
                label: context.t.attachments.content.summary,
                text: summaryText,
                emptyText: attachmentDetailEmptyTextLabel(context),
                onSave: widget.onSaveSummary,
              ),
              const SizedBox(height: 12),
              AttachmentTextEditorCard(
                fieldKeyPrefix: 'attachment_text_full',
                label: context.t.attachments.content.fullText,
                text: fullText,
                markdown: true,
                emptyText: attachmentDetailEmptyTextLabel(context),
                onSave: widget.onSaveFull,
              ),
            ],
          ),
        ),
      ),
    );
  }

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

  Future<File> _materializeTempDownloadFile() async {
    final dir = await getTemporaryDirectory();
    final outFile = File('${dir.path}/${_downloadFilename()}');
    await outFile.writeAsBytes(widget.bytes, flush: true);
    return outFile;
  }

  Future<void> _shareAttachment(BuildContext context) async {
    try {
      final file = await _materializeTempDownloadFile();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: widget.attachment.mimeType)],
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _downloadAttachment(BuildContext context) async {
    try {
      final file = await _materializeTempDownloadFile();
      final launched = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(file.path),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<String> _materializeFileForSystemOpen() async {
    final extension =
        fileExtensionForSystemOpenMimeType(widget.attachment.mimeType);
    final stem = widget.attachment.sha256.trim().isEmpty
        ? DateTime.now().millisecondsSinceEpoch.toString()
        : widget.attachment.sha256.trim();
    final tempDir = Directory(
      '${Directory.systemTemp.path}/secondloop_open_with_system',
    );
    await tempDir.create(recursive: true);
    final outFile = File('${tempDir.path}/$stem$extension');
    await outFile.writeAsBytes(widget.bytes, flush: true);
    return outFile.path;
  }

  Future<void> _openWithSystemApp(BuildContext context) async {
    try {
      final absolutePath = await _materializeFileForSystemOpen();
      final launched = await launchUrl(
        Uri.file(absolutePath),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError('could not open externally');
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget buildWith(AttachmentMetadata? meta, Map<String, Object?>? payload) {
      return _buildView(
        context,
        attachment: widget.attachment,
        bytes: widget.bytes,
        meta: meta,
        payload: payload,
        onRunOcr: widget.onRunOcr,
        onOpenWithSystem: () => _openWithSystemApp(context),
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
