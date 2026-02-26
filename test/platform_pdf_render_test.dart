import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final messenger = TestDefaultBinaryMessengerBinding.instance;
    messenger.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('secondloop/ocr'), null);
  });

  test('PlatformPdfRender forwards page window arguments to native channel',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'renderPdfToLongImage');
      final args = Map<String, Object?>.from(call.arguments as Map);
      expect(args['ocr_model_preset'], kCommonPdfOcrModelPreset);
      expect(args['max_pages'], 10);
      expect(args['dpi'], 180);
      expect(args['start_page'], 11);
      return <String, Object?>{
        'image_bytes': Uint8List.fromList(const <int>[1, 2, 3]),
        'image_mime_type': 'image/jpeg',
        'page_count': 25,
        'processed_pages': 10,
      };
    });

    final result = await PlatformPdfRender.tryRenderPdfToLongImage(
      Uint8List.fromList(const <int>[8, 9, 10]),
      preset: const PlatformPdfRenderPreset(
        id: kCommonPdfOcrModelPreset,
        maxPages: 10,
        dpi: 180,
        startPage: 11,
      ),
    );

    expect(result, isNotNull);
    expect(result!.pageCount, 25);
    expect(result.processedPages, 10);
  });

  test('PlatformPdfRender forwards page window arguments to runtime fallback',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    final result = await PlatformPdfRender.tryRenderPdfToLongImage(
      Uint8List.fromList(const <int>[1, 2, 3]),
      preset: const PlatformPdfRenderPreset(
        id: kCommonPdfOcrModelPreset,
        maxPages: 5,
        dpi: 200,
        startPage: 21,
      ),
      nativeRenderInvoke:
          (bytes, {required PlatformPdfRenderPreset preset}) async => null,
      runtimeRenderInvoke: (bytes,
          {required maxPages,
          required dpi,
          required languageHints,
          required startPage}) async {
        expect(maxPages, 5);
        expect(dpi, 200);
        expect(languageHints, kDesktopRuntimeRenderLongImageHint);
        expect(startPage, 21);
        return <String, Object?>{
          'ocr_text_full': 'AQID',
          'ocr_text_excerpt': '',
          'ocr_engine': 'desktop_rust_pdf_render_jpeg',
          'ocr_is_truncated': false,
          'ocr_page_count': 25,
          'ocr_processed_pages': 5,
        };
      },
    );

    expect(result, isNotNull);
    expect(result!.pageCount, 25);
    expect(result.processedPages, 5);
    expect(result.imageBytes, Uint8List.fromList(const <int>[1, 2, 3]));
  });
}
