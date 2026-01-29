import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/platform/android_media_location_permission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('secondloop/permissions');

  test('requests media-location permission on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestMediaLocation');
      return true;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    final granted = await AndroidMediaLocationPermission.requestIfNeeded();
    expect(granted, isTrue);
  });

  test('does not request permission on iOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      return true;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    final granted = await AndroidMediaLocationPermission.requestIfNeeded();
    expect(granted, isTrue);
    expect(called, isFalse);
  });
}
