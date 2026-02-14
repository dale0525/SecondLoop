import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/keyboard/macos_key_event_channel_normalizer.dart';

void main() {
  test('normalizes mismatched macOS keyup logical key by keyCode', () {
    final normalizer = MacOsKeyEventChannelNormalizer();

    final keyDownMessage = <String, Object?>{
      'keymap': 'macos',
      'type': 'keydown',
      'keyCode': 0,
      'modifiers': 0,
      'characters': 'a',
      'charactersIgnoringModifiers': 'a',
      'specifiedLogicalKey': LogicalKeyboardKey.keyA.keyId,
    };

    final keyUpMessage = <String, Object?>{
      'keymap': 'macos',
      'type': 'keyup',
      'keyCode': 0,
      'modifiers': 0,
      'characters': '',
      'charactersIgnoringModifiers': '',
      'specifiedLogicalKey': 0x01400070004,
    };

    normalizer.normalizeMessage(keyDownMessage);
    final normalized = normalizer.normalizeMessage(keyUpMessage);

    expect(
      (normalized as Map<Object?, Object?>)['specifiedLogicalKey'],
      LogicalKeyboardKey.keyA.keyId,
    );
  });

  test('normalizes mismatched macOS keyup KeyData logical key by physical key',
      () {
    final normalizer = MacOsKeyDataNormalizer();

    const downEvent = ui.KeyData(
      timeStamp: Duration.zero,
      type: ui.KeyEventType.down,
      physical: 0x00070004,
      logical: 0x00000061,
      character: 'a',
      synthesized: false,
    );

    const upEvent = ui.KeyData(
      timeStamp: Duration.zero,
      type: ui.KeyEventType.up,
      physical: 0x00070004,
      logical: 0x01400070004,
      character: null,
      synthesized: false,
    );

    normalizer.normalizeKeyData(downEvent);
    final normalized = normalizer.normalizeKeyData(upEvent);

    expect(normalized.logical, LogicalKeyboardKey.keyA.keyId);
  });

  test('keeps non-macos messages unchanged', () {
    final normalizer = MacOsKeyEventChannelNormalizer();
    final message = <String, Object?>{
      'keymap': 'windows',
      'type': 'keyup',
      'scanCode': 30,
      'keyCode': 65,
    };

    final normalized = normalizer.normalizeMessage(message);

    expect(normalized, same(message));
  });
}
