import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Settings can open diagnostics page', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      AppBackendScope(
        backend: TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(home: Scaffold(body: SettingsPage())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final diagnosticsFinder =
        find.byKey(const ValueKey('settings_diagnostics'));
    await tester.scrollUntilVisible(
      diagnosticsFinder,
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    await tester.tap(diagnosticsFinder);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('diagnostics_page')), findsOneWidget);
  });
}
