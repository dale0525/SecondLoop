import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    try {
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
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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
      'PlatformPdfOcr keeps desktop runtime result when runtime engine is present',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calledMethods = <String>[];
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calledMethods.add(call.method);
      if (call.method == 'rasterizePdfForOcr') {
        return null;
      }
      return <String, Object?>{
        'ocr_text_full': 'vision recovered text',
        'ocr_text_excerpt': 'vision recovered text',
        'ocr_engine': 'apple_vision',
        'ocr_is_truncated': false,
        'ocr_page_count': 3,
        'ocr_processed_pages': 3,
      };
    });

    try {
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
          'ocr_text_full': '',
          'ocr_text_excerpt': '',
          'ocr_engine': 'desktop_rust_pdf_image_decode_empty',
          'ocr_is_truncated': false,
          'ocr_page_count': 3,
          'ocr_processed_pages': 3,
        },
      );
      expect(result, isNotNull);
      expect(result!.fullText, '');
      expect(result.engine, 'desktop_rust_pdf_image_decode_empty');
      expect(calledMethods.contains('ocrPdf'), isFalse);
      expect(calledMethods.contains('ocrImage'), isFalse);
      expect(calledMethods.contains('rasterizePdfForOcr'), isTrue);
      expect(PlatformPdfOcr.lastErrorMessage, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    }
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

    try {
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
    } finally {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test(
      'PlatformPdfOcr retries runtime OCR with macOS rasterized PDF when image decode is empty',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'rasterizePdfForOcr') {
        return Uint8List.fromList(const <int>[9, 9, 9]);
      }
      fail('Unexpected native OCR method call: ${call.method}');
    });

    var invokeCount = 0;
    try {
      final result = await PlatformPdfOcr.tryOcrPdfBytes(
        Uint8List.fromList(const <int>[1, 2, 3]),
        maxPages: 10,
        dpi: 120,
        languageHints: 'device_plus_en',
        ocrPdfInvoke: (bytes,
            {required maxPages, required dpi, required languageHints}) async {
          invokeCount += 1;
          if (bytes.isNotEmpty && bytes.first == 9) {
            return <String, Object?>{
              'ocr_text_full': 'runtime recovered text',
              'ocr_text_excerpt': 'runtime recovered text',
              'ocr_engine': 'desktop_rust_pdf_onnx',
              'ocr_is_truncated': false,
              'ocr_page_count': 3,
              'ocr_processed_pages': 3,
            };
          }
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
      expect(invokeCount, 2);
      expect(result, isNotNull);
      expect(result!.fullText, 'runtime recovered text');
      expect(result.engine, 'desktop_rust_pdf_onnx');
      expect(PlatformPdfOcr.lastErrorMessage, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test(
      'PlatformPdfOcr rescues garbled runtime retry result with macOS vision OCR',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calledMethods = <String>[];
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calledMethods.add(call.method);
      if (call.method == 'rasterizePdfForOcr') {
        return Uint8List.fromList(const <int>[9, 9, 9]);
      }
      if (call.method == 'ocrPdf') {
        return <String, Object?>{
          'ocr_text_full': '精灵森友会CPI测试报告\n结论：不通过\n单价偏高，留存不够好因此不考虑合作\n'
              '测试版本：Android\n测试时间：2021/6/16-2021/6/19\n测试国家：UK\n'
              '地区 UK Impression 22089 Clicks 269 Installs 156 Cost \$500 CTR 1.22% CVR 57.99% CPI \$3.21',
          'ocr_text_excerpt': '精灵森友会CPI测试报告\n结论：不通过',
          'ocr_engine': 'apple_vision',
          'ocr_is_truncated': false,
          'ocr_page_count': 3,
          'ocr_processed_pages': 3,
        };
      }
      fail('Unexpected native OCR method call: ${call.method}');
    });

    const garbledRuntimeText = '''
23I
SE
J2e
2200
ISS0
S5080
Nee.re
noi2sqmI
萄冈
J2oJ
AITS
AVS
CI
MTO
CBC
2aloiID
2llstenl
XU：袁国
biotbnA：本刘发账
萌痂哟
息診对憾、
人。02.留日01.2留日ε001留，S.1
''';

    var invokeCount = 0;
    try {
      final result = await PlatformPdfOcr.tryOcrPdfBytes(
        Uint8List.fromList(const <int>[1, 2, 3]),
        maxPages: 10,
        dpi: 120,
        languageHints: 'device_plus_en',
        ocrPdfInvoke: (bytes,
            {required maxPages, required dpi, required languageHints}) async {
          invokeCount += 1;
          if (bytes.isNotEmpty && bytes.first == 9) {
            return <String, Object?>{
              'ocr_text_full': garbledRuntimeText,
              'ocr_text_excerpt': garbledRuntimeText,
              'ocr_engine': 'desktop_rust_pdf_onnx',
              'ocr_is_truncated': false,
              'ocr_page_count': 3,
              'ocr_processed_pages': 3,
            };
          }
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

      expect(invokeCount, 2);
      expect(result, isNotNull);
      expect(result!.engine, 'apple_vision');
      expect(result.fullText, contains('精灵森友会CPI测试报告'));
      expect(result.retryAttempted, isTrue);
      expect(result.retryAttempts, 2);
      expect(calledMethods.where((m) => m == 'rasterizePdfForOcr').length, 1);
      expect(calledMethods.where((m) => m == 'ocrPdf').length, 1);
      expect(PlatformPdfOcr.lastErrorMessage, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test(
      'PlatformPdfOcr falls back to windows native OCR when runtime is not initialized',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ocrPdf');
      return <String, Object?>{
        'ocr_text_full': 'windows recovered text',
        'ocr_text_excerpt': 'windows recovered text',
        'ocr_engine': 'windows_ocr',
        'ocr_is_truncated': false,
        'ocr_page_count': 3,
        'ocr_processed_pages': 3,
      };
    });

    try {
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
      expect(result!.fullText, 'windows recovered text');
      expect(result.engine, 'windows_ocr');
      expect(PlatformPdfOcr.lastErrorMessage, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test(
      'PlatformPdfOcr retries runtime OCR with windows rasterized PDF when image decode is empty',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'rasterizePdfForOcr') {
        return Uint8List.fromList(const <int>[9, 9, 9]);
      }
      fail('Unexpected native OCR method call: ${call.method}');
    });

    var invokeCount = 0;
    try {
      final result = await PlatformPdfOcr.tryOcrPdfBytes(
        Uint8List.fromList(const <int>[1, 2, 3]),
        maxPages: 10,
        dpi: 120,
        languageHints: 'device_plus_en',
        ocrPdfInvoke: (bytes,
            {required maxPages, required dpi, required languageHints}) async {
          invokeCount += 1;
          if (bytes.isNotEmpty && bytes.first == 9) {
            return <String, Object?>{
              'ocr_text_full': 'runtime recovered text',
              'ocr_text_excerpt': 'runtime recovered text',
              'ocr_engine': 'desktop_rust_pdf_onnx',
              'ocr_is_truncated': false,
              'ocr_page_count': 3,
              'ocr_processed_pages': 3,
            };
          }
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
      expect(invokeCount, 2);
      expect(result, isNotNull);
      expect(result!.fullText, 'runtime recovered text');
      expect(result.engine, 'desktop_rust_pdf_onnx');
      expect(PlatformPdfOcr.lastErrorMessage, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test('PlatformPdfOcr rescues garbled runtime retry result with windows OCR',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calledMethods = <String>[];
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calledMethods.add(call.method);
      if (call.method == 'rasterizePdfForOcr') {
        return Uint8List.fromList(const <int>[9, 9, 9]);
      }
      if (call.method == 'ocrPdf') {
        return <String, Object?>{
          'ocr_text_full':
              'Windows OCR recovered report summary with enough readable text '
                  'to beat runtime garbled output and keep downstream indexing stable.',
          'ocr_text_excerpt': 'Windows OCR recovered report summary',
          'ocr_engine': 'windows_ocr',
          'ocr_is_truncated': false,
          'ocr_page_count': 3,
          'ocr_processed_pages': 3,
        };
      }
      fail('Unexpected native OCR method call: ${call.method}');
    });

    const garbledRuntimeText = '''
23I
SE
J2e
2200
ISS0
S5080
Nee.re
noi2sqmI
萄冈
J2oJ
AITS
AVS
CI
MTO
CBC
2aloiID
2llstenl
XU：袁国
biotbnA：本刘发账
萌痂哟
息診对憾、
人。02.留日01.2留日ε001留，S.1
''';

    var invokeCount = 0;
    try {
      final result = await PlatformPdfOcr.tryOcrPdfBytes(
        Uint8List.fromList(const <int>[1, 2, 3]),
        maxPages: 10,
        dpi: 120,
        languageHints: 'device_plus_en',
        ocrPdfInvoke: (bytes,
            {required maxPages, required dpi, required languageHints}) async {
          invokeCount += 1;
          if (bytes.isNotEmpty && bytes.first == 9) {
            return <String, Object?>{
              'ocr_text_full': garbledRuntimeText,
              'ocr_text_excerpt': garbledRuntimeText,
              'ocr_engine': 'desktop_rust_pdf_onnx',
              'ocr_is_truncated': false,
              'ocr_page_count': 3,
              'ocr_processed_pages': 3,
            };
          }
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

      expect(invokeCount, 2);
      expect(result, isNotNull);
      expect(result!.engine, 'windows_ocr');
      expect(result.fullText, contains('Windows OCR recovered report summary'));
      expect(result.retryAttempted, isTrue);
      expect(result.retryAttempts, 2);
      expect(calledMethods.where((m) => m == 'rasterizePdfForOcr').length, 1);
      expect(calledMethods.where((m) => m == 'ocrPdf').length, 1);
      expect(PlatformPdfOcr.lastErrorMessage, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test(
      'PlatformPdfOcr falls back to android native OCR when runtime result is empty',
      () async {
    const channel = MethodChannel('secondloop/ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calledMethods = <String>[];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calledMethods.add(call.method);
      expect(call.method, 'ocrPdf');
      return <String, Object?>{
        'ocr_text_full': 'android mlkit recovered text',
        'ocr_text_excerpt': 'android mlkit recovered text',
        'ocr_engine': 'mlkit',
        'ocr_is_truncated': false,
        'ocr_page_count': 3,
        'ocr_processed_pages': 3,
      };
    });

    try {
      final result = await PlatformPdfOcr.tryOcrPdfBytes(
        Uint8List.fromList(const <int>[1, 2, 3]),
        maxPages: 10,
        dpi: 180,
        languageHints: 'device_plus_en',
        ocrPdfInvoke: (bytes,
                {required maxPages,
                required dpi,
                required languageHints}) async =>
            <String, Object?>{
          'ocr_text_full': '',
          'ocr_text_excerpt': '',
          'ocr_engine': 'desktop_rust_pdf_text',
          'ocr_is_truncated': false,
          'ocr_page_count': 3,
          'ocr_processed_pages': 3,
        },
      );
      expect(result, isNotNull);
      expect(result!.fullText, 'android mlkit recovered text');
      expect(result.engine, 'mlkit');
      expect(calledMethods, <String>['ocrPdf']);
      expect(PlatformPdfOcr.lastErrorMessage, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test(
      'PlatformPdfOcr retries runtime OCR with linux compression when image decode is empty',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    var invokeCount = 0;
    try {
      final result = await PlatformPdfOcr.tryOcrPdfBytes(
        Uint8List.fromList(const <int>[1, 2, 3]),
        maxPages: 10,
        dpi: 400,
        languageHints: 'device_plus_en',
        compressPdfInvoke: (bytes, {required scanDpi}) async {
          expect(scanDpi, 300);
          return Uint8List.fromList(const <int>[7, 7, 7]);
        },
        ocrPdfInvoke: (bytes,
            {required maxPages, required dpi, required languageHints}) async {
          invokeCount += 1;
          if (bytes.isNotEmpty && bytes.first == 7) {
            return <String, Object?>{
              'ocr_text_full': 'linux runtime recovered text',
              'ocr_text_excerpt': 'linux runtime recovered text',
              'ocr_engine': 'desktop_rust_pdf_onnx',
              'ocr_is_truncated': false,
              'ocr_page_count': 3,
              'ocr_processed_pages': 3,
            };
          }
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
      expect(invokeCount, 2);
      expect(result, isNotNull);
      expect(result!.engine, 'desktop_rust_pdf_onnx');
      expect(result.fullText, 'linux runtime recovered text');
      expect(PlatformPdfOcr.lastErrorMessage, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
