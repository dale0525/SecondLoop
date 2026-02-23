import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/media_enrichment/media_enrichment_gate.dart';
import 'package:secondloop/core/content_enrichment/multimodal_ocr.dart';
import 'package:secondloop/features/attachments/non_image_attachment_view.dart';
import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';
import 'package:secondloop/features/attachments/video_keyframe_ocr_worker.dart';

void main() {
  test('runAutoVideoSegmentOcrWithFallback prefers multimodal OCR', () async {
    var multimodalCalls = 0;
    var keyframeCalls = 0;

    final result = await runAutoVideoSegmentOcrWithFallback(
      shouldTryMultimodalOcr: true,
      canUseNetworkOcr: true,
      runMultimodalOcr: () async {
        multimodalCalls += 1;
        return const PlatformPdfOcrResult(
          fullText: 'multimodal text',
          excerpt: 'multimodal text',
          engine: 'multimodal_engine',
          isTruncated: false,
          pageCount: 2,
          processedPages: 2,
        );
      },
      runKeyframeOcr: () async {
        keyframeCalls += 1;
        return const VideoKeyframeOcrResult(
          fullText: 'keyframe text',
          excerpt: 'keyframe text',
          engine: 'keyframe_engine',
          isTruncated: false,
          frameCount: 4,
          processedFrames: 3,
        );
      },
    );

    expect(multimodalCalls, 1);
    expect(keyframeCalls, 0);
    expect(result, isNotNull);
    expect(result!.source, AutoVideoSegmentOcrSource.multimodal);
    expect(result.fullText, 'multimodal text');
    expect(result.engine, 'multimodal_engine');
    expect(result.pageCount, 2);
    expect(result.processedPages, 2);
  });

  test('runAutoVideoSegmentOcrWithFallback falls back to keyframe OCR',
      () async {
    var multimodalCalls = 0;
    var keyframeCalls = 0;

    final result = await runAutoVideoSegmentOcrWithFallback(
      shouldTryMultimodalOcr: true,
      canUseNetworkOcr: true,
      runMultimodalOcr: () async {
        multimodalCalls += 1;
        return null;
      },
      runKeyframeOcr: () async {
        keyframeCalls += 1;
        return const VideoKeyframeOcrResult(
          fullText: 'keyframe text',
          excerpt: 'keyframe text',
          engine: 'keyframe_engine',
          isTruncated: true,
          frameCount: 6,
          processedFrames: 4,
        );
      },
    );

    expect(multimodalCalls, 1);
    expect(keyframeCalls, 1);
    expect(result, isNotNull);
    expect(result!.source, AutoVideoSegmentOcrSource.keyframe);
    expect(result.fullText, 'keyframe text');
    expect(result.engine, 'keyframe_engine');
    expect(result.pageCount, 6);
    expect(result.processedPages, 4);
    expect(result.isTruncated, isTrue);
  });

  test('runAutoVideoSegmentOcrWithFallback skips multimodal when disallowed',
      () async {
    var multimodalCalls = 0;
    var keyframeCalls = 0;

    final result = await runAutoVideoSegmentOcrWithFallback(
      shouldTryMultimodalOcr: true,
      canUseNetworkOcr: false,
      runMultimodalOcr: () async {
        multimodalCalls += 1;
        return const PlatformPdfOcrResult(
          fullText: 'multimodal text',
          excerpt: 'multimodal text',
          engine: 'multimodal_engine',
          isTruncated: false,
          pageCount: 1,
          processedPages: 1,
        );
      },
      runKeyframeOcr: () async {
        keyframeCalls += 1;
        return const VideoKeyframeOcrResult(
          fullText: 'local text',
          excerpt: 'local text',
          engine: 'keyframe_engine',
          isTruncated: false,
          frameCount: 3,
          processedFrames: 3,
        );
      },
    );

    expect(multimodalCalls, 0);
    expect(keyframeCalls, 1);
    expect(result, isNotNull);
    expect(result!.source, AutoVideoSegmentOcrSource.keyframe);
  });

  test(
    'buildAutoVideoManifestOcrPayload prefers multimodal insight and clears stale non-knowledge fields',
    () {
      const manifest = ParsedVideoManifest(
        originalSha256: 'sha-original',
        originalMimeType: 'video/mp4',
        audioSha256: 'sha-audio',
        audioMimeType: 'audio/mp4',
        segments: [
          VideoManifestSegmentRef(
            index: 0,
            sha256: 'sha-seg-1',
            mimeType: 'video/mp4',
          ),
        ],
      );

      const multimodalInsight = MultimodalVideoInsight(
        contentKind: 'knowledge',
        summary: 'A concise multimodal summary.',
        knowledgeMarkdown: '## Steps\n1. Capture\n2. Explain',
        videoDescription: 'should not be used',
        engine: 'multimodal_cloud_video_extract:gpt-4.1-mini',
      );

      final payload = buildAutoVideoManifestOcrPayload(
        runningPayload: <String, Object?>{
          'ocr_auto_running_ms': 1,
          'video_description_full': 'legacy detail',
          'video_description_excerpt': 'legacy excerpt',
        },
        manifest: manifest,
        maxSegments: 6,
        processedSegments: 1,
        transcriptFull: 'Transcript full',
        transcriptExcerpt: 'Transcript excerpt',
        readableTextFull: 'Readable full',
        readableTextExcerpt: 'Readable excerpt',
        ocrFullText: 'OCR full',
        ocrExcerpt: 'OCR excerpt',
        ocrEngine: 'keyframe_engine',
        languageHints: 'device_plus_en',
        ocrTruncated: false,
        totalFrameCount: 3,
        totalProcessedFrames: 3,
        heuristicContentKind: 'non_knowledge',
        multimodalInsight: multimodalInsight,
        ocrKeyframes: const <VideoManifestPreviewRef>[
          VideoManifestPreviewRef(
            index: 1,
            sha256: 'sha-kf-1',
            mimeType: 'image/jpeg',
            tMs: 1000,
            kind: 'slide',
          ),
        ],
        ocrKeyframeTexts: const <VideoManifestKeyframeOcrText>[
          VideoManifestKeyframeOcrText(
            index: 1,
            sha256: 'sha-kf-1',
            mimeType: 'image/jpeg',
            tMs: 1000,
            kind: 'slide',
            text: 'Slide title',
          ),
        ],
        nowMs: 1700000000000,
      );

      expect(payload['video_content_kind'], 'knowledge');
      expect(
        payload['video_content_kind_engine'],
        'multimodal_cloud_video_extract:gpt-4.1-mini',
      );
      expect(payload.containsKey('video_kind'), isFalse);
      expect(payload.containsKey('video_kind_confidence'), isFalse);
      expect(payload['video_summary'], 'A concise multimodal summary.');
      expect(
        payload['knowledge_markdown_full'],
        '## Steps\n1. Capture\n2. Explain',
      );
      expect(
        payload['knowledge_markdown_excerpt'],
        '## Steps\n1. Capture\n2. Explain',
      );
      expect(payload.containsKey('video_description_full'), isFalse);
      expect(payload.containsKey('video_description_excerpt'), isFalse);
      expect(payload['ocr_auto_status'], 'ok');
      expect(payload['ocr_auto_last_success_ms'], 1700000000000);
      expect(
        payload['ocr_keyframes'],
        [
          {
            'index': 1,
            'sha256': 'sha-kf-1',
            'mime_type': 'image/jpeg',
            't_ms': 1000,
            'kind': 'slide',
          },
        ],
      );
      expect(
        payload['ocr_keyframe_texts'],
        [
          {
            'index': 1,
            'sha256': 'sha-kf-1',
            'mime_type': 'image/jpeg',
            't_ms': 1000,
            'kind': 'slide',
            'text': 'Slide title',
          },
        ],
      );

      final viewerInsight = resolveVideoManifestInsightContent(payload);
      expect(viewerInsight, isNotNull);
      expect(viewerInsight!.contentKind, 'knowledge');
      expect(viewerInsight.summary, 'A concise multimodal summary.');
      expect(viewerInsight.detail, contains('Capture'));
      expect(viewerInsight.segmentCount, 1);
      expect(viewerInsight.processedSegmentCount, 1);
    },
  );

  test(
    'buildAutoVideoManifestOcrPayload uses heuristic non-knowledge fallback and removes stale multimodal fields',
    () {
      const manifest = ParsedVideoManifest(
        originalSha256: 'sha-original',
        originalMimeType: 'video/mp4',
        segments: [
          VideoManifestSegmentRef(
            index: 0,
            sha256: 'sha-seg-1',
            mimeType: 'video/mp4',
          ),
          VideoManifestSegmentRef(
            index: 1,
            sha256: 'sha-seg-2',
            mimeType: 'video/mp4',
          ),
        ],
      );

      final payload = buildAutoVideoManifestOcrPayload(
        runningPayload: <String, Object?>{
          'video_content_kind_engine': 'legacy_engine',
          'knowledge_markdown_full': 'legacy knowledge',
          'knowledge_markdown_excerpt': 'legacy excerpt',
          'ocr_auto_last_failure_ms': 42,
        },
        manifest: manifest,
        maxSegments: 6,
        processedSegments: 2,
        transcriptFull: '',
        transcriptExcerpt: '',
        readableTextFull:
            'A family is walking through a market while chatting casually.',
        readableTextExcerpt: 'Family walking through a market scene.',
        ocrFullText: 'OCR full',
        ocrExcerpt: 'OCR excerpt',
        ocrEngine: 'keyframe_engine',
        languageHints: 'zh_en',
        ocrTruncated: true,
        totalFrameCount: 12,
        totalProcessedFrames: 8,
        heuristicContentKind: 'non_knowledge',
        multimodalInsight: null,
        nowMs: 1800000000000,
      );

      expect(payload['video_content_kind'], 'non_knowledge');
      expect(payload.containsKey('video_content_kind_engine'), isFalse);
      expect(payload.containsKey('video_kind'), isFalse);
      expect(payload.containsKey('video_kind_confidence'), isFalse);
      expect(payload.containsKey('knowledge_markdown_full'), isFalse);
      expect(payload.containsKey('knowledge_markdown_excerpt'), isFalse);
      expect(
        payload['video_description_full'],
        'A family is walking through a market while chatting casually.',
      );
      expect(
        payload['video_description_excerpt'],
        'Family walking through a market scene.',
      );
      expect(
          payload['video_summary'], 'Family walking through a market scene.');
      expect(payload.containsKey('transcript_full'), isFalse);
      expect(payload.containsKey('transcript_excerpt'), isFalse);
      expect(payload.containsKey('ocr_auto_last_failure_ms'), isFalse);

      final viewerInsight = resolveVideoManifestInsightContent(payload);
      expect(viewerInsight, isNotNull);
      expect(viewerInsight!.contentKind, 'non_knowledge');
      expect(viewerInsight.summary, 'Family walking through a market scene.');
      expect(viewerInsight.detail, contains('market'));
      expect(viewerInsight.segmentCount, 2);
      expect(viewerInsight.processedSegmentCount, 2);
    },
  );
}
