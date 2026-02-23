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
    expect(PlatformPdfOcr.lastErrorMessage, isNull);
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
    expect(PlatformPdfOcr.lastErrorMessage, isNull);
  });

  test(
      'PlatformPdfOcr falls back to windows native OCR when runtime reports unsupported image bytes',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var nativeCalled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalled = true;
      expect(call.method, 'ocrImage');
      return <String, Object?>{
        'ocr_text_full': 'windows recovered text',
        'ocr_text_excerpt': 'windows recovered text',
        'ocr_engine': 'windows_ocr',
        'ocr_is_truncated': false,
        'ocr_page_count': 1,
        'ocr_processed_pages': 1,
      };
    });

    final result = await PlatformPdfOcr.tryOcrImageBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      languageHints: 'device_plus_en',
      ocrImageInvoke: (bytes, {required languageHints}) {
        throw StateError(
            'AnyhowException(invalid image bytes: The image format could not be determined)');
      },
    );

    expect(result, isNotNull);
    expect(result!.fullText, 'windows recovered text');
    expect(result.engine, 'windows_ocr');
    expect(nativeCalled, isTrue);
    expect(PlatformPdfOcr.lastErrorMessage, isNull);
  });

  test(
      'PlatformPdfOcr falls back to mobile native OCR when runtime returns unsupported empty image payload',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var nativeCalled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalled = true;
      expect(call.method, 'ocrImage');
      return <String, Object?>{
        'ocr_text_full': 'android recovered text',
        'ocr_text_excerpt': 'android recovered text',
        'ocr_engine': 'android_mlkit',
        'ocr_is_truncated': false,
        'ocr_page_count': 1,
        'ocr_processed_pages': 1,
      };
    });

    final result = await PlatformPdfOcr.tryOcrImageBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      languageHints: 'device_plus_en',
      ocrImageInvoke: (bytes, {required languageHints}) async {
        expect(languageHints, 'device_plus_en');
        return <String, Object?>{
          'ocr_text_full': '',
          'ocr_text_excerpt': '',
          'ocr_engine': 'desktop_rust_image_unsupported',
          'ocr_is_truncated': false,
          'ocr_page_count': 1,
          'ocr_processed_pages': 1,
        };
      },
    );

    expect(result, isNotNull);
    expect(result!.fullText, 'android recovered text');
    expect(result.engine, 'android_mlkit');
    expect(nativeCalled, isTrue);
    expect(PlatformPdfOcr.lastErrorMessage, isNull);
  });

  test(
      'PlatformPdfOcr transcodes HEIF-like bytes then runs runtime OCR on windows',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var decodeCalled = false;
    var runtimeCalled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'decodeImageToJpeg') {
        decodeCalled = true;
        return <String, Object?>{
          'image_bytes':
              Uint8List.fromList(const <int>[0xFF, 0xD8, 0xFF, 0x00]),
          'image_mime_type': 'image/jpeg',
        };
      }
      fail('unexpected method: ${call.method}');
    });

    final result = await PlatformPdfOcr.tryOcrImageBytes(
      Uint8List.fromList(const <int>[
        0x00,
        0x00,
        0x00,
        0x18,
        0x66,
        0x74,
        0x79,
        0x70,
        0x68,
        0x65,
        0x69,
        0x63,
      ]),
      languageHints: 'device_plus_en',
      ocrImageInvoke: (bytes, {required languageHints}) async {
        runtimeCalled = true;
        expect(bytes, Uint8List.fromList(const <int>[0xFF, 0xD8, 0xFF, 0x00]));
        return <String, Object?>{
          'ocr_text_full': 'runtime heif text',
          'ocr_text_excerpt': 'runtime heif text',
          'ocr_engine': 'desktop_rust_image_noop',
          'ocr_is_truncated': false,
          'ocr_page_count': 1,
          'ocr_processed_pages': 1,
        };
      },
    );

    expect(result, isNotNull);
    expect(result!.fullText, 'runtime heif text');
    expect(result.engine, 'desktop_rust_image_noop');
    expect(decodeCalled, isTrue);
    expect(runtimeCalled, isTrue);
    expect(PlatformPdfOcr.lastErrorMessage, isNull);
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
    expect(PlatformPdfOcr.lastErrorMessage, 'ocr_payload_invalid_or_empty');
  });

  test('PlatformPdfOcr returns null when runtime invocation throws', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

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
    expect(PlatformPdfOcr.lastErrorMessage, contains('runtime_error'));
  });

  test('PlatformPdfOcr returns null on empty input', () async {
    final result = await PlatformPdfOcr.tryOcrPdfBytes(
      Uint8List(0),
      maxPages: 10,
      dpi: 120,
      languageHints: 'device_plus_en',
      ocrPdfInvoke: (bytes,
          {required maxPages, required dpi, required languageHints}) async {
        fail('OCR runtime should not be invoked when input is empty');
      },
    );
    expect(result, isNull);
    expect(PlatformPdfOcr.lastErrorMessage, 'ocr_input_unavailable');
  });

  test(
      'PlatformPdfOcr falls back to macOS native OCR when runtime is not initialized',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ocrPdf');
      return <String, Object?>{
        'ocr_text_full': 'vision recovered text',
        'ocr_text_excerpt': 'vision recovered text',
        'ocr_engine': 'apple_vision',
        'ocr_is_truncated': false,
        'ocr_page_count': 3,
        'ocr_processed_pages': 3,
      };
    });

    final result = await PlatformPdfOcr.tryOcrPdfBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      maxPages: 10,
      dpi: 120,
      languageHints: 'device_plus_en',
      ocrPdfInvoke: (bytes,
          {required maxPages, required dpi, required languageHints}) {
        throw StateError('runtime_not_initialized');
      },
    );
    expect(result, isNotNull);
    expect(result!.fullText, 'vision recovered text');
    expect(result.engine, 'apple_vision');
    expect(PlatformPdfOcr.lastErrorMessage, isNull);
  });

  test(
      'PlatformPdfOcr falls back to macOS native OCR when desktop runtime returns empty text',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    var nativeCalled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalled = true;
      expect(call.method, 'ocrPdf');
      return <String, Object?>{
        'ocr_text_full': 'native recovered text',
        'ocr_text_excerpt': 'native recovered text',
        'ocr_engine': 'apple_vision',
        'ocr_is_truncated': false,
        'ocr_page_count': 3,
        'ocr_processed_pages': 3,
      };
    });

    final result = await PlatformPdfOcr.tryOcrPdfBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      maxPages: 10,
      dpi: 120,
      languageHints: 'device_plus_en',
      ocrPdfInvoke: (bytes,
          {required maxPages, required dpi, required languageHints}) async {
        return <String, Object?>{
          'ocr_text_full': '',
          'ocr_text_excerpt': '',
          'ocr_engine': 'desktop_rust_pdf_image_decode_empty',
          'ocr_is_truncated': false,
          'ocr_page_count': 3,
          'ocr_processed_pages': 3,
        };
      },
    );

    expect(result, isNotNull);
    expect(result!.fullText, 'native recovered text');
    expect(result.engine, 'apple_vision');
    expect(nativeCalled, isTrue);
    expect(PlatformPdfOcr.lastErrorMessage, isNull);
  });

  test('PlatformPdfOcr keeps runtime result when runtime succeeds', () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    var nativeCalled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalled = true;
      return null;
    });

    final result = await PlatformPdfOcr.tryOcrPdfBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      maxPages: 10,
      dpi: 120,
      languageHints: 'device_plus_en',
      ocrPdfInvoke: (bytes,
          {required maxPages, required dpi, required languageHints}) async {
        return <String, Object?>{
          'ocr_text_full': 'runtime ok',
          'ocr_text_excerpt': 'runtime ok',
          'ocr_engine': 'desktop_rust_pdf_onnx',
          'ocr_is_truncated': false,
          'ocr_page_count': 1,
          'ocr_processed_pages': 1,
        };
      },
    );

    expect(result, isNotNull);
    expect(result!.fullText, 'runtime ok');
    expect(result.engine, 'desktop_rust_pdf_onnx');
    expect(nativeCalled, isFalse);
  });

  test(
      'PlatformPdfOcr keeps desktop runtime OCR even when text coverage is low',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    var nativeCalled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalled = true;
      expect(call.method, 'ocrPdf');
      return <String, Object?>{
        'ocr_text_full': 'native recovered rich text on all pages',
        'ocr_text_excerpt': 'native recovered rich text on all pages',
        'ocr_engine': 'apple_vision',
        'ocr_is_truncated': false,
        'ocr_page_count': 3,
        'ocr_processed_pages': 3,
      };
    });

    final result = await PlatformPdfOcr.tryOcrPdfBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      maxPages: 10,
      dpi: 120,
      languageHints: 'device_plus_en',
      ocrPdfInvoke: (bytes,
          {required maxPages, required dpi, required languageHints}) async {
        return <String, Object?>{
          'ocr_text_full': 'too short runtime text',
          'ocr_text_excerpt': 'too short runtime text',
          'ocr_engine': 'desktop_rust_pdf_onnx',
          'ocr_is_truncated': false,
          'ocr_page_count': 3,
          'ocr_processed_pages': 3,
        };
      },
    );

    expect(nativeCalled, isFalse);
    expect(result, isNotNull);
    expect(result!.engine, 'desktop_rust_pdf_onnx');
    expect(result.fullText, 'too short runtime text');
  });

  test('PlatformPdfOcr keeps single-page runtime OCR result on desktop',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    var nativeCalled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalled = true;
      return null;
    });

    final result = await PlatformPdfOcr.tryOcrPdfBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      maxPages: 10,
      dpi: 120,
      languageHints: 'device_plus_en',
      ocrPdfInvoke: (bytes,
          {required maxPages, required dpi, required languageHints}) async {
        return <String, Object?>{
          'ocr_text_full': 'short one-page runtime text',
          'ocr_text_excerpt': 'short one-page runtime text',
          'ocr_engine': 'desktop_rust_pdf_onnx',
          'ocr_is_truncated': false,
          'ocr_page_count': 1,
          'ocr_processed_pages': 1,
        };
      },
    );

    expect(result, isNotNull);
    expect(result!.engine, 'desktop_rust_pdf_onnx');
    expect(nativeCalled, isFalse);
  });

  test('PlatformPdfRender parses native rendered long image payload', () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'renderPdfToLongImage');
      return <String, Object?>{
        'image_bytes': Uint8List.fromList(const <int>[1, 2, 3, 4]),
        'image_mime_type': 'image/jpeg',
        'page_count': 5,
        'processed_pages': 4,
      };
    });

    final result = await PlatformPdfRender.tryRenderPdfToLongImage(
      Uint8List.fromList(const <int>[8, 9, 10]),
      preset: PlatformPdfRenderPreset.common,
    );

    expect(result, isNotNull);
    expect(result!.mimeType, 'image/jpeg');
    expect(result.pageCount, 5);
    expect(result.processedPages, 4);
    expect(result.imageBytes, Uint8List.fromList(const <int>[1, 2, 3, 4]));
  });

  test('PlatformPdfRender uses desktop runtime render path on linux', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    final result = await PlatformPdfRender.tryRenderPdfToLongImage(
      Uint8List.fromList(const <int>[1, 2, 3]),
      preset: PlatformPdfRenderPreset.common,
      nativeRenderInvoke:
          (bytes, {required PlatformPdfRenderPreset preset}) async => null,
      runtimeRenderInvoke: (bytes,
          {required maxPages, required dpi, required languageHints}) async {
        expect(languageHints, kDesktopRuntimeRenderLongImageHint);
        return <String, Object?>{
          'ocr_text_full': 'AQID',
          'ocr_text_excerpt': 'ignored',
          'ocr_engine': 'desktop_rust_pdf_render_jpeg',
          'ocr_is_truncated': false,
          'ocr_page_count': 3,
          'ocr_processed_pages': 2,
        };
      },
    );

    expect(result, isNotNull);
    expect(result!.mimeType, 'image/jpeg');
    expect(result.pageCount, 3);
    expect(result.processedPages, 2);
    expect(result.imageBytes, Uint8List.fromList(const <int>[1, 2, 3]));
  });
}
