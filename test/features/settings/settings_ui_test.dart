import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/settings/settings_ui.dart';
import 'package:secondloop/ui/sl_background.dart';
import 'package:secondloop/ui/sl_button.dart';
import 'package:secondloop/ui/sl_surface.dart';

void main() {
  testWidgets('SettingsPageShell wraps content in SlBackground',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsPageShell(
          title: 'Settings',
          children: [
            Text('Body'),
          ],
        ),
      ),
    );

    expect(find.byType(SlBackground), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
  });

  testWidgets('SettingsPageShell paints the scaffold behind app bars',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsPageShell(
          title: 'Settings',
          children: [
            Text('Body'),
          ],
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, isNot(Colors.transparent));
  });

  testWidgets('SettingsSection renders rows inside one surface',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsSection(
            title: 'Account',
            children: [
              SettingsRow(
                title: 'Cloud account',
                body: 'Signed in',
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Cloud account'), findsOneWidget);
    expect(find.byType(SlSurface), findsOneWidget);
  });

  testWidgets('SettingsActionBar uses SlButton variants', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsActionBar(
            actions: [
              SettingsAction(
                label: 'Save',
                onPressed: () {},
              ),
              SettingsAction(
                label: 'Cancel',
                onPressed: () {},
                variant: SlButtonVariant.outline,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(SlButton), findsNWidgets(2));
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('SettingsStatusBadge exposes compact status text',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsStatusBadge(
            label: 'Ready',
            badgeKey: ValueKey('ready_badge'),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('ready_badge')), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
  });
}
