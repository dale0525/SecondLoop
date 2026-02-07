import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';

void main() {
  const channel = MethodChannel('secondloop/ocr');
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('PlatformPdfOcr parses native payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ocrPdf');
      final args = (call.arguments as Map).cast<String, Object?>();
      expect(args['max_pages'], 200);
      expect(args['dpi'], 180);
      expect(args['language_hints'], 'device_plus_en');
      expect(args['bytes'], isA<Uint8List>());
      return jsonEncode(<String, Object?>{
        'ocr_text_full': '[page 1]\nhello\n\n[page 2]\nworld',
        'ocr_text_excerpt': '[page 1]\nhello',
        'ocr_engine': 'apple_vision',
        'ocr_is_truncated': false,
        'ocr_page_count': 1,
        'ocr_processed_pages': 1,
      });
    });

    final result = await PlatformPdfOcr.tryOcrPdfBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      maxPages: 200,
      dpi: 180,
      languageHints: 'device_plus_en',
    );

    expect(result, isNotNull);
    expect(result!.engine, 'apple_vision');
    expect(result.pageCount, 1);
    expect(result.processedPages, 1);
    expect(result.excerpt, 'hello');
    expect(result.fullText, 'hello\nworld');
    expect(result.retryAttempted, isFalse);
    expect(result.retryAttempts, 0);
    expect(result.retryHintsTried, isEmpty);
  });

  test('PlatformPdfOcr retries degraded OCR payload with higher DPI', () async {
    var callCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ocrPdf');
      callCount += 1;
      final args = (call.arguments as Map).cast<String, Object?>();
      if (callCount == 1) {
        expect(args['dpi'], 180);
        expect(args['language_hints'], 'device_plus_en');
        return jsonEncode(<String, Object?>{
          'ocr_text_full': '[page 1]\nA B C D E F G H I J K L M N O P',
          'ocr_text_excerpt': '[page 1]\nA B C D E F G H I J K L M N O P',
          'ocr_engine': 'apple_vision',
          'ocr_is_truncated': false,
          'ocr_page_count': 1,
          'ocr_processed_pages': 1,
        });
      }
      expect(args['dpi'], 360);
      expect(args['language_hints'], 'device_plus_en');
      return jsonEncode(<String, Object?>{
        'ocr_text_full': '[page 1]\nInvoice total is 123.45 USD.',
        'ocr_text_excerpt': '[page 1]\nInvoice total is 123.45 USD.',
        'ocr_engine': 'apple_vision',
        'ocr_is_truncated': false,
        'ocr_page_count': 1,
        'ocr_processed_pages': 1,
      });
    });

    final result = await PlatformPdfOcr.tryOcrPdfBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      maxPages: 200,
      dpi: 180,
      languageHints: 'device_plus_en',
    );

    expect(result, isNotNull);
    expect(callCount, 2);
    expect(result!.engine, 'apple_vision+dpi360');
    expect(result.excerpt, 'Invoice total is 123.45 USD.');
    expect(result.retryAttempted, isTrue);
    expect(result.retryAttempts, 1);
    expect(result.retryHintsTried, <String>['device_plus_en']);
  });

  test('PlatformPdfOcr retries with zh_en for CJK-heavy auto hints', () async {
    var callCount = 0;
    final seenHints = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ocrPdf');
      callCount += 1;
      final args = (call.arguments as Map).cast<String, Object?>();
      final hint = (args['language_hints'] ?? '').toString();
      seenHints.add(hint);
      if (callCount == 1) {
        expect(hint, 'device_plus_en');
        expect(args['dpi'], 180);
      } else {
        expect(args['dpi'], 360);
      }
      if (hint == 'zh_en') {
        return jsonEncode(<String, Object?>{
          'ocr_text_full': '[page 1]\n这是扫描件 OCR 的中文结果，文本明显更可读且语义完整。',
          'ocr_text_excerpt': '[page 1]\n这是扫描件 OCR 的中文结果，文本明显更可读且语义完整。',
          'ocr_engine': 'apple_vision',
          'ocr_is_truncated': false,
          'ocr_page_count': 1,
          'ocr_processed_pages': 1,
        });
      }
      return jsonEncode(<String, Object?>{
        'ocr_text_full':
            '[page 1]\n崠辣墅\n感焚育春眚\n唦部育春青\n最目\n2TM\n3TMO\nSO\n公青\n戴姑突',
        'ocr_text_excerpt':
            '[page 1]\n崠辣墅\n感焚育春眚\n唦部育春青\n最目\n2TM\n3TMO\nSO\n公青\n戴姑突',
        'ocr_engine': 'apple_vision',
        'ocr_is_truncated': false,
        'ocr_page_count': 1,
        'ocr_processed_pages': 1,
      });
    });

    final result = await PlatformPdfOcr.tryOcrPdfBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      maxPages: 200,
      dpi: 180,
      languageHints: 'device_plus_en',
    );

    expect(result, isNotNull);
    expect(callCount, 3);
    expect(
      seenHints,
      <String>['device_plus_en', 'device_plus_en', 'zh_en'],
    );
    expect(result!.engine, 'apple_vision+dpi360+zh_en');
    expect(result.excerpt, '这是扫描件 OCR 的中文结果，文本明显更可读且语义完整。');
    expect(result.retryAttempted, isTrue);
    expect(result.retryAttempts, 2);
    expect(
      result.retryHintsTried,
      <String>['device_plus_en', 'zh_en'],
    );
  });

  test('PlatformPdfOcr retries with en for latin-heavy auto hints', () async {
    var callCount = 0;
    final seenHints = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ocrPdf');
      callCount += 1;
      final args = (call.arguments as Map).cast<String, Object?>();
      final hint = (args['language_hints'] ?? '').toString();
      seenHints.add(hint);
      if (callCount == 1) {
        expect(hint, 'device_plus_en');
        expect(args['dpi'], 180);
      } else {
        expect(args['dpi'], 360);
      }
      if (hint == 'en') {
        return jsonEncode(<String, Object?>{
          'ocr_text_full':
              '[page 1]\nInvoice total is 123.45 USD and payment due date is 2026-02-07.',
          'ocr_text_excerpt':
              '[page 1]\nInvoice total is 123.45 USD and payment due date is 2026-02-07.',
          'ocr_engine': 'apple_vision',
          'ocr_is_truncated': false,
          'ocr_page_count': 1,
          'ocr_processed_pages': 1,
        });
      }
      return jsonEncode(<String, Object?>{
        'ocr_text_full': '[page 1]\nA B C D E F G H I J K L M N O P',
        'ocr_text_excerpt': '[page 1]\nA B C D E F G H I J K L M N O P',
        'ocr_engine': 'apple_vision',
        'ocr_is_truncated': false,
        'ocr_page_count': 1,
        'ocr_processed_pages': 1,
      });
    });

    final result = await PlatformPdfOcr.tryOcrPdfBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      maxPages: 200,
      dpi: 180,
      languageHints: 'device_plus_en',
    );

    expect(result, isNotNull);
    expect(callCount, 3);
    expect(
      seenHints,
      <String>['device_plus_en', 'device_plus_en', 'en'],
    );
    expect(result!.engine, 'apple_vision+dpi360+en');
    expect(
      result.excerpt,
      'Invoice total is 123.45 USD and payment due date is 2026-02-07.',
    );
    expect(result.retryAttempted, isTrue);
    expect(result.retryAttempts, 2);
    expect(
      result.retryHintsTried,
      <String>['device_plus_en', 'en'],
    );
  });

  test('PlatformPdfOcr returns null on malformed payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'ocr_text_full': 'x',
        'ocr_engine': '',
        'ocr_page_count': 0,
        'ocr_processed_pages': 0,
      };
    });

    final result = await PlatformPdfOcr.tryOcrPdfBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      maxPages: 10,
      dpi: 120,
      languageHints: 'device_plus_en',
    );
    expect(result, isNull);
  });

  test('PlatformPdfOcr parses native image OCR payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ocrImage');
      final args = (call.arguments as Map).cast<String, Object?>();
      expect(args['language_hints'], 'device_plus_en');
      expect(args['bytes'], isA<Uint8List>());
      return jsonEncode(<String, Object?>{
        'ocr_text_full': 'hello image',
        'ocr_text_excerpt': 'hello image',
        'ocr_engine': 'apple_vision',
        'ocr_is_truncated': false,
        'ocr_page_count': 1,
        'ocr_processed_pages': 1,
      });
    });

    final result = await PlatformPdfOcr.tryOcrImageBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      languageHints: 'device_plus_en',
    );

    expect(result, isNotNull);
    expect(result!.engine, 'apple_vision');
    expect(result.pageCount, 1);
    expect(result.processedPages, 1);
    expect(result.excerpt, 'hello image');
    expect(result.retryAttempted, isFalse);
    expect(result.retryAttempts, 0);
    expect(result.retryHintsTried, isEmpty);
  });

  test('PlatformPdfOcr image OCR returns null on malformed payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'ocr_text_full': 'x',
        'ocr_engine': '',
        'ocr_page_count': 0,
        'ocr_processed_pages': 0,
      };
    });

    final result = await PlatformPdfOcr.tryOcrImageBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      languageHints: 'device_plus_en',
    );
    expect(result, isNull);
  });
}
