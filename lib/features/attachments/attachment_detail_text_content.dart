import 'package:flutter/widgets.dart';

import 'attachment_ocr_text_normalizer.dart';
import 'attachment_text_source_policy.dart';

final class AttachmentDetailTextContent {
  const AttachmentDetailTextContent({
    required this.summary,
    required this.full,
  });

  final String summary;
  final String full;

  bool get hasAny => summary.isNotEmpty || full.isNotEmpty;
}

String attachmentDetailEmptyTextLabel(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode.toLowerCase();
  if (code.startsWith('zh')) return '无';
  return 'None';
}

AttachmentDetailTextContent resolveAttachmentDetailTextContent(
  Map<String, Object?>? payload, {
  String? annotationCaption,
}) {
  String read(String key, {bool normalizeOcr = false}) {
    final raw = (payload?[key] ?? '').toString();
    final normalized = normalizeOcr ? normalizeOcrTextForDisplay(raw) : raw;
    return normalized.trim();
  }

  String firstNonEmpty(List<String?> values) {
    for (final raw in values) {
      final value = (raw ?? '').trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  final selected = selectAttachmentDisplayText(payload);
  final caption = firstNonEmpty(<String?>[
    read('caption_long'),
    annotationCaption,
  ]);

  final summary = firstNonEmpty(<String?>[
    read('manual_summary'),
    read('summary'),
    read('knowledge_markdown_excerpt'),
    read('video_description_excerpt'),
    selected.excerpt,
    read('transcript_excerpt'),
    caption,
    read('ocr_text_excerpt', normalizeOcr: true),
    read('ocr_text', normalizeOcr: true),
    read('readable_text_excerpt'),
    read('extracted_text_excerpt'),
  ]);

  final normalizedMime = read('mime_type').toLowerCase();
  final isImagePayload = normalizedMime.startsWith('image/');
  final hasVideoPayloadSignal = payload != null &&
      (payload.containsKey('video_segment_count') ||
          payload.containsKey('video_segments') ||
          payload.containsKey('video_content_kind') ||
          payload.containsKey('video_proxy_sha256'));

  final imageFull = firstNonEmpty(<String?>[
    read('manual_full_text'),
    read('full_text'),
    read('manual_summary'),
    read('summary'),
    caption,
    selected.full,
    selected.excerpt,
    read('transcript_full'),
    read('transcript_excerpt'),
    read('ocr_text_full', normalizeOcr: true),
    read('ocr_text', normalizeOcr: true),
    read('readable_text_full'),
    read('extracted_text_full'),
    read('ocr_text_excerpt', normalizeOcr: true),
    read('readable_text_excerpt'),
    read('extracted_text_excerpt'),
  ]);

  final videoFull = firstNonEmpty(<String?>[
    read('manual_full_text'),
    read('full_text'),
    read('knowledge_markdown_full'),
    read('video_description_full'),
    selected.full,
    read('transcript_full'),
    read('ocr_text_full', normalizeOcr: true),
    read('ocr_text', normalizeOcr: true),
    read('readable_text_full'),
    read('extracted_text_full'),
    read('knowledge_markdown_excerpt'),
    read('video_description_excerpt'),
    read('transcript_excerpt'),
    read('ocr_text_excerpt', normalizeOcr: true),
    read('readable_text_excerpt'),
    read('extracted_text_excerpt'),
    caption,
  ]);

  final nonImageFallbackFull = firstNonEmpty(<String?>[
    read('manual_full_text'),
    read('full_text'),
    selected.full,
    read('transcript_full'),
    read('manual_summary'),
    read('summary'),
    selected.excerpt,
    read('transcript_excerpt'),
    caption,
    read('ocr_text_full', normalizeOcr: true),
    read('ocr_text', normalizeOcr: true),
    read('readable_text_full'),
    read('extracted_text_full'),
    read('ocr_text_excerpt', normalizeOcr: true),
    read('readable_text_excerpt'),
    read('extracted_text_excerpt'),
  ]);

  final full = hasVideoPayloadSignal
      ? videoFull
      : (isImagePayload ? imageFull : nonImageFallbackFull);

  return AttachmentDetailTextContent(summary: summary, full: full);
}

Map<String, Object?> buildManualAttachmentTextPayload({
  required Map<String, Object?>? existingPayload,
  required String summary,
  required String full,
  required String mimeType,
}) {
  final normalizedSummary = summary.trim();
  final normalizedFull = full.trim();
  final next = Map<String, Object?>.from(existingPayload ?? const {});

  next['manual_summary'] = normalizedSummary;
  next['manual_full_text'] = normalizedFull;
  next['summary'] = normalizedSummary;
  next['full_text'] = normalizedFull;
  next['readable_text_excerpt'] = normalizedSummary;
  next['readable_text_full'] = normalizedFull;
  if (normalizedSummary.isNotEmpty || normalizedFull.isNotEmpty) {
    next['needs_ocr'] = false;
  }

  final normalizedMime = mimeType.trim().toLowerCase();
  if (normalizedMime.startsWith('image/')) {
    final caption =
        normalizedFull.isNotEmpty ? normalizedFull : normalizedSummary;
    next['caption_long'] = caption;
  }

  if (normalizedMime.startsWith('audio/')) {
    next['transcript_excerpt'] = normalizedSummary;
    next['transcript_full'] = normalizedFull;
  }

  return next;
}
