import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/media_enrichment/media_enrichment_gate.dart';
import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';

void main() {
  test('buildAutoPdfOcrSuccessPayload persists retryable partial metadata', () {
    final payload = buildAutoPdfOcrSuccessPayload(
      runningPayload: <String, Object?>{
        'ocr_auto_status': 'running',
        'ocr_auto_running_ms': 1700000000000,
      },
      sourcePayload: <String, Object?>{
        'page_count': 25,
        'extracted_text_full': '',
        'extracted_text_excerpt': '',
      },
      ocr: const PlatformPdfOcrResult(
        fullText: 'partial text',
        excerpt: 'partial text',
        engine: 'multimodal_cloud_ocr_markdown:gpt-4.1-mini+partial',
        isTruncated: true,
        pageCount: 25,
        processedPages: 15,
        partial: true,
        retryable: true,
        failedRanges: <Map<String, int>>[
          {'start_page': 11, 'end_page': 20},
        ],
        completedRanges: <Map<String, int>>[
          {'start_page': 1, 'end_page': 10},
          {'start_page': 21, 'end_page': 25},
        ],
      ),
      languageHints: 'device_plus_en',
      dpi: 180,
      nowMs: 1700000000100,
    );

    expect(payload['ocr_partial'], isTrue);
    expect(payload['ocr_retryable'], isTrue);
    expect(payload['ocr_failed_ranges'], isNotEmpty);
    expect(payload['ocr_completed_ranges'], isNotEmpty);
    expect(payload['needs_ocr'], isTrue);
    expect(payload['ocr_auto_status'], 'ok');
  });

  test('buildAutoPdfOcrSuccessPayload clears partial metadata on full success',
      () {
    final payload = buildAutoPdfOcrSuccessPayload(
      runningPayload: <String, Object?>{
        'ocr_auto_status': 'running',
        'ocr_partial': true,
        'ocr_retryable': true,
        'ocr_failed_ranges': const [
          {'start_page': 11, 'end_page': 20},
        ],
      },
      sourcePayload: <String, Object?>{
        'page_count': 10,
        'extracted_text_full': '',
        'extracted_text_excerpt': '',
      },
      ocr: const PlatformPdfOcrResult(
        fullText: 'full text',
        excerpt: 'full text',
        engine: 'multimodal_cloud_ocr_markdown:gpt-4.1-mini',
        isTruncated: false,
        pageCount: 10,
        processedPages: 10,
      ),
      languageHints: 'device_plus_en',
      dpi: 180,
      nowMs: 1700000000200,
    );

    expect(payload['ocr_partial'], isFalse);
    expect(payload['ocr_retryable'], isFalse);
    expect(payload.containsKey('ocr_failed_ranges'), isFalse);
    expect(payload.containsKey('ocr_completed_ranges'), isFalse);
    expect(payload['needs_ocr'], isFalse);
    expect(payload['ocr_auto_status'], 'ok');
  });
}
