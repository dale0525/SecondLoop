import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Settings includes AI source entry and opens unified page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      AppBackendScope(
        backend: TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(
              home: Scaffold(body: SettingsPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final aiEntry = find.byKey(const ValueKey('settings_ai_source'));
    await tester.dragUntilVisible(
      aiEntry,
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();

    expect(aiEntry, findsOneWidget);

    await tester.tap(aiEntry);
    await tester.pumpAndSettle();

    expect(find.byType(AiSettingsPage), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_settings_section_ask_ai')),
        findsOneWidget);
  });
}
