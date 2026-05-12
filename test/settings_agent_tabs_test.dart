import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/settings/agent_settings_page.dart';

import 'test_i18n.dart';

void main() {
  Future<void> pumpSettingsPage(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(home: AgentSettingsPage()),
      ),
    );
  }

  testWidgets('AgentSettingsPage shows top tabs without duplicate side tabs',
      (tester) async {
    await pumpSettingsPage(tester);

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

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Billing'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Runtime mode'), findsNothing);
    expect(find.text('Allowed actions'), findsNothing);
  });

  testWidgets('Connection tab owns runtime setup and connection health only',
      (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(find.text('Connection'));
    await tester.pumpAndSettle();

    expect(find.text('Runtime mode'), findsOneWidget);
    expect(find.text('Connection health'), findsOneWidget);
    expect(find.text('Allowed actions'), findsNothing);
    expect(find.text('Activity transparency timeline'), findsNothing);
  });

  testWidgets('Permissions tab owns allowed actions only', (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(find.text('Permissions'));
    await tester.pumpAndSettle();

    expect(find.text('Allowed actions'), findsOneWidget);
    expect(find.text('Runtime mode'), findsNothing);
    expect(find.text('Memory behavior toggles'), findsNothing);
  });

  testWidgets('Memory tab owns memory behavior toggles only', (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(find.text('Memory'));
    await tester.pumpAndSettle();

    expect(find.text('Memory behavior toggles'), findsOneWidget);
    expect(find.text('Allowed actions'), findsNothing);
    expect(find.text('Diagnostic export'), findsNothing);
  });

  testWidgets('Activity tab owns transparency timeline and diagnostics only',
      (tester) async {
    await pumpSettingsPage(tester);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();

    expect(find.text('Activity transparency timeline'), findsOneWidget);
    expect(find.text('Diagnostic export'), findsOneWidget);
    expect(find.text('Runtime mode'), findsNothing);
    expect(find.text('Memory behavior toggles'), findsNothing);
  });
}
