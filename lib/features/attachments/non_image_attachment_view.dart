import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/attachments_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/content_enrichment/docx_ocr_policy.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import '../media_backup/cloud_media_download.dart';
import 'attachment_detail_text_content.dart';
import 'attachment_external_open_helper.dart';
import 'attachment_text_editor_card.dart';
import 'attachment_text_source_policy.dart';
import 'video_keyframe_ocr_worker.dart';
import 'video_proxy_open_helper.dart';

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

final class VideoManifestInsightContent {
  const VideoManifestInsightContent({
    required this.contentKind,
    required this.summary,
    required this.detail,
    required this.segmentCount,
    required this.processedSegmentCount,
  });

  final String contentKind;
  final String summary;
  final String detail;
  final int segmentCount;
  final int processedSegmentCount;

  bool get hasAny {
    return contentKind != 'unknown' ||
        summary.isNotEmpty ||
        detail.isNotEmpty ||
        segmentCount > 0 ||
        processedSegmentCount > 0;
  }
}

@visibleForTesting
VideoManifestInsightContent? resolveVideoManifestInsightContent(
  Map<String, Object?>? payload,
) {
  if (payload == null) return null;

  String read(String key) {
    final raw = payload[key];
    if (raw == null) return '';
    final value = raw.toString().trim();
    if (value.toLowerCase() == 'null') return '';
    return value;
  }

  String firstNonEmpty(List<String> keys) {
    for (final key in keys) {
      final value = read(key);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  final rawContentKind = read('video_content_kind').toLowerCase();
  final contentKind = switch (rawContentKind) {
    'knowledge' || 'non_knowledge' => rawContentKind,
    _ => 'unknown',
  };

  final summary = firstNonEmpty(const <String>[
    'video_summary',
    'knowledge_markdown_excerpt',
    'video_description_excerpt',
    'readable_text_excerpt',
    'transcript_excerpt',
    'ocr_text_excerpt',
  ]);

  final detail = switch (contentKind) {
    'knowledge' => firstNonEmpty(const <String>[
        'knowledge_markdown_excerpt',
        'knowledge_markdown_full',
        'readable_text_excerpt',
        'readable_text_full',
      ]),
    'non_knowledge' => firstNonEmpty(const <String>[
        'video_description_excerpt',
        'video_description_full',
        'readable_text_excerpt',
        'readable_text_full',
      ]),
    _ => firstNonEmpty(const <String>[
        'readable_text_excerpt',
        'readable_text_full',
        'ocr_text_excerpt',
        'ocr_text_full',
      ]),
  };

  final segmentCount = _videoManifestAsInt(payload['video_segment_count']);
  final processedSegmentCount =
      _videoManifestAsInt(payload['video_processed_segment_count']);

  final insight = VideoManifestInsightContent(
    contentKind: contentKind,
    summary: _truncateVideoManifestInsightText(summary, maxChars: 1200),
    detail: _truncateVideoManifestInsightText(detail, maxChars: 2400),
    segmentCount: segmentCount,
    processedSegmentCount: processedSegmentCount,
  );
  if (!insight.hasAny) return null;
  return insight;
}

int _videoManifestAsInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim()) ?? 0;
  return 0;
}

String _truncateVideoManifestInsightText(
  String value, {
  required int maxChars,
}) {
  final trimmed = value.trim();
  if (trimmed.length <= maxChars) return trimmed;
  if (maxChars <= 0) return '';
  return '${trimmed.substring(0, maxChars)}...';
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
    this.onOpenVideoProxyInApp,
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
  final OpenVideoProxyInAppOverride? onOpenVideoProxyInApp;

  @override
  State<NonImageAttachmentView> createState() => _NonImageAttachmentViewState();
}

class _NonImageAttachmentViewState extends State<NonImageAttachmentView> {
  Future<ParsedVideoManifest?>? _videoManifestFuture;
  final Map<String, Future<Uint8List?>> _attachmentBytesBySha =
      <String, Future<Uint8List?>>{};

  @override
  void initState() {
    super.initState();
    _videoManifestFuture = _createVideoManifestFuture();
  }

