import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/attachment_payload_refresh_policy.dart';

void main() {
  test('refreshes when payload is missing', () {
    final shouldRefresh = shouldRefreshAttachmentAnnotationPayloadOnSync(
      payload: null,
      ocrRunning: false,
      ocrStatusText: null,
    );

    expect(shouldRefresh, isTrue);
  });

  test('refreshes when payload has no usable text', () {
    final shouldRefresh = shouldRefreshAttachmentAnnotationPayloadOnSync(
      payload: const <String, Object?>{
        'needs_ocr': false,
        'extracted_text_excerpt': '',
        'ocr_text_excerpt': '',
      },
      ocrRunning: false,
      ocrStatusText: null,
    );

    expect(shouldRefresh, isTrue);
  });

  test('refreshes when OCR is marked as running', () {
    final shouldRefresh = shouldRefreshAttachmentAnnotationPayloadOnSync(
      payload: const <String, Object?>{
        'ocr_auto_status': 'running',
        'needs_ocr': true,
      },
      ocrRunning: false,
      ocrStatusText: null,
    );

    expect(shouldRefresh, isTrue);
  });

  test('does not refresh when payload already has text and OCR is idle', () {
    final shouldRefresh = shouldRefreshAttachmentAnnotationPayloadOnSync(
      payload: const <String, Object?>{
        'extracted_text_excerpt': 'already done',
        'needs_ocr': false,
      },
      ocrRunning: false,
      ocrStatusText: null,
    );

    expect(shouldRefresh, isFalse);
  });
}
