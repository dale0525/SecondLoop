import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/attachment_detail_text_content.dart';

void main() {
  test('resolveAttachmentDetailTextContent prefers knowledge video fields', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'video_content_kind': 'knowledge',
        'video_summary': 'Lesson summary from classifier',
        'knowledge_markdown_excerpt': '## Key points',
        'knowledge_markdown_full': '## Key points\n1. OCR\n2. fallback',
        'readable_text_full': 'legacy readable text',
      },
    );

    expect(content.summary, 'Lesson summary from classifier');
    expect(content.full, '## Key points\n1. OCR\n2. fallback');
  });

  test('resolveAttachmentDetailTextContent prefers non-knowledge description',
      () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'video_content_kind': 'non_knowledge',
        'video_summary': 'Travel vlog summary',
        'video_description_excerpt': 'A calm beach sunset scene.',
        'video_description_full':
            'A calm beach sunset scene with walking and ambient sounds.',
      },
    );

    expect(content.summary, 'Travel vlog summary');
    expect(
      content.full,
      'A calm beach sunset scene with walking and ambient sounds.',
    );
  });

  test(
      'resolveAttachmentDetailTextContent uses transcript for vlog without OCR',
      () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'video_kind': 'vlog',
        'video_segment_count': 1,
        'video_summary': 'Travel vlog summary',
        'video_description_full': 'A calm beach sunset scene.',
        'transcript_full': 'Narrator talks about the trip.',
        'ocr_text_full': '',
        'ocr_text_excerpt': '',
      },
    );

    expect(content.summary, 'Travel vlog summary');
    expect(content.full, 'Narrator talks about the trip.');
  });
}
