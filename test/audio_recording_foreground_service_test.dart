import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/platform/audio_recording_foreground_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('secondloop/audio_recording_lifecycle');

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('invokes foreground lifecycle channel on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });

    final started = await AudioRecordingForegroundService.startIfSupported();
    final stopped = await AudioRecordingForegroundService.stopIfSupported();

    expect(started, isTrue);
    expect(stopped, isTrue);
    expect(
        calls, <String>['startForegroundRecording', 'stopForegroundRecording']);
  });

  test('is a no-op outside Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    var called = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      return true;
    });

    final started = await AudioRecordingForegroundService.startIfSupported();
    final stopped = await AudioRecordingForegroundService.stopIfSupported();

    expect(started, isTrue);
    expect(stopped, isTrue);
    expect(called, isFalse);
  });

  test('returns false when channel throws on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'failed');
    });

    final started = await AudioRecordingForegroundService.startIfSupported();
    final stopped = await AudioRecordingForegroundService.stopIfSupported();

    expect(started, isFalse);
    expect(stopped, isFalse);
  });
}
