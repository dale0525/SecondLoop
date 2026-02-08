import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PlatformPdfOcr parses desktop runtime pdf payload', () async {
    final result = await PlatformPdfOcr.tryOcrPdfBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      maxPages: 200,
      dpi: 180,
      languageHints: 'device_plus_en',
      ocrPdfInvoke: (bytes,
          {required maxPages, required dpi, required languageHints}) async {
        expect(maxPages, 200);
        expect(dpi, 180);
        expect(languageHints, 'device_plus_en');
        expect(bytes, isA<Uint8List>());
        return <String, Object?>{
          'ocr_text_full': '[page 1]\nhello\n\n[page 2]\nworld',
          'ocr_text_excerpt': '[page 1]\nhello',
          'ocr_engine': 'desktop_rust_pdf_text',
          'ocr_is_truncated': false,
          'ocr_page_count': 2,
          'ocr_processed_pages': 2,
        };
      },
    );

    expect(result, isNotNull);
    expect(result!.engine, 'desktop_rust_pdf_text');
    expect(result.pageCount, 2);
    expect(result.processedPages, 2);
    expect(result.excerpt, 'hello');
    expect(result.fullText, 'hello\nworld');
    expect(result.retryAttempted, isFalse);
    expect(result.retryAttempts, 0);
    expect(result.retryHintsTried, isEmpty);
  });

  test('PlatformPdfOcr parses desktop runtime image payload', () async {
    final result = await PlatformPdfOcr.tryOcrImageBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      languageHints: 'device_plus_en',
      ocrImageInvoke: (bytes, {required languageHints}) async {
        expect(languageHints, 'device_plus_en');
        return <String, Object?>{
          'ocr_text_full': 'hello image',
          'ocr_text_excerpt': 'hello image',
          'ocr_engine': 'desktop_rust_image_noop',
          'ocr_is_truncated': false,
          'ocr_page_count': 1,
          'ocr_processed_pages': 1,
        };
      },
    );

    expect(result, isNotNull);
    expect(result!.engine, 'desktop_rust_image_noop');
    expect(result.pageCount, 1);
    expect(result.processedPages, 1);
    expect(result.excerpt, 'hello image');
  });

  test('PlatformPdfOcr returns null on malformed payload', () async {
    final result = await PlatformPdfOcr.tryOcrPdfBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      maxPages: 10,
      dpi: 120,
      languageHints: 'device_plus_en',
      ocrPdfInvoke: (bytes,
              {required maxPages,
              required dpi,
              required languageHints}) async =>
          <String, Object?>{
        'ocr_text_full': 'x',
        'ocr_engine': '',
        'ocr_page_count': 0,
        'ocr_processed_pages': 0,
      },
    );
    expect(result, isNull);
  });

  test('PlatformPdfOcr returns null when runtime invocation throws', () async {
    final result = await PlatformPdfOcr.tryOcrPdfBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      maxPages: 10,
      dpi: 120,
      languageHints: 'device_plus_en',
      ocrPdfInvoke: (bytes,
          {required maxPages, required dpi, required languageHints}) {
        throw StateError('runtime_error');
      },
    );
    expect(result, isNull);
  });
}
