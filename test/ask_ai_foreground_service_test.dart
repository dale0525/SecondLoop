import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/platform/ask_ai_foreground_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const serviceChannel = MethodChannel('secondloop/audio_recording_lifecycle');
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  final serviceCalls = <MethodCall>[];
  final notificationCalls = <MethodCall>[];

  setUp(() {
    serviceCalls.clear();
    notificationCalls.clear();
    debugDefaultTargetPlatformOverride = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(serviceChannel, (call) async {
      serviceCalls.add(call);
      if (call.method == 'startForegroundAskAi') return true;
      if (call.method == 'stopForegroundAskAi') return true;
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
      notificationCalls.add(call);
      if (call.method == 'requestNotificationsPermission') return true;
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(serviceChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
  });

  test('start asks Android notification permission before foreground',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final started = await AskAiForegroundService.startIfSupported();

    expect(started, isTrue);
    expect(
      notificationCalls.any(
        (call) => call.method == 'requestNotificationsPermission',
      ),
      isTrue,
    );
    expect(
      serviceCalls.any((call) => call.method == 'startForegroundAskAi'),
      isTrue,
    );
  });

  test('stop calls ask-ai foreground stop method on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final stopped = await AskAiForegroundService.stopIfSupported();

    expect(stopped, isTrue);
    expect(
      serviceCalls.any((call) => call.method == 'stopForegroundAskAi'),
      isTrue,
    );
  });

  test('start on iOS returns true without channel calls', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final started = await AskAiForegroundService.startIfSupported();

    expect(started, isTrue);
    expect(notificationCalls, isEmpty);
    expect(serviceCalls, isEmpty);
  });
}
