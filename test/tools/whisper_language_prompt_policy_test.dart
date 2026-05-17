import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local whisper runtime path no longer points at Rust sources', () {
    final content = File(
      'lib/core/runtime_compat/api/audio_transcribe.dart',
    ).readAsStringSync();

    expect(content, contains('audioTranscribeLocalWhisper'));
    expect(
      content,
      contains('UnsupportedError(\'rust_runtime_removed:'),
    );
    expect(content, isNot(contains('set_initial_prompt')));
  });
}
