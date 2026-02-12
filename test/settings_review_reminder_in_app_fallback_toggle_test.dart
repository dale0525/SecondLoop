import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/notifications/review_reminder_in_app_fallback_prefs.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Settings: toggling in-app reminder fallback persists preference',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ReviewReminderInAppFallbackPrefs.prefsKey: false,
    });

    await tester.pumpWidget(
      SessionScope(
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        lock: () {},
        child: wrapWithI18n(
          const MaterialApp(home: Scaffold(body: SettingsPage())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fallbackSwitchTile = find.byKey(
      const ValueKey('settings_review_reminder_in_app_fallback_switch'),
    );
    await tester.scrollUntilVisible(
      fallbackSwitchTile,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(fallbackSwitchTile, findsOneWidget);

    final initialSwitch = tester.widget<Switch>(
      find.descendant(of: fallbackSwitchTile, matching: find.byType(Switch)),
    );
    expect(initialSwitch.value, isFalse);

    await tester.tap(fallbackSwitchTile);
    await tester.pumpAndSettle();

    final updatedSwitch = tester.widget<Switch>(
      find.descendant(of: fallbackSwitchTile, matching: find.byType(Switch)),
    );
    expect(updatedSwitch.value, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ReviewReminderInAppFallbackPrefs.prefsKey), isTrue);
  });
}
