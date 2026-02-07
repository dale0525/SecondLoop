import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/content_enrichment/pdf_ocr_auto_policy.dart';

void main() {
  test('shouldAutoRunPdfOcr allows scanned PDF when auto page limit disabled',
      () {
    final payload = <String, Object?>{
      'mime_type': 'application/pdf',
      'needs_ocr': true,
      'page_count': 240,
    };
    expect(shouldAutoRunPdfOcr(payload, autoMaxPages: 0), isTrue);
  });

  test('shouldAutoRunPdfOcr allows PDF even when needs_ocr is false', () {
    final payload = <String, Object?>{
      'mime_type': 'application/pdf',
      'needs_ocr': false,
      'page_count': 8,
      'extracted_text_excerpt': 'garbled text',
    };
    expect(shouldAutoRunPdfOcr(payload, autoMaxPages: 0), isTrue);
  });

  test('shouldAutoRunPdfOcr returns false when page count exceeds limit', () {
    final payload = <String, Object?>{
      'mime_type': 'application/pdf',
      'needs_ocr': true,
      'page_count': 31,
    };
    expect(shouldAutoRunPdfOcr(payload, autoMaxPages: 30), isFalse);
  });

  test('shouldAutoRunPdfOcr returns false when OCR engine already exists', () {
    final payloadWithEngine = <String, Object?>{
      'mime_type': 'application/pdf',
      'needs_ocr': true,
      'page_count': 4,
      'ocr_engine': 'apple_vision',
    };

    expect(shouldAutoRunPdfOcr(payloadWithEngine, autoMaxPages: 30), isFalse);
  });

  test('shouldAutoRunPdfOcr skips while auto OCR is running recently', () {
    const nowMs = 1760000000000;
    final payload = <String, Object?>{
      'mime_type': 'application/pdf',
      'needs_ocr': true,
      'page_count': 4,
      'ocr_auto_status': 'running',
      'ocr_auto_running_ms': nowMs - 60 * 1000,
    };

    expect(
      shouldAutoRunPdfOcr(payload, autoMaxPages: 30, nowMs: nowMs),
      isFalse,
    );
  });

  test('shouldAutoRunPdfOcr retries when running state is stale', () {
    const nowMs = 1760000000000;
    final payload = <String, Object?>{
      'mime_type': 'application/pdf',
      'needs_ocr': true,
      'page_count': 4,
      'ocr_auto_status': 'running',
      'ocr_auto_running_ms': nowMs - 5 * 60 * 1000,
    };

    expect(
      shouldAutoRunPdfOcr(payload, autoMaxPages: 30, nowMs: nowMs),
      isTrue,
    );
  });

  test('shouldAutoRunPdfOcr respects cooldown after failed auto OCR', () {
    const nowMs = 1760000000000;
    final payload = <String, Object?>{
      'mime_type': 'application/pdf',
      'needs_ocr': true,
      'page_count': 4,
      'ocr_auto_status': 'failed',
      'ocr_auto_last_failure_ms': nowMs - 30 * 1000,
    };

    expect(
      shouldAutoRunPdfOcr(payload, autoMaxPages: 30, nowMs: nowMs),
      isFalse,
    );
  });
}
