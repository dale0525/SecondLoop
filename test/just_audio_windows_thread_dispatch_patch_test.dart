import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('patched just_audio_windows marshals EventSink messages to UI thread',
      () {
    final file = File(
      'third_party/just_audio_windows_patched/windows/player.hpp',
    );
    expect(file.existsSync(), isTrue);

    final content = file.readAsStringSync();
    expect(content, contains('DispatcherQueue'));
    expect(content, contains('TryEnqueue'));
  });
}
