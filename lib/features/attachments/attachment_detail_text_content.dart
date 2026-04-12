import 'package:flutter/widgets.dart';

import '../../i18n/strings.g.dart';

import 'audio_transcript_turn_view_display.dart';
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

const String kPreferredAttachmentContentKindKey =
    '_secondloop_preferred_attachment_kind';
const String kPreferredAttachmentChunkIndexKey =
    '_secondloop_preferred_attachment_chunk';

String attachmentDetailEmptyTextLabel(BuildContext context) {
  return context.t.attachments.content.emptyText;
}

AttachmentDetailTextContent resolveAttachmentDetailTextContent(
  Map<String, Object?>? payload, {
  String? annotationCaption,
  String? mimeTypeOverride,
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

  AttachmentDetailTextContent? resolvePreferredContent(String rawKind) {
    final normalizedKind = rawKind.trim().toLowerCase();
    if (normalizedKind.isEmpty) return null;

    String content(String excerpt, String full) {
      final normalizedExcerpt = excerpt.trim();
      final normalizedFull = full.trim();
      return normalizedFull.isNotEmpty ? normalizedFull : normalizedExcerpt;
    }

    switch (normalizedKind) {
      case 'transcript':
      case 'transcript_full':
        final excerpt = firstNonEmpty(<String?>[
          read('transcript_excerpt'),
          read('transcript_full'),
        ]);
        final full =
            content(read('transcript_excerpt'), read('transcript_full'));
        if (excerpt.isEmpty && full.isEmpty) return null;
        return AttachmentDetailTextContent(summary: excerpt, full: full);
      case 'ocr_text':
      case 'ocr_text_full':
        final excerpt = firstNonEmpty(<String?>[
          read('ocr_text_excerpt', normalizeOcr: true),
          read('ocr_text_full', normalizeOcr: true),
          read('ocr_text', normalizeOcr: true),
        ]);
        final full = firstNonEmpty(<String?>[
          read('ocr_text_full', normalizeOcr: true),
          read('ocr_text', normalizeOcr: true),
          read('ocr_text_excerpt', normalizeOcr: true),
        ]);
        if (excerpt.isEmpty && full.isEmpty) return null;
        return AttachmentDetailTextContent(summary: excerpt, full: full);
      case 'readable_text':
      case 'readable_text_full':
        final excerpt = firstNonEmpty(<String?>[
          read('readable_text_excerpt'),
          read('readable_text_full'),
        ]);
        final full =
            firstNonEmpty(<String?>[read('readable_text_full'), excerpt]);
        if (excerpt.isEmpty && full.isEmpty) return null;
        return AttachmentDetailTextContent(summary: excerpt, full: full);
      case 'extracted_text':
      case 'extracted_text_full':
        final excerpt = firstNonEmpty(<String?>[
          read('extracted_text_excerpt'),
          read('extracted_text_full'),
        ]);
        final full =
            firstNonEmpty(<String?>[read('extracted_text_full'), excerpt]);
        if (excerpt.isEmpty && full.isEmpty) return null;
        return AttachmentDetailTextContent(summary: excerpt, full: full);
      case 'summary':
      case 'metadata':
        final excerpt = firstNonEmpty(<String?>[
          read('manual_summary'),
          read('llm_summary'),
          read('summary'),
        ]);
        final full = firstNonEmpty(<String?>[
          read('manual_full_text'),
          read('full_text'),
          excerpt,
        ]);
        if (excerpt.isEmpty && full.isEmpty) return null;
        return AttachmentDetailTextContent(summary: excerpt, full: full);
    }

    return null;
  }

  final selected = selectAttachmentDisplayText(payload);
  final preferredKind = read(kPreferredAttachmentContentKindKey);
  final preferredContent =
      preferredKind.isEmpty ? null : resolvePreferredContent(preferredKind);
  if (preferredContent != null && preferredContent.hasAny) {
    return preferredContent;
  }
  final caption = firstNonEmpty(<String?>[
    read('caption_long'),
    annotationCaption,
  ]);
  final ocrFull = firstNonEmpty(<String?>[
    read('ocr_text_full', normalizeOcr: true),
    read('ocr_text', normalizeOcr: true),
    read('ocr_text_excerpt', normalizeOcr: true),
  ]);

  final summary = firstNonEmpty(<String?>[
    read('manual_summary'),
    read('llm_summary'),
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

  final normalizedMime = firstNonEmpty(<String?>[
    mimeTypeOverride,
    read('mime_type'),
  ]).toLowerCase();
  final isAudioPayload = normalizedMime.startsWith('audio/');
  final isImagePayload = normalizedMime.startsWith('image/');
  final isUrlPayload = normalizedMime == 'application/x.secondloop.url+json';
  final hasVideoPayloadSignal = payload != null &&
      (payload.containsKey('video_segment_count') ||
          payload.containsKey('video_segments') ||
          payload.containsKey('video_content_kind') ||
          payload.containsKey('video_proxy_sha256'));

  final selectedNonOcr = selected.source == AttachmentTextSource.ocr
      ? ''
      : firstNonEmpty(<String?>[
          selected.full,
          selected.excerpt,
        ]);

  final imageManualFull = firstNonEmpty(<String?>[
    read('manual_full_text'),
    read('manual_summary'),
  ]);

  final imageAiFull = firstNonEmpty(<String?>[
    read('llm_summary'),
    read('summary'),
    caption,
    selectedNonOcr,
    read('full_text'),
    read('transcript_full'),
    read('transcript_excerpt'),
    read('readable_text_full'),
    read('extracted_text_full'),
    read('readable_text_excerpt'),
    read('extracted_text_excerpt'),
  ]);
  final imageCombinedFull = _mergeWithBlankLine(imageAiFull, ocrFull);
  final imageFallbackFull = firstNonEmpty(<String?>[
    selected.full,
    selected.excerpt,
    read('transcript_full'),
    read('transcript_excerpt'),
    read('full_text'),
    read('readable_text_full'),
    read('extracted_text_full'),
    read('readable_text_excerpt'),
    read('extracted_text_excerpt'),
  ]);
  final imageFull = firstNonEmpty(<String?>[
    imageManualFull,
    imageCombinedFull,
    imageFallbackFull,
    caption,
    ocrFull,
  ]);

  final audioTurnText = isAudioPayload
      ? resolveAudioTranscriptTurnViewDisplayText(payload)
      : const AudioTranscriptTurnViewDisplayText(excerpt: '', full: '');
  final audioTurnSummary = audioTurnText.excerpt;
  final audioTurnFull = audioTurnText.full;

  final audioSummary = firstNonEmpty(<String?>[
    read('manual_summary'),
    read('llm_summary'),
    read('summary'),
    audioTurnSummary,
    selected.excerpt,
    read('transcript_excerpt'),
    caption,
    read('readable_text_excerpt'),
    read('extracted_text_excerpt'),
  ]);

  final audioFull = firstNonEmpty(<String?>[
    read('manual_full_text'),
    audioTurnFull,
    read('transcript_full'),
    read('full_text'),
    read('manual_summary'),
    read('llm_summary'),
    read('summary'),
    read('transcript_excerpt'),
    selected.full,
    selected.excerpt,
    read('readable_text_full'),
    read('extracted_text_full'),
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
    read('llm_summary'),
    read('summary'),
    selected.excerpt,
    read('transcript_excerpt'),
    caption,
    ocrFull,
    read('readable_text_full'),
    read('extracted_text_full'),
    read('readable_text_excerpt'),
    read('extracted_text_excerpt'),
  ]);
  final urlSummaryForFull = firstNonEmpty(<String?>[
    read('manual_summary'),
    read('llm_summary'),
    read('summary'),
  ]);
  final urlFull =
      urlSummaryForFull.isNotEmpty ? urlSummaryForFull : nonImageFallbackFull;

  final full = hasVideoPayloadSignal
      ? videoFull
      : (isAudioPayload
          ? audioFull
          : (isImagePayload
              ? imageFull
              : (isUrlPayload ? urlFull : nonImageFallbackFull)));

  final effectiveSummary = isAudioPayload ? audioSummary : summary;

  return AttachmentDetailTextContent(summary: effectiveSummary, full: full);
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

String _mergeWithBlankLine(String first, String second) {
  final a = first.trim();
  final b = second.trim();
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  if (a == b) return a;
  if (a.contains(b)) return a;
  if (b.contains(a)) return b;
  return '$a\n\n$b';
}
