import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class PlatformLocation {
  const PlatformLocation({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

final class PlatformLocationReader {
  static const MethodChannel _channel = MethodChannel('secondloop/location');

  static Future<PlatformLocation?> tryGetCurrentLocation() async {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        break;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return null;
    }

    try {
      final raw =
          await _channel.invokeMapMethod<String, Object?>('getCurrentLocation');
      if (raw == null) return null;
      final latitude = raw['latitude'];
      final longitude = raw['longitude'];
      if (latitude is! num || longitude is! num) return null;

      final lat = latitude.toDouble();
      final lon = longitude.toDouble();
      if (lat == 0.0 && lon == 0.0) return null;
      if (lat.isNaN || lon.isNaN) return null;

      return PlatformLocation(latitude: lat, longitude: lon);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
