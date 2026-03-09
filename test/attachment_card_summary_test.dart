import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/attachment_card.dart';

void main() {
  test('attachment card fallback shows failed label for failed annotation job',
      () {
    final subtitle = resolveAttachmentCardFallbackSubtitle(
      ocrRunning: false,
      jobStatus: 'failed',
      preparingText: 'Preparing...',
      ocrRunningText: 'OCR running...',
      failedText: 'Failed',
      canceledText: 'Canceled',
    );

    expect(subtitle, 'Failed');
  });

  test('attachment card fallback keeps preparing for pending annotation job',
      () {
    final subtitle = resolveAttachmentCardFallbackSubtitle(
      ocrRunning: false,
      jobStatus: 'pending',
      preparingText: 'Preparing...',
      ocrRunningText: 'OCR running...',
      failedText: 'Failed',
      canceledText: 'Canceled',
    );

    expect(subtitle, 'Preparing...');
  });

  test('attachment card fallback keeps OCR running text when OCR is active',
      () {
    final subtitle = resolveAttachmentCardFallbackSubtitle(
      ocrRunning: true,
      jobStatus: null,
      preparingText: 'Preparing...',
      ocrRunningText: 'OCR running...',
      failedText: 'Failed',
      canceledText: 'Canceled',
    );

    expect(subtitle, 'OCR running...');
  });

  test('attachment card fallback shows failed when auto OCR failed', () {
    final subtitle = resolveAttachmentCardFallbackSubtitle(
      ocrRunning: false,
      jobStatus: null,
      preparingText: 'Preparing...',
      ocrRunningText: 'OCR running...',
      failedText: 'Failed',
      canceledText: 'Canceled',
      autoOcrStatus: 'failed',
    );

    expect(subtitle, 'Failed');
  });

  test('attachment card fallback shows canceled label for canceled job', () {
    final subtitle = resolveAttachmentCardFallbackSubtitle(
      ocrRunning: false,
      jobStatus: 'canceled',
      preparingText: 'Preparing...',
      ocrRunningText: 'OCR running...',
      failedText: 'Failed',
      canceledText: 'Canceled',
    );

    expect(subtitle, 'Canceled');
  });

  test(
      'attachment card fallback does not keep preparing after OCR completed with no text',
      () {
    final subtitle = resolveAttachmentCardFallbackSubtitle(
      ocrRunning: false,
      jobStatus: null,
      preparingText: 'Preparing...',
      ocrRunningText: 'OCR running...',
      failedText: 'Failed',
      canceledText: 'Canceled',
      autoOcrStatus: 'ok',
      hasAnnotationPayload: true,
      completedText: 'Preview unavailable',
    );

    expect(subtitle, 'Preview unavailable');
  });

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

  test('attachment card summary prefers audio turn excerpt over raw transcript',
      () {
    final summary = extractAttachmentCardSummaryFromPayload(
      const <String, Object?>{
        'transcript_excerpt': 'raw transcript excerpt',
        'transcript_full': 'raw transcript full',
        'transcript_turns_v1': {
          'builder_version': 'turns_v1',
          'status': 'ok',
          'turns': [
            {
              'start_ms': 12000,
              'end_ms': 18000,
              'text': 'Hello everyone.',
              'segment_count': 1,
              'source_segment_start_index': 0,
              'source_segment_end_index': 0,
            },
          ],
        },
      },
      mimeTypeHint: 'audio/mp4',
    );

    expect(summary, '[00:12–00:18] Hello everyone.');
  });

  test('attachment card summary falls back to payload mime when hint is empty',
      () {
    final summary = extractAttachmentCardSummaryFromPayload(
      const <String, Object?>{
        'mime_type': 'audio/mp4',
        'transcript_excerpt': 'raw transcript excerpt',
        'transcript_full': 'raw transcript full',
        'transcript_turns_v1': {
          'builder_version': 'turns_v1',
          'status': 'ok',
          'turns': [
            {
              'start_ms': 12000,
              'end_ms': 18000,
              'text': 'Hello everyone.',
              'segment_count': 1,
              'source_segment_start_index': 0,
              'source_segment_end_index': 0,
            },
          ],
        },
      },
      mimeTypeHint: '',
    );

    expect(summary, '[00:12–00:18] Hello everyone.');
  });

  test(
      'attachment card summary keeps audio turn excerpt ahead of readable text',
      () {
    final summary = extractAttachmentCardSummaryFromPayload(
      const <String, Object?>{
        'mime_type': 'audio/mp4',
        'readable_text_excerpt': 'readable excerpt',
        'transcript_excerpt': 'raw transcript excerpt',
        'transcript_turns_v1': {
          'builder_version': 'turns_v1',
          'status': 'ok',
          'turns': [
            {
              'start_ms': 12000,
              'end_ms': 18000,
              'text': 'Hello everyone.',
              'segment_count': 1,
              'source_segment_start_index': 0,
              'source_segment_end_index': 0,
            },
          ],
        },
      },
      mimeTypeHint: 'audio/mp4',
    );

    expect(summary, '[00:12–00:18] Hello everyone.');
  });

  test('attachment card summary ignores turn excerpt for non-audio mime', () {
    final summary = extractAttachmentCardSummaryFromPayload(
      const <String, Object?>{
        'transcript_excerpt': 'raw transcript excerpt',
        'transcript_full': 'raw transcript full',
        'transcript_turns_v1': {
          'builder_version': 'turns_v1',
          'status': 'ok',
          'turns': [
            {
              'start_ms': 12000,
              'end_ms': 18000,
              'text': 'Hello everyone.',
              'segment_count': 1,
              'source_segment_start_index': 0,
              'source_segment_end_index': 0,
            },
          ],
        },
      },
      mimeTypeHint: 'video/mp4',
    );

    expect(summary, 'raw transcript excerpt');
  });

  test('attachment card summary prefers readable excerpt over transcript', () {
    final summary = extractAttachmentCardSummaryFromPayload(
      const <String, Object?>{
        'llm_summary': 'Cloud summary',
        'readable_text_excerpt': 'readable excerpt',
        'transcript_excerpt': 'transcript excerpt',
      },
    );

    expect(summary, 'Cloud summary');
  });

  test('attachment card summary falls back to readable excerpt', () {
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

  test('attachment card summary supports legacy ocr_text payload', () {
    final summary = extractAttachmentCardSummaryFromPayload(
      const <String, Object?>{
        'ocr_text': 'Legacy OCR summary text',
      },
    );

    expect(summary, 'Legacy OCR summary text');
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
