import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/media_backup/pdf_ingest_compression.dart';

void main() {
  test('compressPdfForIngest defaults to enabled when config read fails',
      () async {
    var calls = 0;
    final result = await compressPdfForIngest(
      Uint8List.fromList(List<int>.filled(64, 1)),
      mimeType: 'application/pdf',
      readPdfSmartCompressEnabled: () async {
        throw StateError('config_read_failed');
      },
      scanClassifier: (_) => true,
      platformCompressor: (bytes, {required scanDpi}) async {
        calls += 1;
        return Uint8List.fromList(List<int>.filled(16, 9));
      },
    );

    expect(calls, 1);
    expect(result.didCompress, isTrue);
    expect(result.bytes.length, 16);
  });

  test('compressPdfForIngest respects disabled config', () async {
    var calls = 0;
    final result = await compressPdfForIngest(
      Uint8List.fromList(List<int>.filled(64, 1)),
      mimeType: 'application/pdf',
      readPdfSmartCompressEnabled: () async => false,
      scanClassifier: (_) => true,
      platformCompressor: (bytes, {required scanDpi}) async {
        calls += 1;
        return Uint8List.fromList(List<int>.filled(16, 9));
      },
    );

    expect(calls, 0);
    expect(result.didCompress, isFalse);
  });
}
