import 'dart:async';

import '../../core/platform/platform_location.dart';

typedef AttachmentExifUpsert = Future<void> Function({
  required int? capturedAtMs,
  required double latitude,
  required double longitude,
});

Future<void> deferAttachmentLocationUpsert({
  required Future<PlatformLocation?> locationFuture,
  required int? capturedAtMs,
  required AttachmentExifUpsert upsert,
}) async {
  try {
    final loc = await locationFuture;
    if (loc == null) return;
    if (loc.latitude == 0.0 && loc.longitude == 0.0) return;
    if (loc.latitude.isNaN || loc.longitude.isNaN) return;

    await upsert(
      capturedAtMs: capturedAtMs,
      latitude: loc.latitude,
      longitude: loc.longitude,
    );
  } catch (_) {
    return;
  }
}
