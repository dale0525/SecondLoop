import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/content_enrichment/ocr_result_preference.dart';
import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';

void main() {
  test(
      'maybePreferExtractedTextForRuntimeOcr prefers extracted text on runtime OCR',
      () {
    const runtime = PlatformPdfOcrResult(
      fullText: 'Q u a r t e r l y r e p o r t t o t a l r e v e n u e',
      excerpt: 'Q u a r t e r l y r e p o r t',
      engine: 'desktop_rust_pdf_onnx',
      isTruncated: false,
      pageCount: 2,
      processedPages: 2,
    );

    final preferred = maybePreferExtractedTextForRuntimeOcr(
      ocr: runtime,
      extractedFull:
          'Quarterly report total revenue grew 32 percent year over year.',
      extractedExcerpt: 'Quarterly report total revenue grew 32 percent',
    );

    expect(preferred.fullText, contains('Quarterly report total revenue'));
    expect(preferred.excerpt, contains('32 percent'));
    expect(preferred.engine, 'desktop_rust_pdf_onnx+prefer_extracted');
  });

  test('maybePreferExtractedTextForRuntimeOcr keeps non-runtime OCR untouched',
      () {
    const nonRuntime = PlatformPdfOcrResult(
      fullText: 'runtime independent ocr text',
      excerpt: 'runtime independent',
      engine: 'apple_vision',
      isTruncated: false,
      pageCount: 1,
      processedPages: 1,
    );

    final result = maybePreferExtractedTextForRuntimeOcr(
      ocr: nonRuntime,
      extractedFull: 'a clearly better extracted sentence',
      extractedExcerpt: 'a clearly better extracted sentence',
    );

    expect(identical(result, nonRuntime), isTrue);
    expect(result.engine, 'apple_vision');
  });

  test(
      'maybePreferExtractedTextForRuntimeOcr keeps OCR when extracted is weaker',
      () {
    const runtime = PlatformPdfOcrResult(
      fullText: 'comprehensive OCR text with enough details and structure',
      excerpt: 'comprehensive OCR text',
      engine: 'desktop_rust_pdf_onnx',
      isTruncated: false,
      pageCount: 1,
      processedPages: 1,
    );

    final result = maybePreferExtractedTextForRuntimeOcr(
      ocr: runtime,
      extractedFull: 'bad',
      extractedExcerpt: '',
    );

    expect(identical(result, runtime), isTrue);
    expect(result.engine, 'desktop_rust_pdf_onnx');
  });

  test('buildOcrExcerptFromText trims long text with ellipsis', () {
    final source = 'a' * 1300;
    final excerpt = buildOcrExcerptFromText(source, maxChars: 1200);

    expect(excerpt.length, lessThanOrEqualTo(1201));
    expect(excerpt.endsWith('…'), isTrue);
  });

  test('isRuntimeOcrEngine recognizes desktop rust engines', () {
    expect(isRuntimeOcrEngine('desktop_rust_pdf_onnx'), isTrue);
    expect(isRuntimeOcrEngine('apple_vision'), isFalse);
  });
}
