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
  testWidgets('Settings omits removed lock controls', (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_lock_enabled_v1': true,
      'biometric_unlock_enabled_v1': true,
      'master_password_setup_required_v1': true,
    });

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

    expect(find.text('Auto lock'), findsNothing);
    expect(find.text('Lock now'), findsNothing);
    expect(find.text('Use biometrics'), findsNothing);
    expect(find.byKey(const ValueKey('settings_runtime_mode')), findsOneWidget);
  });
}
