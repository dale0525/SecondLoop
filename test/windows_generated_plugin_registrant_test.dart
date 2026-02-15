import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('windows generated plugin registrant keeps just_audio_windows wired',
      () {
    final registrant = File('windows/flutter/generated_plugin_registrant.cc')
        .readAsStringSync();
    final pluginsCmake =
        File('windows/flutter/generated_plugins.cmake').readAsStringSync();

    expect(
      registrant,
      contains('#include <just_audio_windows/just_audio_windows_plugin.h>'),
    );
    expect(
      registrant,
      contains('JustAudioWindowsPluginRegisterWithRegistrar('),
    );
    expect(pluginsCmake, contains('just_audio_windows'));
  });
}
