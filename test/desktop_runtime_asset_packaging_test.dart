import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pubspec includes desktop runtime asset directories for recursive files',
      () async {
    final pubspec = File('pubspec.yaml');
    expect(pubspec.existsSync(), isTrue);

    final content = await pubspec.readAsString();
    expect(content, contains('- assets/ocr/desktop_runtime/'));
    expect(content, contains('- assets/ocr/desktop_runtime/models/'));
    expect(content, contains('- assets/ocr/desktop_runtime/onnxruntime/'));
  });
}
