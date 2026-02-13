import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Settings (desktop): boot and background switches persist',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues({
      'desktop.start_with_system_v1': false,
      'desktop.silent_startup_v1': false,
      'desktop.keep_running_in_background_v1': true,
    });

    try {
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

      final startWithSystemFinder =
          find.byKey(const ValueKey('settings_start_with_system_switch'));
      final silentStartupFinder =
          find.byKey(const ValueKey('settings_silent_startup_switch'));
      final keepRunningFinder = find
          .byKey(const ValueKey('settings_keep_running_in_background_switch'));

      await tester.scrollUntilVisible(startWithSystemFinder, 300);
      await tester.ensureVisible(startWithSystemFinder);
      await tester.pumpAndSettle();

      await tester.tap(startWithSystemFinder);
      await tester.pumpAndSettle();

      await tester.tap(silentStartupFinder);
      await tester.pumpAndSettle();

      await tester.tap(keepRunningFinder);
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('desktop.start_with_system_v1'), true);
      expect(prefs.getBool('desktop.silent_startup_v1'), true);
      expect(prefs.getBool('desktop.keep_running_in_background_v1'), false);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
