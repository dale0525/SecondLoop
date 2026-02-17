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

  test(
      'extractMultimodalVideoInsight does not treat video_kind as content kind',
      () {
    final payloadJson = jsonEncode(<String, Object?>{
      'video_kind': 'knowledge',
      'summary': 'Fallback summary only.',
    });

    final insight = extractMultimodalVideoInsight(
      payloadJson,
      defaultEngine: 'multimodal_byok_video_extract:gpt-4.1-mini',
    );

    expect(insight, isNotNull);
    expect(insight!.contentKind, 'unknown');
    expect(insight.summary, 'Fallback summary only.');
  });

  test('mergeMultimodalVideoInsights aggregates multi-segment knowledge fields',
      () {
    final merged = mergeMultimodalVideoInsights([
      const MultimodalVideoInsight(
        contentKind: 'knowledge',
        summary: 'Part 1 explains segmentation.',
        knowledgeMarkdown: '## Segment 1\n- split to 20 minutes',
        videoDescription: '',
        engine: 'multimodal_cloud_video_extract:gpt-4.1-mini',
      ),
      const MultimodalVideoInsight(
        contentKind: 'knowledge',
        summary: 'Part 2 explains OCR fallback.',
        knowledgeMarkdown: '## Segment 2\n- fallback to local OCR',
        videoDescription: '',
        engine: 'multimodal_cloud_video_extract:gpt-4.1-mini',
      ),
    ]);

    expect(merged, isNotNull);
    expect(merged!.contentKind, 'knowledge');
    expect(merged.summary, contains('Part 1'));
    expect(merged.summary, contains('Part 2'));
    expect(merged.knowledgeMarkdown, contains('Segment 1'));
    expect(merged.knowledgeMarkdown, contains('Segment 2'));
    expect(merged.videoDescription, isEmpty);
  });

  test('mergeMultimodalVideoInsights picks non-knowledge by majority', () {
    final merged = mergeMultimodalVideoInsights([
      const MultimodalVideoInsight(
        contentKind: 'non_knowledge',
        summary: 'Cooking opening scene.',
        knowledgeMarkdown: '',
        videoDescription: 'Two people prep ingredients.',
        engine: 'multimodal_byok_video_extract:gpt-4.1-mini',
      ),
      const MultimodalVideoInsight(
        contentKind: 'non_knowledge',
        summary: 'Main cooking scene.',
        knowledgeMarkdown: '',
        videoDescription: 'Pan frying and plating.',
        engine: 'multimodal_byok_video_extract:gpt-4.1-mini',
      ),
      const MultimodalVideoInsight(
        contentKind: 'knowledge',
        summary: 'A short recipe tip.',
        knowledgeMarkdown: '- Keep heat medium',
        videoDescription: '',
        engine: 'multimodal_cloud_video_extract:gpt-4.1-mini',
      ),
    ]);

    expect(merged, isNotNull);
    expect(merged!.contentKind, 'non_knowledge');
    expect(merged.summary, contains('Cooking opening scene.'));
    expect(merged.summary, contains('Main cooking scene.'));
    expect(merged.videoDescription, contains('prep ingredients'));
    expect(merged.videoDescription, contains('Pan frying'));
  });

  test('mergeMultimodalVideoInsights returns null when no useful insight', () {
    expect(mergeMultimodalVideoInsights(const []), isNull);
    expect(mergeMultimodalVideoInsights(const [null]), isNull);
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
