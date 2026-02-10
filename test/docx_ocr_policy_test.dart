import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/content_enrichment/docx_ocr_policy.dart';

void main() {
  test('shouldAttemptDocxOcr requires docx mime and unresolved OCR', () {
    final payload = <String, Object?>{
      'mime_type':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'ocr_engine': null,
    };

    expect(shouldAttemptDocxOcr(payload), isTrue);
  });

  test('shouldAttemptDocxOcr returns false when OCR already exists', () {
    final payload = <String, Object?>{
      'mime_type':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'ocr_engine': 'multimodal_byok_ocr_markdown:gpt-4.1-mini',
    };

    expect(shouldAttemptDocxOcr(payload), isFalse);
  });

  test('docxBytesFromArchiveExtract handles valid and invalid zip payload', () {
    final source = List<int>.generate(128, (i) => i % 251);
    final zipped = docxBytesToZipContainer(source);

    expect(zipped.isNotEmpty, isTrue);
    expect(docxBytesFromArchiveExtract(zipped), source);

    final plain = List<int>.generate(16, (i) => i);
    expect(docxBytesFromArchiveExtract(plain), isNull);
  });
}
