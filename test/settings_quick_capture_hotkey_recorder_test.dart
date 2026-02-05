import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'test_i18n.dart';

Future<void> _sendRawKeyEvent(Map<String, dynamic> message) async {
  final encoded = SystemChannels.keyEvent.codec.encodeMessage(message);
  final completer = Completer<void>();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    SystemChannels.keyEvent.name,
    encoded,
    (ByteData? data) {
      completer.complete();
    },
  );
  await completer.future;
}

void main() {
  testWidgets('Settings: hotkey recorder captures modifiers on macOS',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      expect(defaultTargetPlatform, TargetPlatform.macOS);
      expect(kIsWeb, isFalse);
      await tester.pumpWidget(
        SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(
              home: Scaffold(body: SettingsPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final shortcutFinder =
          find.byKey(const ValueKey('settings_quick_capture_hotkey'));
      await tester.scrollUntilVisible(shortcutFinder, 500);
      await tester.ensureVisible(shortcutFinder);
      await tester.pumpAndSettle();
      await tester.tap(shortcutFinder);
      await tester.pumpAndSettle();

      await _sendRawKeyEvent(<String, dynamic>{
        'type': 'keydown',
        'keymap': 'macos',
        // Physical key J.
        'keyCode': 0x26,
        'characters': 'j',
        'charactersIgnoringModifiers': 'j',
        // Cmd + Shift.
        'modifiers': 0x100000 | 0x20000,
      });
      await tester.pump();

      expect(find.text('⌘⇧J'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
