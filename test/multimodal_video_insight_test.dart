import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/content_enrichment/multimodal_ocr.dart';

void main() {
  test('extractMultimodalVideoInsight parses knowledge payload fields', () {
    final payloadJson = jsonEncode(<String, Object?>{
      'video_content_kind': 'knowledge',
      'video_summary': 'A lesson on OCR fallback strategy.',
      'knowledge_markdown': '## Key points\n1. multimodal\n2. local fallback',
      'video_description': '',
    });

    final insight = extractMultimodalVideoInsight(
      payloadJson,
      defaultEngine: 'multimodal_cloud_video_extract:gpt-4.1-mini',
    );

    expect(insight, isNotNull);
    expect(insight!.contentKind, 'knowledge');
    expect(insight.summary, 'A lesson on OCR fallback strategy.');
    expect(insight.knowledgeMarkdown, contains('Key points'));
    expect(insight.videoDescription, isEmpty);
    expect(insight.engine, 'multimodal_cloud_video_extract:gpt-4.1-mini');
  });

  test('extractMultimodalVideoInsight infers non-knowledge detail fallback',
      () {
    final payloadJson = jsonEncode(<String, Object?>{
      'video_content_kind': 'non_knowledge',
      'summary': 'A travel vlog clip.',
      'full_text': 'Sunset, walking on the beach, crowd ambience.',
    });

    final insight = extractMultimodalVideoInsight(
      payloadJson,
      defaultEngine: 'multimodal_byok_video_extract:gpt-4.1-mini',
    );

    expect(insight, isNotNull);
    expect(insight!.contentKind, 'non_knowledge');
    expect(insight.summary, 'A travel vlog clip.');
    expect(insight.videoDescription, contains('Sunset'));
    expect(insight.knowledgeMarkdown, isEmpty);
  });

  test('extractMultimodalVideoInsight returns null for invalid payload', () {
    expect(
      extractMultimodalVideoInsight('{not-json}', defaultEngine: 'x'),
      isNull,
    );
    expect(
      extractMultimodalVideoInsight('{}', defaultEngine: 'x'),
      isNull,
    );
  });
}
