import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/attachment_card.dart';

void main() {
  test('attachment card summary uses transcript excerpt when present', () {
    final summary = extractAttachmentCardSummaryFromPayload(
      const <String, Object?>{
        'transcript_excerpt': 'hello from transcript excerpt',
        'transcript_full': 'hello from transcript full',
      },
    );

    expect(summary, 'hello from transcript excerpt');
  });

  test('attachment card summary falls back to transcript full', () {
    final summary = extractAttachmentCardSummaryFromPayload(
      const <String, Object?>{
        'transcript_excerpt': '',
        'transcript_full': 'hello from transcript full',
      },
    );

    expect(summary, 'hello from transcript full');
  });

  test('attachment card summary prefers readable excerpt over transcript', () {
    final summary = extractAttachmentCardSummaryFromPayload(
      const <String, Object?>{
        'readable_text_excerpt': 'readable excerpt',
        'transcript_excerpt': 'transcript excerpt',
      },
    );

    expect(summary, 'readable excerpt');
  });

  test('attachment card summary prefers extracted excerpt over OCR excerpt',
      () {
    final summary = extractAttachmentCardSummaryFromPayload(
      const <String, Object?>{
        'extracted_text_excerpt': 'extracted excerpt',
        'ocr_text_excerpt': 'ocr excerpt',
      },
    );

    expect(summary, 'extracted excerpt');
  });

  test('attachment card summary prefers OCR when extracted looks degraded', () {
    final summary = extractAttachmentCardSummaryFromPayload(
      const <String, Object?>{
        'extracted_text_excerpt': 'A B C D E F G H I J K L M N O P',
        'ocr_text_excerpt': 'Invoice total is 123.45 USD.',
        'ocr_engine': 'apple_vision',
      },
    );

    expect(summary, 'Invoice total is 123.45 USD.');
  });

  test('attachment card marks queued auto OCR as in progress', () {
    final running = attachmentCardOcrInProgressFromPayload(
      const <String, Object?>{
        'ocr_auto_status': 'queued',
      },
    );

    expect(running, isTrue);
  });

  test('attachment card marks needs_ocr with no OCR text as in progress', () {
    final running = attachmentCardOcrInProgressFromPayload(
      const <String, Object?>{
        'needs_ocr': true,
      },
    );

    expect(running, isTrue);
  });

  test('attachment card marks needs_ocr false as not in progress', () {
    final running = attachmentCardOcrInProgressFromPayload(
      const <String, Object?>{
        'needs_ocr': false,
      },
    );

    expect(running, isFalse);
  });
}
