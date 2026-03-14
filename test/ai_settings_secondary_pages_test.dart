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

  testWidgets('Ask AI advanced review replaces secondary page', (tester) async {
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

    await tester
        .tap(find.byKey(const ValueKey('ask_ai_settings_open_advanced')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ai_settings_section_ask_ai')),
        findsOneWidget);
    expect(find.byType(AiAskAiSettingsPage), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('ai_settings_home_ask_ai')), findsOneWidget);
    expect(find.byType(AiAskAiSettingsPage), findsNothing);
  });

  testWidgets('Smart organization advanced review replaces secondary page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

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

    final openAdvanced =
        find.byKey(const ValueKey('smart_organization_settings_open_advanced'));
    await tester.dragUntilVisible(
      openAdvanced,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    await tester.tap(openAdvanced);
    await tester.pumpAndSettle();

    expect(find.byType(AiSettingsPage), findsOneWidget);
    expect(find.byType(AiSmartOrganizationSettingsPage), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ai_settings_home_smart_organization')),
      findsOneWidget,
    );
    expect(find.byType(AiSmartOrganizationSettingsPage), findsNothing);
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
