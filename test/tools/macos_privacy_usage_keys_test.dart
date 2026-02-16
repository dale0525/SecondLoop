import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macos app config injects speech and microphone usage descriptions', () {
    final config =
        File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();

    expect(
      config,
      contains(
        RegExp(
          r'^\s*INFOPLIST_KEY_NSSpeechRecognitionUsageDescription\s*=\s*.+$',
          multiLine: true,
        ),
      ),
    );
    expect(
      config,
      contains(
        RegExp(
          r'^\s*INFOPLIST_KEY_NSMicrophoneUsageDescription\s*=\s*.+$',
          multiLine: true,
        ),
      ),
    );
  });
}
