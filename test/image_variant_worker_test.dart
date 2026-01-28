import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/media_backup/image_variant_worker.dart';

void main() {
  test('ImageVariantWorker generates WebP q85 when smaller', () async {
    final original = Uint8List.fromList(List<int>.filled(256, 7));
    final webp = Uint8List.fromList(<int>[
      // 'RIFF' + <len> + 'WEBP' magic
      0x52, 0x49, 0x46, 0x46,
      0x10, 0x00, 0x00, 0x00,
      0x57, 0x45, 0x42, 0x50,
      0x00, 0x01, 0x02, 0x03,
    ]);

    final result = await ImageVariantWorker.generateWebpQ85(
      original,
      mimeType: 'image/png',
      transcode: (bytes, {required webpQuality}) async => webp,
    );

    expect(result.didTranscode, isTrue);
    expect(result.mimeType, 'image/webp');
    expect(result.bytes.length, lessThan(original.length));
    expect(result.bytes.sublist(0, 4), Uint8List.fromList('RIFF'.codeUnits));
    expect(result.bytes.sublist(8, 12), Uint8List.fromList('WEBP'.codeUnits));
  });

  test('ImageVariantWorker keeps original when WebP is larger', () async {
    final original = Uint8List.fromList(List<int>.filled(64, 9));
    final larger = Uint8List.fromList(List<int>.filled(128, 1));

    final result = await ImageVariantWorker.generateWebpQ85(
      original,
      mimeType: 'image/png',
      transcode: (bytes, {required webpQuality}) async => larger,
    );

    expect(result.didTranscode, isFalse);
    expect(result.mimeType, 'image/png');
    expect(result.bytes, original);
  });
}
