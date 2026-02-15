import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pubspec includes platform ffmpeg asset directories', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(
      pubspec,
      contains(
          RegExp(r'^\s*-\s*assets/bin/ffmpeg/macos/\s*$', multiLine: true)),
    );
    expect(
      pubspec,
      contains(
          RegExp(r'^\s*-\s*assets/bin/ffmpeg/linux/\s*$', multiLine: true)),
    );
    expect(
      pubspec,
      contains(
          RegExp(r'^\s*-\s*assets/bin/ffmpeg/windows/\s*$', multiLine: true)),
    );
  });
}
