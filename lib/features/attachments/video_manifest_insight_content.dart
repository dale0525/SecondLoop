import '../../core/content_enrichment/video_ocr_auto_policy.dart';

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

  final rawContentKind = firstNonEmpty(const <String>[
    'video_content_kind',
    'content_kind',
  ]).toLowerCase();
  var contentKind = switch (rawContentKind) {
    'knowledge' || 'non_knowledge' => rawContentKind,
    _ => 'unknown',
  };

  final transcriptForInference = firstNonEmpty(const <String>[
    'transcript_full',
    'transcript_excerpt',
  ]);
  final ocrTextForInference = firstNonEmpty(const <String>[
    'ocr_text_full',
    'ocr_text_excerpt',
  ]);
  final readableTextForInference = firstNonEmpty(const <String>[
    'readable_text_full',
    'readable_text_excerpt',
    'transcript_full',
    'transcript_excerpt',
    'ocr_text_full',
    'ocr_text_excerpt',
    'video_summary',
  ]);

  if (contentKind == 'unknown') {
    final hasKnowledgeMarkdown = firstNonEmpty(const <String>[
      'knowledge_markdown_excerpt',
      'knowledge_markdown_full',
    ]).isNotEmpty;
    final hasVideoDescription = firstNonEmpty(const <String>[
      'video_description_excerpt',
      'video_description_full',
    ]).isNotEmpty;
    final hasSummarySignal = firstNonEmpty(const <String>[
      'video_summary',
      'readable_text_excerpt',
      'readable_text_full',
      'transcript_excerpt',
      'transcript_full',
      'ocr_text_excerpt',
      'ocr_text_full',
    ]).isNotEmpty;

    if (hasKnowledgeMarkdown && !hasVideoDescription) {
      contentKind = 'knowledge';
    } else if (hasVideoDescription && !hasKnowledgeMarkdown) {
      contentKind = 'non_knowledge';
    } else if (hasSummarySignal) {
      final inferred = inferVideoContentKind(
        transcriptFull: transcriptForInference,
        ocrTextFull: ocrTextForInference,
        readableTextFull: readableTextForInference,
      );
      if (inferred == 'knowledge' || inferred == 'non_knowledge') {
        contentKind = inferred;
      } else if (!hasKnowledgeMarkdown) {
        contentKind = 'non_knowledge';
      }
    }
  }

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
        'transcript_excerpt',
        'transcript_full',
        'ocr_text_excerpt',
        'ocr_text_full',
      ]),
    'non_knowledge' => firstNonEmpty(const <String>[
        'video_description_excerpt',
        'video_description_full',
        'readable_text_excerpt',
        'readable_text_full',
        'transcript_excerpt',
        'transcript_full',
        'ocr_text_excerpt',
        'ocr_text_full',
      ]),
    _ => firstNonEmpty(const <String>[
        'readable_text_excerpt',
        'readable_text_full',
        'transcript_excerpt',
        'transcript_full',
        'ocr_text_excerpt',
        'ocr_text_full',
      ]),
  };

  final segmentCount = _videoManifestAsInt(payload['video_segment_count']);
  var processedSegmentCount =
      _videoManifestAsInt(payload['video_processed_segment_count']);
  if (processedSegmentCount < 0) {
    processedSegmentCount = 0;
  }
  if (segmentCount > 0 && processedSegmentCount <= 0) {
    final hasReadableSignal = firstNonEmpty(const <String>[
      'readable_text_excerpt',
      'readable_text_full',
      'transcript_excerpt',
      'transcript_full',
      'video_summary',
      'knowledge_markdown_excerpt',
      'knowledge_markdown_full',
      'video_description_excerpt',
      'video_description_full',
      'ocr_text_excerpt',
      'ocr_text_full',
    ]).isNotEmpty;
    final needsOcr = payload['needs_ocr'] == true;
    if (!needsOcr && hasReadableSignal) {
      processedSegmentCount = segmentCount;
    }
  }
  if (segmentCount > 0 && processedSegmentCount > segmentCount) {
    processedSegmentCount = segmentCount;
  }

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
