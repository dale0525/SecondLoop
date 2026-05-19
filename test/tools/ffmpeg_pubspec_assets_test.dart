import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pubspec excludes platform ffmpeg asset directories', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(
      pubspec,
      isNot(contains(RegExp(r'^\s*-\s*assets/bin/ffmpeg/', multiLine: true))),
    );
  });

  test('legacy bundled ffmpeg preparation tools are removed', () {
    const paths = [
      'scripts/prepare_ffmpeg_windows.ps1',
      'scripts/setup_ffmpeg_macos.sh',
      'scripts/setup_ffmpeg_windows.ps1',
      'tools/prepare_bundled_ffmpeg.dart',
      'tools/prepare_bundled_ffmpeg_lib.dart',
      'tools/prune_web_build_ffmpeg.dart',
    ];

    for (final path in paths) {
      expect(
        File(path).existsSync(),
        isFalse,
        reason: '$path must not remain after removing bundled ffmpeg assets',
      );
    }
  });
}
