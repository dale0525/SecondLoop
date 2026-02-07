import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/media_backup/platform_pdf_compression.dart';

void main() {
  const channel = MethodChannel('secondloop/ocr');
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('compressPdfScanPagesViaPlatform passes bytes and dpi', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'compressPdf');
      final args = (call.arguments as Map).cast<String, Object?>();
      expect(args['scan_dpi'], 180);
      expect(args['bytes'], isA<Uint8List>());
      return Uint8List.fromList(const <int>[1, 2, 3]);
    });

    final result = await compressPdfScanPagesViaPlatform(
      Uint8List.fromList(const <int>[9, 8, 7]),
      scanDpi: 180,
    );
    expect(result, isNotNull);
    expect(result, Uint8List.fromList(const <int>[1, 2, 3]));
  });

  test('compressPdfScanPagesViaPlatform clamps dpi into 150..200', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map).cast<String, Object?>();
      expect(args['scan_dpi'], 150);
      return null;
    });

    final result = await compressPdfScanPagesViaPlatform(
      Uint8List.fromList(const <int>[1]),
      scanDpi: 10,
    );
    expect(result, isNull);
  });

  test('compressPdfScanPagesViaPlatform falls back when native returns null',
      () async {
    var fallbackCalls = 0;
    final result = await compressPdfScanPagesViaPlatform(
      Uint8List.fromList(const <int>[9, 8, 7]),
      scanDpi: 180,
      nativeInvoke: (method, arguments) async {
        expect(method, 'compressPdf');
        return null;
      },
      linuxFallbackCompressor: (bytes, {required scanDpi}) async {
        fallbackCalls += 1;
        expect(scanDpi, 180);
        return Uint8List.fromList(const <int>[4, 5, 6]);
      },
    );

    expect(fallbackCalls, 1);
    expect(result, Uint8List.fromList(const <int>[4, 5, 6]));
  });

  test('compressPdfScanPagesViaPlatform skips fallback when native succeeds',
      () async {
    var fallbackCalls = 0;
    final result = await compressPdfScanPagesViaPlatform(
      Uint8List.fromList(const <int>[1, 2, 3]),
      scanDpi: 200,
      nativeInvoke: (method, arguments) async {
        return Uint8List.fromList(const <int>[7, 7, 7]);
      },
      linuxFallbackCompressor: (bytes, {required scanDpi}) async {
        fallbackCalls += 1;
        return Uint8List.fromList(const <int>[8, 8, 8]);
      },
    );

    expect(fallbackCalls, 0);
    expect(result, Uint8List.fromList(const <int>[7, 7, 7]));
  });
}
