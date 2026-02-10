import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';
import 'package:secondloop/features/media_enrichment/media_enrichment_runner.dart';
import 'package:secondloop/features/media_enrichment/ocr_fallback_media_annotation_client.dart';

final class _PrimaryClient implements MediaEnrichmentClient {
  @override
  final String annotationModelName = 'byok-model';

  String? annotateResponse;
  Object? annotateError;
  int annotateCalls = 0;

  @override
  Future<String> annotateImage({
    required String lang,
    required String mimeType,
    required Uint8List imageBytes,
  }) async {
    annotateCalls += 1;
    final error = annotateError;
    if (error != null) throw error;
    return annotateResponse ?? '{"caption_long":"primary"}';
  }

  @override
  Future<String> reverseGeocode({
    required double lat,
    required double lon,
    required String lang,
  }) async {
    throw StateError('not_used_in_tests');
  }
}

void main() {
  test('returns primary payload when it is usable', () async {
    final primary = _PrimaryClient()
      ..annotateResponse = '{"caption_long":"a cat"}';
    var ocrCalls = 0;

    final client = OcrFallbackMediaAnnotationClient(
      primaryClient: primary,
      languageHints: 'device_plus_en',
      tryOcrImage: (bytes, {required languageHints}) async {
        ocrCalls += 1;
        return const PlatformPdfOcrResult(
          fullText: 'ocr text',
          excerpt: 'ocr text',
          engine: 'desktop_rust_image_onnx',
          isTruncated: false,
          pageCount: 1,
          processedPages: 1,
        );
      },
    );

    final payload = await client.annotateImage(
      lang: 'en',
      mimeType: 'image/png',
      imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
    );

    expect(payload, contains('a cat'));
    expect(ocrCalls, 0);
    expect(primary.annotateCalls, 1);
  });

  test('falls back to OCR when primary client throws', () async {
    final primary = _PrimaryClient()
      ..annotateError = StateError('model_unavailable');
    var ocrCalls = 0;

    final client = OcrFallbackMediaAnnotationClient(
      primaryClient: primary,
      languageHints: 'zh_en',
      tryOcrImage: (bytes, {required languageHints}) async {
        ocrCalls += 1;
        expect(languageHints, 'zh_en');
        return const PlatformPdfOcrResult(
          fullText: '这是一次图片OCR兜底识别结果，包含足够多的文字。',
          excerpt: '这是一次图片OCR兜底识别结果',
          engine: 'desktop_rust_image_onnx',
          isTruncated: false,
          pageCount: 1,
          processedPages: 1,
        );
      },
    );

    final payload = await client.annotateImage(
      lang: 'zh',
      mimeType: 'image/jpeg',
      imageBytes: Uint8List.fromList(<int>[9, 9, 9]),
    );

    expect(primary.annotateCalls, 1);
    expect(ocrCalls, 1);
    expect(payload, contains('ocr_text'));
    expect(payload, contains('caption_long'));
  });

  test('supports OCR-only mode when no primary model is configured', () async {
    final client = OcrFallbackMediaAnnotationClient(
      languageHints: 'device_plus_en',
      tryOcrImage: (bytes, {required languageHints}) async {
        return const PlatformPdfOcrResult(
          fullText:
              'This image contains enough OCR text signal to become a fallback caption.',
          excerpt: 'This image contains enough OCR text signal',
          engine: 'apple_vision',
          isTruncated: false,
          pageCount: 1,
          processedPages: 1,
        );
      },
    );

    final payload = await client.annotateImage(
      lang: 'en',
      mimeType: 'image/webp',
      imageBytes: Uint8List.fromList(<int>[4, 5, 6]),
    );

    expect(client.annotationModelName, 'ocr_fallback');
    expect(payload, contains('fallback caption'));
  });

  test('throws when OCR fallback text signal is too weak', () async {
    final client = OcrFallbackMediaAnnotationClient(
      languageHints: 'device_plus_en',
      minOcrTextScore: 20,
      tryOcrImage: (bytes, {required languageHints}) async {
        return const PlatformPdfOcrResult(
          fullText: 'ok',
          excerpt: 'ok',
          engine: 'apple_vision',
          isTruncated: false,
          pageCount: 1,
          processedPages: 1,
        );
      },
    );

    await expectLater(
      () => client.annotateImage(
        lang: 'en',
        mimeType: 'image/png',
        imageBytes: Uint8List.fromList(<int>[7, 8, 9]),
      ),
      throwsStateError,
    );
  });
}
