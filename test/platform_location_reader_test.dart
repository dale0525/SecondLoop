import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/platform/platform_location.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('secondloop/location');

  test('reads current location via platform channel on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getCurrentLocation');
      return <String, Object?>{'latitude': 1.23, 'longitude': 4.56};
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    final loc = await PlatformLocationReader.tryGetCurrentLocation();
    expect(loc, isNotNull);
    expect(loc!.latitude, closeTo(1.23, 1e-9));
    expect(loc.longitude, closeTo(4.56, 1e-9));
  });

  test('does not query channel on desktop', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      return null;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    final loc = await PlatformLocationReader.tryGetCurrentLocation();
    expect(loc, isNull);
    expect(called, isFalse);
  });
}
