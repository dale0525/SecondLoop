import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/content_enrichment/docx_ocr_policy.dart';
import 'package:secondloop/features/attachments/attachment_text_source_policy.dart';

void main() {
  test('selectAttachmentDisplayText removes OCR page headers', () {
    final selected = selectAttachmentDisplayText(
      const <String, Object?>{
        'ocr_text_excerpt': '[page 1]\nInvoice total 123.45',
        'ocr_text_full':
            '[page 1]\nInvoice total 123.45\n\n[page 2]\nThank you',
      },
    );

    expect(selected.excerpt, 'Invoice total 123.45');
    expect(selected.full, 'Invoice total 123.45\nThank you');
  });

  test('does not prefer OCR when both extracted and OCR look degraded', () {
    final selected = selectAttachmentDisplayText(
      const <String, Object?>{
        'extracted_text_excerpt': 'A B C D E F G H I J K L M N O P',
        'ocr_text_excerpt': 'Q R S T U V W X Y Z A B C D E F',
      },
    );

    expect(selected.excerpt, 'A B C D E F G H I J K L M N O P');
  });

  test('prefers OCR for degraded spaced CJK extracted text', () {
    final selected = selectAttachmentDisplayText(
      const <String, Object?>{
        'extracted_text_excerpt': '書 190 会丈森 女 不 公 合 不 因 不 留 高 单',
        'ocr_text_excerpt': '这是一个正常的中文句子用于测试 OCR 结果。',
      },
    );

    expect(selected.excerpt, '这是一个正常的中文句子用于测试 OCR 结果。');
  });

  test('docx keeps extracted text and OCR image text together', () {
    final selected = selectAttachmentDisplayText(
      const <String, Object?>{
        'mime_type': kDocxMimeType,
        'extracted_text_excerpt': 'Docx body paragraph.',
        'extracted_text_full': 'Docx body paragraph.\nSecond line.',
        'ocr_text_excerpt': 'Text inside image.',
        'ocr_text_full': 'Text inside image.\nImage footer.',
      },
    );

    expect(selected.excerpt, 'Docx body paragraph.\n\nText inside image.');
    expect(
      selected.full,
      'Docx body paragraph.\nSecond line.\n\nText inside image.\nImage footer.',
    );
  });

  test('falls back to legacy ocr_text key when ocr_text_full is absent', () {
    final selected = selectAttachmentDisplayText(
      const <String, Object?>{
        'ocr_text': '[page 1]\nLegacy OCR payload text',
      },
    );

    expect(selected.excerpt, 'Legacy OCR payload text');
    expect(selected.full, 'Legacy OCR payload text');
  });
}
