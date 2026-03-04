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

    expect(content.summary, '## Key points');
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

    expect(content.summary, 'A calm beach sunset scene.');
    expect(
      content.full,
      'A calm beach sunset scene with walking and ambient sounds.',
    );
  });

  test('resolveAttachmentDetailTextContent prefers extracted video detail', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'video_segment_count': 1,
        'video_summary': 'Travel vlog summary',
        'video_description_full': 'A calm beach sunset scene.',
        'transcript_full': 'Narrator talks about the trip.',
        'ocr_text_full': '',
        'ocr_text_excerpt': '',
      },
    );

    expect(content.summary, '');
    expect(content.full, 'A calm beach sunset scene.');
  });

  test('image detail full prefers summary over extracted metadata', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'image/jpeg',
        'summary': 'A cat is sleeping on the sofa.',
        'extracted_text_full': 'ISO 100\\nExposure 1/120\\nF2.8',
      },
    );

    expect(content.full, 'A cat is sleeping on the sofa.');
  });

  test('image detail full uses annotation caption before extracted metadata',
      () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'image/png',
        'extracted_text_full': 'Lens 35mm\\nCamera Model X',
      },
      annotationCaption: 'Sunset over the lake with orange reflections.',
    );

    expect(content.full, 'Sunset over the lake with orange reflections.');
  });

  test('image detail full keeps AI summary and OCR text together', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'image/png',
        'caption_long': 'AI: A white cat sleeping on a blue sofa.',
        'ocr_text_full': 'OCR: noon 12:30 · call mom',
      },
    );

    expect(
      content.full,
      'AI: A white cat sleeping on a blue sofa.\n\nOCR: noon 12:30 · call mom',
    );
  });

  test('mimeTypeOverride forces image merge when payload lacks mime_type', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'caption_long': 'AI says this is a calendar screenshot.',
        'ocr_text': 'OCR found: meeting with team at 14:00',
      },
      mimeTypeOverride: 'image/png',
    );

    expect(
      content.full,
      'AI says this is a calendar screenshot.\n\n'
      'OCR found: meeting with team at 14:00',
    );
  });

  test('non-image detail full keeps preferring extracted text', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'application/pdf',
        'summary': 'Document summary',
        'extracted_text_full': 'Document full text body',
      },
    );

    expect(content.full, 'Document full text body');
  });

  test('url detail summary prefers llm_summary when available', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'application/x.secondloop.url+json',
        'llm_summary': 'Cloud generated concise summary.',
        'readable_text_excerpt': 'Local extracted excerpt.',
        'readable_text_full': 'Local extracted full text.',
      },
    );

    expect(content.summary, 'Cloud generated concise summary.');
    expect(content.full, 'Cloud generated concise summary.');
  });

  test('url detail full falls back to local extracted text when no summary',
      () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'application/x.secondloop.url+json',
        'readable_text_excerpt': 'Local extracted excerpt.',
        'readable_text_full': 'Local extracted full text.',
      },
    );

    expect(content.summary, 'Local extracted excerpt.');
    expect(content.full, 'Local extracted full text.');
  });
}
