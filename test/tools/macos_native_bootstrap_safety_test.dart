import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native stt checks speech usage description before requesting auth', () {
    final content =
        File('macos/Runner/AppDelegate+NativeStt.swift').readAsStringSync();

    expect(content, contains('NSSpeechRecognitionUsageDescription'));
    expect(content, contains('speech_permission_usage_description_missing'));

    final guardIndex = content.indexOf('NSSpeechRecognitionUsageDescription');
    final authIndex =
        content.indexOf('SFSpeechRecognizer.authorizationStatus()');
    expect(guardIndex, greaterThanOrEqualTo(0));
    expect(authIndex, greaterThan(guardIndex));
  });

  test('app delegate retries native channel setup when flutter view is late',
      () {
    final appDelegate =
        File('macos/Runner/AppDelegate.swift').readAsStringSync();
    final mainWindow =
        File('macos/Runner/MainFlutterWindow.swift').readAsStringSync();

    expect(
      appDelegate,
      contains('super.applicationDidFinishLaunching(notification)'),
    );
    expect(appDelegate, contains('func configureMethodChannelsIfNeeded()'));
    expect(appDelegate, contains('DispatchQueue.main.asyncAfter'));
    expect(
        mainWindow, contains('appDelegate.configureMethodChannelsIfNeeded()'));
  });
}
