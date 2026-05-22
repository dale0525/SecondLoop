import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/agent_settings_page.dart';
import 'package:secondloop/features/settings/settings_ui.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  Future<void> pumpSettingsPage(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: TestAppBackend(),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const AgentSettingsPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AgentSettingsPage shows top tabs without duplicate side tabs',
      (tester) async {
    await pumpSettingsPage(tester);

    expect(find.byType(SettingsPageShell), findsOneWidget);
    expect(find.byType(SettingsSection), findsWidgets);
    expect(find.byKey(const ValueKey('agent_settings_open_cloud_account')),
        findsNothing);
    expect(find.byKey(const ValueKey('agent_settings_open_runtime_mode')),
        findsNothing);
    expect(find.byKey(const ValueKey('agent_settings_open_ai_settings')),
        findsNothing);
    expect(find.byKey(const ValueKey('agent_settings_open_diagnostics')),
        findsNothing);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Permissions'), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings_side_tab_list')), findsNothing);
  });

  testWidgets('Account tab owns profile plan billing and security only',
      (tester) async {
    await pumpSettingsPage(tester);

    expect(find.byKey(const ValueKey('cloud_sign_in')), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud_sign_up')), findsOneWidget);
    expect(find.text('Runtime mode'), findsNothing);
    expect(find.text('Allowed actions'), findsNothing);
  });

  testWidgets('Connection tab owns runtime setup and connection health only',
      (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(find.text('Connection'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('runtime_mode_self_managed')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('runtime_mode_managed_pro')), findsOneWidget);
    expect(find.text('Allowed actions'), findsNothing);
    expect(find.text('Activity transparency timeline'), findsNothing);
    expect(
      find.byKey(const ValueKey('agent_settings_open_runtime_mode')),
      findsNothing,
    );
  });

  testWidgets('Permissions tab owns allowed actions only', (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(find.text('Permissions'));
    await tester.pumpAndSettle();

    expect(find.text('Allowed actions'), findsOneWidget);
    expect(find.text('External writes and sends stay behind approval.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('ai_settings_home_ask_ai')), findsNothing);
    expect(find.byKey(const ValueKey('ai_settings_home_smart_organization')),
        findsNothing);
    expect(find.text('Runtime mode'), findsNothing);
    expect(find.text('Memory behavior toggles'), findsNothing);
  });

  testWidgets('Memory tab owns memory behavior toggles only', (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(find.text('Memory'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('agent_digest_regenerate')), findsOneWidget);
    expect(find.text('Allowed actions'), findsNothing);
    expect(find.text('Diagnostic export'), findsNothing);
  });

  testWidgets('Activity tab owns transparency timeline and diagnostics only',
      (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('diagnostics_page')), findsOneWidget);
    expect(find.byKey(const ValueKey('diagnostics_copy')), findsOneWidget);
    expect(find.text('Runtime mode'), findsNothing);
    expect(find.text('Memory behavior toggles'), findsNothing);
  });
}
