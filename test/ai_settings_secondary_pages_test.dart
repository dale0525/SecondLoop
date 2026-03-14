import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/settings/ai_ask_ai_settings_page.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';
import 'package:secondloop/features/settings/ai_smart_organization_settings_page.dart';
import 'package:secondloop/ui/sl_surface.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('AI settings home opens Ask AI secondary page', (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: AiSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('ai_settings_open_ask_ai_settings')));
    await tester.pumpAndSettle();

    expect(find.byType(AiAskAiSettingsPage), findsOneWidget);
  });

  testWidgets('AI settings home opens smart organization secondary page',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: AiSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final smartSettings = find
        .byKey(const ValueKey('ai_settings_open_smart_organization_settings'));
    await tester.dragUntilVisible(
      smartSettings,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    await tester.tap(smartSettings);
    await tester.pumpAndSettle();

    expect(find.byType(AiSmartOrganizationSettingsPage), findsOneWidget);
  });

  testWidgets('Ask AI secondary page intro card keeps inner padding',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: AiAskAiSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final introSurface = tester.widget<SlSurface>(find.byType(SlSurface).first);
    expect(introSurface.padding, const EdgeInsets.all(16));
  });

  testWidgets(
      'Smart organization secondary page intro card keeps inner padding',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: AiSmartOrganizationSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final introSurface = tester.widget<SlSurface>(find.byType(SlSurface).first);
    expect(introSurface.padding, const EdgeInsets.all(16));
  });
}
