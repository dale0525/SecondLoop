import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'image_exif_metadata.dart';

final class PlatformExifMetadata {
  const PlatformExifMetadata({
    required this.capturedAtMsUtc,
    required this.latitude,
    required this.longitude,
  });

  final int? capturedAtMsUtc;
  final double? latitude;
  final double? longitude;

  bool get hasLocation => latitude != null && longitude != null;

  bool get isEmpty => capturedAtMsUtc == null && !hasLocation;

  ImageExifMetadata toImageExifMetadata() {
    final capturedAt = capturedAtMsUtc == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            capturedAtMsUtc!,
            isUtc: true,
          ).toLocal();
    return ImageExifMetadata(
      capturedAt: capturedAt,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

final class PlatformExifReader {
  static const MethodChannel _channel = MethodChannel('secondloop/exif');

  static Future<PlatformExifMetadata?> tryReadImageMetadataFromPath(
      String path) async {
    if (kIsWeb) return null;
    if (path.trim().isEmpty) return null;

    try {
      final raw = await _channel.invokeMethod<Object?>(
        'extractImageMetadata',
        <String, Object?>{'path': path},
      );
      if (raw is! Map) return null;

      int? capturedAtMsUtc;
      final rawCapturedAtMs = raw['capturedAtMsUtc'];
      if (rawCapturedAtMs is int) {
        capturedAtMsUtc = rawCapturedAtMs;
      } else if (rawCapturedAtMs is num) {
        capturedAtMsUtc = rawCapturedAtMs.toInt();
      }

      final rawLat = raw['latitude'];
      final rawLon = raw['longitude'];
      final latitude = rawLat is num ? rawLat.toDouble() : null;
      final longitude = rawLon is num ? rawLon.toDouble() : null;

      final meta = PlatformExifMetadata(
        capturedAtMsUtc: capturedAtMsUtc,
        latitude: latitude,
        longitude: longitude,
      );
      return meta.isEmpty ? null : meta;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
