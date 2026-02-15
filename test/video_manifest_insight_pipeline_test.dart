import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/content_enrichment/multimodal_ocr.dart';
import 'package:secondloop/core/media_enrichment/media_enrichment_gate.dart';
import 'package:secondloop/features/attachments/attachment_detail_text_content.dart';
import 'package:secondloop/features/attachments/non_image_attachment_view.dart';
import 'package:secondloop/features/attachments/video_keyframe_ocr_worker.dart';
import 'package:secondloop/features/share/share_ingest_gate.dart';

void main() {
  ParsedVideoManifest parseManifest(Map<String, Object?> payload) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final parsed = parseVideoManifestPayload(bytes);
    expect(parsed, isNotNull);
    return parsed!;
  }

  test(
    'ingest manifest + multimodal insight produces viewer-ready knowledge payload',
    () {
      final manifestPayload = buildVideoManifestPayload(
        videoSha256: 'sha_seg_0',
        videoMimeType: 'video/mp4',
        audioSha256: 'sha_audio',
        audioMimeType: 'audio/mp4',
        segmentCount: 2,
        videoSegments: const [
          (index: 0, sha256: 'sha_seg_0', mimeType: 'video/mp4'),
          (index: 1, sha256: 'sha_seg_1', mimeType: 'video/mp4'),
        ],
      );
      final manifest = parseManifest(manifestPayload);

      const insight = MultimodalVideoInsight(
        contentKind: 'knowledge',
        summary: 'Video explains OCR fallback decision tree.',
        knowledgeMarkdown: '## Key steps\n1. Segment\n2. OCR\n3. Summarize',
        videoDescription: 'unused narrative text',
        engine: 'multimodal_cloud_video_extract:gpt-4.1-mini',
      );

      final payload = buildAutoVideoManifestOcrPayload(
        runningPayload: <String, Object?>{
          'video_description_full': 'legacy narrative',
          'video_description_excerpt': 'legacy excerpt',
        },
        manifest: manifest,
        maxSegments: 6,
        processedSegments: 2,
        transcriptFull: 'Transcript full body',
        transcriptExcerpt: 'Transcript excerpt',
        readableTextFull: 'Readable full body',
        readableTextExcerpt: 'Readable excerpt',
        ocrFullText: 'OCR full body',
        ocrExcerpt: 'OCR excerpt',
        ocrEngine: 'keyframe_engine',
        languageHints: 'device_plus_en',
        ocrTruncated: false,
        totalFrameCount: 9,
        totalProcessedFrames: 9,
        heuristicContentKind: 'non_knowledge',
        multimodalInsight: insight,
        nowMs: 1700000001000,
      );

      expect(payload['video_content_kind'], 'knowledge');
      expect(
        payload['video_content_kind_engine'],
        'multimodal_cloud_video_extract:gpt-4.1-mini',
      );
      expect(payload['knowledge_markdown_full'], contains('Key steps'));
      expect(payload.containsKey('video_description_full'), isFalse);
      expect(payload['video_segment_count'], 2);
      expect(payload['video_processed_segment_count'], 2);

      final viewerInsight = resolveVideoManifestInsightContent(payload);
      expect(viewerInsight, isNotNull);
      expect(viewerInsight!.contentKind, 'knowledge');
      expect(
          viewerInsight.summary, 'Video explains OCR fallback decision tree.');
      expect(viewerInsight.detail, contains('Segment'));

      final detailText = resolveAttachmentDetailTextContent(payload);
      expect(detailText.summary, 'Video explains OCR fallback decision tree.');
      expect(detailText.full, contains('Key steps'));
    },
  );

  test(
    'ingest manifest + heuristic fallback produces viewer-ready non-knowledge payload',
    () {
      final manifestPayload = buildVideoManifestPayload(
        videoSha256: 'sha_seg_0',
        videoMimeType: 'video/mp4',
        videoSegments: const [
          (index: 0, sha256: 'sha_seg_0', mimeType: 'video/mp4'),
          (index: 1, sha256: 'sha_seg_1', mimeType: 'video/mp4'),
          (index: 2, sha256: 'sha_seg_2', mimeType: 'video/mp4'),
        ],
      );
      final manifest = parseManifest(manifestPayload);

      final payload = buildAutoVideoManifestOcrPayload(
        runningPayload: <String, Object?>{
          'video_content_kind_engine': 'legacy_engine',
          'knowledge_markdown_full': 'legacy knowledge',
          'knowledge_markdown_excerpt': 'legacy knowledge excerpt',
          'ocr_auto_last_failure_ms': 123,
        },
        manifest: manifest,
        maxSegments: 6,
        processedSegments: 3,
        transcriptFull: '',
        transcriptExcerpt: '',
        readableTextFull:
            'Two people are cooking in a kitchen and chatting casually.',
        readableTextExcerpt: 'People cooking and chatting in a kitchen.',
        ocrFullText: 'OCR full body',
        ocrExcerpt: 'OCR excerpt',
        ocrEngine: 'keyframe_engine',
        languageHints: 'zh_en',
        ocrTruncated: true,
        totalFrameCount: 15,
        totalProcessedFrames: 11,
        heuristicContentKind: 'non_knowledge',
        multimodalInsight: null,
        nowMs: 1800000001000,
      );

      expect(payload['video_content_kind'], 'non_knowledge');
      expect(payload.containsKey('video_content_kind_engine'), isFalse);
      expect(payload.containsKey('knowledge_markdown_full'), isFalse);
      expect(payload.containsKey('knowledge_markdown_excerpt'), isFalse);
      expect(
        payload['video_description_full'],
        'Two people are cooking in a kitchen and chatting casually.',
      );
      expect(payload['video_description_excerpt'], contains('kitchen'));
      expect(payload.containsKey('ocr_auto_last_failure_ms'), isFalse);

      final viewerInsight = resolveVideoManifestInsightContent(payload);
      expect(viewerInsight, isNotNull);
      expect(viewerInsight!.contentKind, 'non_knowledge');
      expect(
          viewerInsight.summary, 'People cooking and chatting in a kitchen.');
      expect(viewerInsight.detail, contains('cooking'));

      final detailText = resolveAttachmentDetailTextContent(payload);
      expect(detailText.summary, 'People cooking and chatting in a kitchen.');
      expect(detailText.full, contains('kitchen'));
    },
  );

  test(
      'viewer insight falls back to legacy content-kind keys and transcript progress',
      () {
    final payload = <String, Object?>{
      'video_kind': 'knowledge',
      'video_segment_count': 1,
      'video_processed_segment_count': 0,
      'needs_ocr': false,
      'transcript_full': 'Structured transcript content',
      'video_summary': 'Legacy summary',
      'readable_text_full': 'Structured transcript content',
    };

    final viewerInsight = resolveVideoManifestInsightContent(payload);

    expect(viewerInsight, isNotNull);
    expect(viewerInsight!.contentKind, 'knowledge');
    expect(viewerInsight.segmentCount, 1);
    expect(viewerInsight.processedSegmentCount, 1);
  });

  test('viewer insight infers non-knowledge when summary exists without kind',
      () {
    final payload = <String, Object?>{
      'video_summary': 'People are walking near a harbor.',
      'readable_text_excerpt': 'People are walking near a harbor.',
      'video_segment_count': 1,
      'video_processed_segment_count': 0,
      'needs_ocr': false,
    };

    final viewerInsight = resolveVideoManifestInsightContent(payload);

    expect(viewerInsight, isNotNull);
    expect(viewerInsight!.contentKind, 'non_knowledge');
    expect(viewerInsight.summary, contains('harbor'));
    expect(viewerInsight.processedSegmentCount, 1);
  });

  test('viewer insight infers non-knowledge from legacy description fields',
      () {
    final payload = <String, Object?>{
      'video_segment_count': 2,
      'video_processed_segment_count': 1,
      'video_description_excerpt': 'A family walks through a market.',
      'readable_text_excerpt': 'A family walks through a market.',
    };

    final viewerInsight = resolveVideoManifestInsightContent(payload);

    expect(viewerInsight, isNotNull);
    expect(viewerInsight!.contentKind, 'non_knowledge');
    expect(viewerInsight.summary, contains('family'));
  });
}
