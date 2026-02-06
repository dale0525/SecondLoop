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
}
