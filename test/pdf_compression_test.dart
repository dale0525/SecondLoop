import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/media_backup/pdf_compression.dart';

void main() {
  const enabledConfig = PdfCompressionConfig(enabled: true);

  test('compressPdfForStorage skips non-pdf mime types', () async {
    var calls = 0;
    final input = Uint8List.fromList(List<int>.filled(32, 1));
    final result = await compressPdfForStorage(
      input,
      mimeType: 'text/plain',
      config: enabledConfig,
      platformCompressor: (bytes, {required scanDpi}) async {
        calls += 1;
        return Uint8List.fromList(const <int>[1]);
      },
    );

    expect(result.didCompress, isFalse);
    expect(result.bytes, input);
    expect(calls, 0);
  });

  test('compressPdfForStorage skips when disabled', () async {
    var calls = 0;
    final input = Uint8List.fromList(List<int>.filled(32, 2));
    const disabledConfig = PdfCompressionConfig(enabled: false);

    final result = await compressPdfForStorage(
      input,
      mimeType: 'application/pdf',
      config: disabledConfig,
      scanClassifier: (_) => true,
      platformCompressor: (bytes, {required scanDpi}) async {
        calls += 1;
        return Uint8List.fromList(const <int>[1]);
      },
    );

    expect(result.didCompress, isFalse);
    expect(result.bytes, input);
    expect(calls, 0);
  });

  test('compressPdfForStorage keeps text-heavy pdf as lossless original',
      () async {
    var calls = 0;
    final input = Uint8List.fromList(utf8.encode(
      '%PDF-1.7\n1 0 obj\n<< /Type /Page /Resources << /Font << /F1 2 0 R >> >> >>\nendobj\n',
    ));
    final result = await compressPdfForStorage(
      input,
      mimeType: 'application/pdf',
      config: enabledConfig,
      platformCompressor: (bytes, {required scanDpi}) async {
        calls += 1;
        return Uint8List.fromList(const <int>[1, 2, 3]);
      },
    );

    expect(result.didCompress, isFalse);
    expect(result.bytes, input);
    expect(calls, 0);
  });

  test('compressPdfForStorage keeps smaller scan compression output', () async {
    final input = Uint8List.fromList(List<int>.filled(128, 3));
    final result = await compressPdfForStorage(
      input,
      mimeType: 'application/pdf',
      config: enabledConfig,
      scanClassifier: (_) => true,
      platformCompressor: (bytes, {required scanDpi}) async {
        expect(scanDpi, 220);
        return Uint8List.fromList(List<int>.filled(16, 9));
      },
    );

    expect(result.didCompress, isTrue);
    expect(result.mimeType, 'application/pdf');
    expect(result.bytes.length, 16);
  });

  test('compressPdfForStorage retries with lower dpi when 220 is not smaller',
      () async {
    final input = Uint8List.fromList(List<int>.filled(200, 5));
    final attemptedDpi = <int>[];
    final result = await compressPdfForStorage(
      input,
      mimeType: 'application/pdf',
      config: enabledConfig,
      scanClassifier: (_) => true,
      platformCompressor: (bytes, {required scanDpi}) async {
        attemptedDpi.add(scanDpi);
        if (scanDpi == 220) {
          return Uint8List.fromList(List<int>.filled(220, 1));
        }
        if (scanDpi == 200) {
          return Uint8List.fromList(List<int>.filled(150, 1));
        }
        return Uint8List.fromList(List<int>.filled(140, 1));
      },
    );

    expect(result.didCompress, isTrue);
    expect(result.bytes.length, 150);
    expect(attemptedDpi, <int>[220, 200]);
  });

  test('compressPdfForStorage falls back to original on failed compression',
      () async {
    final input = Uint8List.fromList(List<int>.filled(96, 4));
    final result = await compressPdfForStorage(
      input,
      mimeType: 'application/pdf',
      config: enabledConfig,
      scanClassifier: (_) => true,
      platformCompressor: (bytes, {required scanDpi}) async {
        return Uint8List.fromList(List<int>.filled(120, 4));
      },
    );

    expect(result.didCompress, isFalse);
    expect(result.bytes, input);
  });
}
