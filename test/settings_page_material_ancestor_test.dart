import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Settings page works without wrapping Scaffold', (tester) async {
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
              home: SettingsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsWidgets);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
