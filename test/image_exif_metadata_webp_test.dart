import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:secondloop/features/attachments/image_exif_metadata.dart';

void main() {
  test('reads captured time + location from WebP EXIF chunk', () {
    final webp = _webpWithExif(_exifPayloadBytes());

    final metadata = tryReadImageExifMetadata(webp);

    expect(metadata, isNotNull);
    expect(formatCapturedAt(metadata!.capturedAt!), '2026-01-27 10:23');
    expect(
      formatLatLon(metadata.latitude!, metadata.longitude!),
      '37.76667 N, 122.41667 W',
    );
  });
}

Uint8List _exifPayloadBytes() {
  final exif = img.ExifData();
  exif.exifIfd['DateTimeOriginal'] = '2026:01:27 10:23:45';
  exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
  exif.gpsIfd['GPSLatitude'] = _gpsCoordinateValue(
    degrees: 37,
    minutes: 46,
    seconds: 0,
  );
  exif.gpsIfd['GPSLongitudeRef'] = img.IfdValueAscii('W');
  exif.gpsIfd['GPSLongitude'] = _gpsCoordinateValue(
    degrees: 122,
    minutes: 25,
    seconds: 0,
  );

  final out = img.OutputBuffer();
  exif.write(out);
  final tiff = out.getBytes();

  final exifHeader = ascii.encode('Exif\x00\x00');
  return Uint8List.fromList([...exifHeader, ...tiff]);
}

img.IfdValueRational _gpsCoordinateValue({
  required int degrees,
  required int minutes,
  required int seconds,
}) {
  final data = ByteData(24)
    ..setUint32(0, degrees, Endian.big)
    ..setUint32(4, 1, Endian.big)
    ..setUint32(8, minutes, Endian.big)
    ..setUint32(12, 1, Endian.big)
    ..setUint32(16, seconds, Endian.big)
    ..setUint32(20, 1, Endian.big);
  return img.IfdValueRational.data(
    img.InputBuffer(data.buffer.asUint8List(), bigEndian: true),
    3,
  );
}

Uint8List _webpWithExif(Uint8List exifPayload) {
  final chunkSize = exifPayload.length;
  final padding = chunkSize.isOdd ? 1 : 0;
  final riffSize = 4 + 8 + chunkSize + padding;

  final out = BytesBuilder();
  out.add(const [0x52, 0x49, 0x46, 0x46]); // 'RIFF'
  final riffSizeBytes = ByteData(4)..setUint32(0, riffSize, Endian.little);
  out.add(riffSizeBytes.buffer.asUint8List());
  out.add(const [0x57, 0x45, 0x42, 0x50]); // 'WEBP'
  out.add(const [0x45, 0x58, 0x49, 0x46]); // 'EXIF'
  final chunkSizeBytes = ByteData(4)..setUint32(0, chunkSize, Endian.little);
  out.add(chunkSizeBytes.buffer.asUint8List());
  out.add(exifPayload);
  if (padding == 1) out.add(const [0x00]);
  return out.toBytes();
}
