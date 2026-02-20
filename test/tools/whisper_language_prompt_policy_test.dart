import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local whisper uses automatic language prompt policy', () {
    final content = File('rust/src/api/audio_transcribe.rs').readAsStringSync();

    expect(
        content, isNot(contains('fn local_whisper_initial_prompt_for_lang(')));
    expect(content, isNot(contains('params.set_initial_prompt(')));
  });
}