  @override
  void didUpdateWidget(covariant NonImageAttachmentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final didVideoTargetChange =
        oldWidget.attachment.sha256 != widget.attachment.sha256 ||
            oldWidget.attachment.mimeType != widget.attachment.mimeType ||
            oldWidget.bytes != widget.bytes;
    if (!didVideoTargetChange) return;

    _attachmentBytesBySha.clear();
    _videoManifestFuture = _createVideoManifestFuture();
  }

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

  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
    return 0;
  }

  Future<ParsedVideoManifest?> _createVideoManifestFuture() async {
    final mime = widget.attachment.mimeType.trim().toLowerCase();
    if (mime != kSecondLoopVideoManifestMimeType) return null;

    final inlineManifest = parseVideoManifestPayload(widget.bytes);
    if (inlineManifest != null) return inlineManifest;

    final bytes = await _readAttachmentBytesBySha(widget.attachment.sha256);
    if (bytes == null || bytes.isEmpty) return null;
    return parseVideoManifestPayload(bytes);
  }

  Future<Uint8List?> _readAttachmentBytesBySha(String sha256) {
    final normalizedSha = sha256.trim();
    if (normalizedSha.isEmpty) return Future<Uint8List?>.value(null);

    return _attachmentBytesBySha.putIfAbsent(normalizedSha, () async {
      final backend = AppBackendScope.maybeOf(context);
      final sessionScope = SessionScope.maybeOf(context);
      if (backend is! AppBackend ||
          backend is! AttachmentsBackend ||
          sessionScope == null) {
        return null;
      }
      final attachmentsBackend = backend as AttachmentsBackend;
      final idTokenGetter =
          CloudAuthScope.maybeOf(context)?.controller.getIdToken;

      try {
        final bytes = await attachmentsBackend.readAttachmentBytes(
          sessionScope.sessionKey,
          sha256: normalizedSha,
        );
        if (bytes.isEmpty) return null;
        return bytes;
      } catch (_) {
        final downloader = CloudMediaDownload();
        final result = await downloader
            .downloadAttachmentBytesFromConfiguredSyncWithPolicy(
          backend: backend,
          sessionKey: sessionScope.sessionKey,
          idTokenGetter: idTokenGetter,
          sha256: normalizedSha,
          allowCellular: false,
        );
        if (!result.didDownload) return null;
        try {
          final downloaded = await attachmentsBackend.readAttachmentBytes(
            sessionScope.sessionKey,
            sha256: normalizedSha,
          );
          if (downloaded.isEmpty) return null;
          return downloaded;
        } catch (_) {
          return null;
        }
      }
    });
  }

  Future<void> _openAttachmentBySha(String sha256, String mimeType) {
    final extension = fileExtensionForSystemOpenMimeType(mimeType);
    final stem = sha256.trim().isEmpty
        ? DateTime.now().millisecondsSinceEpoch.toString()
        : sha256.trim();

    return openAttachmentBytesWithSystem(
      context,
      loadBytes: () => _readAttachmentBytesBySha(sha256),
      outputStem: stem,
      extension: extension,
    );
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

  Widget _buildVideoManifestInsightsCard(
    BuildContext context,
    VideoManifestInsightContent insights,
  ) {
    final labels = context.t.attachments.content.videoInsights;

    final contentKindLabel = switch (insights.contentKind) {
      'knowledge' => labels.contentKind.knowledge,
      'non_knowledge' => labels.contentKind.nonKnowledge,
      _ => labels.contentKind.unknown,
    };

    final detailLabel = switch (insights.contentKind) {
      'knowledge' => labels.detail.knowledgeMarkdown,
      'non_knowledge' => labels.detail.videoDescription,
      _ => labels.detail.extractedContent,
    };

    final hasSegmentStats =
        insights.segmentCount > 0 || insights.processedSegmentCount > 0;
    final segmentTotal = insights.segmentCount > 0
        ? insights.segmentCount
        : insights.processedSegmentCount;
    final segmentDone = insights.processedSegmentCount;
    final segmentValue = hasSegmentStats ? '$segmentDone/$segmentTotal' : '';

    final children = <Widget>[];

    void addField(String fieldLabel, String fieldValue, {Key? valueKey}) {
      final normalizedValue = fieldValue.trim();
      if (normalizedValue.isEmpty) return;
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 10));
      }
      children.add(
        Text(
          fieldLabel,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      );
      children.add(const SizedBox(height: 4));
      children.add(
        SelectableText(
          normalizedValue,
          key: valueKey,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    addField(
      labels.fields.contentType,
      contentKindLabel,
      valueKey: const ValueKey('video_manifest_content_kind_value'),
    );
    addField(
      labels.fields.segments,
      segmentValue,
    );
    addField(
      labels.fields.summary,
      insights.summary,
      valueKey: const ValueKey('video_manifest_summary_text'),
    );
    addField(
      detailLabel,
      insights.detail,
      valueKey: const ValueKey('video_manifest_detail_text'),
    );

    return SlSurface(
      key: const ValueKey('video_manifest_insights_surface'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildVideoManifestPreviewTile({
    required String sha256,
    required String mimeType,
    required Key key,
    double width = 240,
    double height = 136,
  }) {
    return FutureBuilder<Uint8List?>(
      future: _readAttachmentBytesBySha(sha256),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        final hasBytes = bytes != null && bytes.isNotEmpty;

        return Container(
          key: key,
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: hasBytes
              ? Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                )
              : Center(
                  child: Icon(
                    _previewIconForMime(mimeType),
                    size: 28,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
        );
      },
    );
  }

  Widget _buildVideoManifestPreviewCard(
    BuildContext context,
    ParsedVideoManifest manifest,
  ) {
    final keyframes = manifest.keyframes
        .where((item) => item.sha256.trim().isNotEmpty)
        .toList(growable: false);
    final previewKeyframes = keyframes.take(4).toList(growable: false);
    final posterSha256 = (manifest.posterSha256 ?? '').trim();
    final proxySha256 = (manifest.videoProxySha256 ?? '').trim();
    final proxyMimeType = manifest.segments.isNotEmpty
        ? manifest.segments.first.mimeType
        : manifest.originalMimeType;
    final confidencePercent =
        (manifest.videoKindConfidence.clamp(0.0, 1.0) * 100).round();

    Widget buildStatBadge(String text) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      );
    }

    return SlSurface(
      key: const ValueKey('video_manifest_preview_surface'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              buildStatBadge('${manifest.videoKind} ($confidencePercent%)'),
              buildStatBadge('segments: ${manifest.segments.length}'),
              buildStatBadge('keyframes: ${keyframes.length}'),
            ],
          ),
          if (posterSha256.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildVideoManifestPreviewTile(
              sha256: posterSha256,
              mimeType: manifest.posterMimeType ?? 'image/jpeg',
              key: const ValueKey('video_manifest_poster_preview'),
              width: double.infinity,
              height: 188,
            ),
          ],
          if (previewKeyframes.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < previewKeyframes.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _buildVideoManifestPreviewTile(
                      sha256: previewKeyframes[i].sha256,
                      mimeType: previewKeyframes[i].mimeType,
                      key: ValueKey('video_manifest_keyframe_preview_$i'),
                      width: 156,
                      height: 96,
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (proxySha256.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const ValueKey('video_manifest_open_proxy_button'),
                onPressed: () => unawaited(openVideoProxyWithBestEffort(context,
                    sha256: proxySha256,
                    mimeType: proxyMimeType,
                    loadBytes: _readAttachmentBytesBySha,
                    openWithSystem: () =>
                        _openAttachmentBySha(proxySha256, proxyMimeType),
                    onOpenVideoProxyInApp: widget.onOpenVideoProxyInApp,
                    segmentRefs: manifest.segments
                        .map((segment) => (
                              sha256: segment.sha256,
                              mimeType: segment.mimeType
                            ))
                        .toList(growable: false))),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(context.t.common.actions.open),
              ),
            ),
          ],
        ],
      ),
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
    final videoInsights =
        isVideoManifest ? resolveVideoManifestInsightContent(payload) : null;
    final videoManifestFuture = isVideoManifest
        ? (_videoManifestFuture ??= _createVideoManifestFuture())
        : null;

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
      source: switch (selectedTextContent.source) {
        AttachmentTextSource.extracted => 'extracted',
        AttachmentTextSource.readable => 'readable',
        AttachmentTextSource.ocr => 'ocr',
        AttachmentTextSource.none => 'none',
      },
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
              if (videoManifestFuture != null) ...[
                buildSection(
                  FutureBuilder<ParsedVideoManifest?>(
                    future: videoManifestFuture,
                    builder: (context, snapshot) {
                      final manifest = snapshot.data;
                      if (manifest == null) return const SizedBox.shrink();
                      return _buildVideoManifestPreviewCard(context, manifest);
                    },
                  ),
                  maxWidth: 820,
                ),
                const SizedBox(height: 14),
              ],
              if (videoInsights != null) ...[
                buildSection(
                  _buildVideoManifestInsightsCard(context, videoInsights),
                  maxWidth: 820,
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
