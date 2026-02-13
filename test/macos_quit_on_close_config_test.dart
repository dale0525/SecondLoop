import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS app keeps running after last window closes', () {
    final file = File('macos/Runner/AppDelegate.swift');
    expect(file.existsSync(), isTrue);

    final content = file.readAsStringSync();
    final pattern = RegExp(
      r'applicationShouldTerminateAfterLastWindowClosed\([\s\S]*?\) -> Bool \{\s*return false\s*\}',
      multiLine: true,
    );

    expect(pattern.hasMatch(content), isTrue);
  });
}
