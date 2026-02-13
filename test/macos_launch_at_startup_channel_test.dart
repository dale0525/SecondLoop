import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS launch_at_startup method channel is wired in AppDelegate', () {
    final file = File('macos/Runner/AppDelegate.swift');
    expect(file.existsSync(), isTrue);

    final content = file.readAsStringSync();
    expect(content.contains('name: "launch_at_startup"'), isTrue);
    expect(content.contains('case "launchAtStartupIsEnabled"'), isTrue);
    expect(content.contains('case "launchAtStartupSetEnabled"'), isTrue);
  });
}
