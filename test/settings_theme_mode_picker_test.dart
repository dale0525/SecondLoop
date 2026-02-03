import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/theme_mode_prefs.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Settings: theme picker persists selection', (tester) async {
    SharedPreferences.setMockInitialValues({});
    AppThemeModePrefs.resetForTests();
    await AppThemeModePrefs.ensureInitialized();

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

    expect(find.text('Theme'), findsOneWidget);

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();

    expect(find.text('System'), findsWidgets);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_mode_v1'), 'dark');
    expect(AppThemeModePrefs.value.value, ThemeMode.dark);
  });
}
