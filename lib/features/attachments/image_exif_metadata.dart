import 'dart:typed_data';

import 'package:image/image.dart' as img;

final class ImageExifMetadata {
  const ImageExifMetadata({
    required this.capturedAt,
    required this.latitude,
    required this.longitude,
  });

  final DateTime? capturedAt;
  final double? latitude;
  final double? longitude;

  bool get hasLocation => latitude != null && longitude != null;

  bool get isEmpty => capturedAt == null && !hasLocation;
}

ImageExifMetadata? tryReadImageExifMetadata(Uint8List bytes) {
  final exif = _tryReadExif(bytes);
  if (exif == null) return null;

  final capturedAt = _tryReadCapturedAt(exif);
  final location = _tryReadLatLon(exif);

  final metadata = ImageExifMetadata(
    capturedAt: capturedAt,
    latitude: location?.$1,
    longitude: location?.$2,
  );
  return metadata.isEmpty ? null : metadata;
}

String formatCapturedAt(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm';
}

String formatLatLon(double latitude, double longitude) {
  final latDir = latitude >= 0 ? 'N' : 'S';
  final lonDir = longitude >= 0 ? 'E' : 'W';
  final lat = latitude.abs().toStringAsFixed(5);
  final lon = longitude.abs().toStringAsFixed(5);
  return '$lat $latDir, $lon $lonDir';
}

img.ExifData? _tryReadExif(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return img.decodeJpgExif(bytes);
  }

  final webpExif = _tryExtractWebpExif(bytes);
  if (webpExif != null && webpExif.isNotEmpty) {
    try {
      return img.ExifData.fromInputBuffer(img.InputBuffer(webpExif));
    } catch (_) {
      return null;
    }
  }

  return null;
}

Uint8List? _tryExtractWebpExif(Uint8List bytes) {
  if (bytes.length < 12) return null;
  if (bytes[0] != 0x52 ||
      bytes[1] != 0x49 ||
      bytes[2] != 0x46 ||
      bytes[3] != 0x46) {
    return null; // 'RIFF'
  }
  if (bytes[8] != 0x57 ||
      bytes[9] != 0x45 ||
      bytes[10] != 0x42 ||
      bytes[11] != 0x50) {
    return null; // 'WEBP'
  }

  int offset = 12;
  while (offset + 8 <= bytes.length) {
    final tag0 = bytes[offset];
    final tag1 = bytes[offset + 1];
    final tag2 = bytes[offset + 2];
    final tag3 = bytes[offset + 3];
    final size = _readLeUint32(bytes, offset + 4);
    offset += 8;
    if (offset + size > bytes.length) return null;

    final isExif =
        tag0 == 0x45 && tag1 == 0x58 && tag2 == 0x49 && tag3 == 0x46; // 'EXIF'
    if (isExif) {
      return Uint8List.sublistView(bytes, offset, offset + size);
    }

    offset += size;
    if (size.isOdd) offset += 1; // padding byte
  }

  return null;
}

int _readLeUint32(Uint8List bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

DateTime? _tryReadCapturedAt(img.ExifData exif) {
  final candidates = <String?>[
    exif.exifIfd['DateTimeOriginal']?.toString(),
    exif.exifIfd['DateTimeDigitized']?.toString(),
    exif.imageIfd['DateTime']?.toString(),
  ];

  for (final raw in candidates) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) continue;
    final parsed = _tryParseExifDateTime(value);
    if (parsed != null) return parsed;
  }
  return null;
}

DateTime? _tryParseExifDateTime(String value) {
  final match = RegExp(r'^(\d{4}):(\d{2}):(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$')
      .firstMatch(value);
  if (match == null) return null;

  int? parseGroup(int i) => int.tryParse(match.group(i) ?? '');
  final year = parseGroup(1);
  final month = parseGroup(2);
  final day = parseGroup(3);
  final hour = parseGroup(4);
  final minute = parseGroup(5);
  final second = parseGroup(6);
  if (year == null ||
      month == null ||
      day == null ||
      hour == null ||
      minute == null ||
      second == null) {
    return null;
  }

  return DateTime(year, month, day, hour, minute, second);
}

(double, double)? _tryReadLatLon(img.ExifData exif) {
  final latValue = exif.gpsIfd['GPSLatitude'];
  final lonValue = exif.gpsIfd['GPSLongitude'];
  if (latValue == null || lonValue == null) return null;

  final latRef = exif.gpsIfd['GPSLatitudeRef']?.toString().trim();
  final lonRef = exif.gpsIfd['GPSLongitudeRef']?.toString().trim();

  final lat = _tryParseGpsCoordinate(latValue, latRef);
  final lon = _tryParseGpsCoordinate(lonValue, lonRef);
  if (lat == null || lon == null) return null;
  return (lat, lon);
}

double? _tryParseGpsCoordinate(img.IfdValue value, String? ref) {
  if (value.type != img.IfdValueType.rational || value.length < 3) return null;

  final degrees = value.toRational(0).toDouble();
  final minutes = value.toRational(1).toDouble();
  final seconds = value.toRational(2).toDouble();
  if (degrees.isNaN || minutes.isNaN || seconds.isNaN) return null;

  var decimal = degrees + (minutes / 60.0) + (seconds / 3600.0);
  final direction = (ref ?? '').trim().toUpperCase();
  if (direction == 'S' || direction == 'W') {
    decimal *= -1;
  }
  return decimal;
}
