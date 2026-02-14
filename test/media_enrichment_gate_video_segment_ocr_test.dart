import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/media_enrichment/media_enrichment_gate.dart';
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
}
