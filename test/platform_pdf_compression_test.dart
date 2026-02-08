import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/media_backup/platform_pdf_compression.dart';

void main() {
  test('compressPdfScanPagesViaPlatform passes bytes and dpi', () async {
    final result = await compressPdfScanPagesViaPlatform(
      Uint8List.fromList(const <int>[9, 8, 7]),
      scanDpi: 180,
      desktopCompressor: (bytes, {required scanDpi}) async {
        expect(scanDpi, 180);
        expect(bytes, isA<Uint8List>());
        return Uint8List.fromList(const <int>[1, 2, 3]);
      },
    );

    expect(result, isNotNull);
    expect(result, Uint8List.fromList(const <int>[1, 2, 3]));
  });

  test('compressPdfScanPagesViaPlatform clamps dpi into 180..300', () async {
    final result = await compressPdfScanPagesViaPlatform(
      Uint8List.fromList(const <int>[1]),
      scanDpi: 10,
      desktopCompressor: (bytes, {required scanDpi}) async {
        expect(scanDpi, 180);
        return null;
      },
    );

    expect(result, isNull);
  });

  test('compressPdfScanPagesViaPlatform returns null when runtime fails',
      () async {
    final result = await compressPdfScanPagesViaPlatform(
      Uint8List.fromList(const <int>[9, 8, 7]),
      scanDpi: 180,
      desktopCompressor: (bytes, {required scanDpi}) async {
        throw StateError('runtime_error');
      },
    );

    expect(result, isNull);
  });
}
