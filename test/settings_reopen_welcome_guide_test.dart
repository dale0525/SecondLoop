import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/settings_page.dart';
import 'package:secondloop/features/welcome/welcome_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('settings can reopen welcome guide', (tester) async {
    SharedPreferences.setMockInitialValues({});

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

    final reopenFinder =
        find.byKey(const ValueKey('settings_reopen_welcome_guide'));
    await tester.scrollUntilVisible(reopenFinder, 240);
    await tester.pumpAndSettle();

    await tester.tap(reopenFinder);
    await tester.pumpAndSettle();

    expect(find.byType(WelcomePage), findsOneWidget);
  });
}
