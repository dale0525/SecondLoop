import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/content_enrichment/ocr_text_quality.dart';

void main() {
  test('estimateOcrEffectiveTextScore handles latin and CJK text', () {
    final latin = estimateOcrEffectiveTextScore(
      'This is an OCR fallback sample text for invoice line items.',
    );
    final cjk = estimateOcrEffectiveTextScore('这是一次图片OCR兜底结果，用于测试有效字数阈值。');

    expect(latin, greaterThan(10));
    expect(cjk, greaterThan(10));
  });

  test('hasSufficientOcrTextSignal ignores very short snippets', () {
    expect(hasSufficientOcrTextSignal('Hi'), isFalse);
    expect(hasSufficientOcrTextSignal('你好'), isFalse);
    expect(
      hasSufficientOcrTextSignal('识别结果包含了足够多的文字信息，可作为图片注释。'),
      isTrue,
    );
  });

  test('shouldPreferExtractedTextOverOcr favors cleaner extracted text', () {
    const extracted =
        'Quarterly report total revenue grew 32 percent year over year.';
    const degradedOcr = 'Q u a r t e r l y r e p o r t t o t a l r e v e n u e';

    expect(
      shouldPreferExtractedTextOverOcr(
        extractedText: extracted,
        ocrText: degradedOcr,
      ),
      isTrue,
    );
  });
}
