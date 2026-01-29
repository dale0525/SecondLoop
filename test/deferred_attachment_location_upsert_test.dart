import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/platform/platform_location.dart';
import 'package:secondloop/features/chat/deferred_attachment_location_upsert.dart';

void main() {
  test('defers exif upsert until location resolves', () async {
    final completer = Completer<PlatformLocation?>();

    var called = false;
    int? capturedAtMsSeen;
    double? latSeen;
    double? lonSeen;

    final future = deferAttachmentLocationUpsert(
      locationFuture: completer.future,
      capturedAtMs: 123,
      upsert: ({
        required int? capturedAtMs,
        required double latitude,
        required double longitude,
      }) async {
        called = true;
        capturedAtMsSeen = capturedAtMs;
        latSeen = latitude;
        lonSeen = longitude;
      },
    );

    expect(called, isFalse);

    completer.complete(const PlatformLocation(latitude: 1.23, longitude: 4.56));
    await future;

    expect(called, isTrue);
    expect(capturedAtMsSeen, 123);
    expect(latSeen, closeTo(1.23, 1e-9));
    expect(lonSeen, closeTo(4.56, 1e-9));
  });
}
