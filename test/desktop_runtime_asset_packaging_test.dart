import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pubspec excludes desktop runtime asset directories from app bundle',
      () async {
    final pubspec = File('pubspec.yaml');
    expect(pubspec.existsSync(), isTrue);

    final content = await pubspec.readAsString();
    expect(content, isNot(contains('- assets/ocr/desktop_runtime/')));
    expect(content, isNot(contains('- assets/ocr/desktop_runtime/models/')));
    expect(
        content, isNot(contains('- assets/ocr/desktop_runtime/onnxruntime/')));
    expect(content, isNot(contains('- assets/ocr/desktop_runtime/whisper/')));
  });

  test('desktop runtime asset skeleton placeholders are not tracked app assets',
      () {
    final trackedFiles = Process.runSync(
      'git',
      ['ls-files', 'assets/ocr/desktop_runtime'],
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );
    expect(trackedFiles.exitCode, 0);
    expect((trackedFiles.stdout as String).trim(), isEmpty);
  });
}
