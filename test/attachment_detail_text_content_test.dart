import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/attachment_detail_text_content.dart';

void main() {
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
}
