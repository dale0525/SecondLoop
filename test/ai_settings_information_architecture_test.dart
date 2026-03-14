import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/settings/ai_settings_page.dart';

import 'test_i18n.dart';
import 'ai_settings_test_helpers.dart';

void main() {
  testWidgets(
      'AI settings home shows task-first entries and hides advanced controls by default',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: AiSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('ai_settings_home_ask_ai')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai_settings_home_smart_organization')),
      findsOneWidget,
    );
    final advancedSettings =
        find.byKey(const ValueKey('ai_settings_home_advanced_settings'));
    await tester.dragUntilVisible(
      advancedSettings,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    expect(advancedSettings, findsOneWidget);

    expect(
        find.byKey(const ValueKey('ai_settings_section_ask_ai')), findsNothing);
    expect(
      find.byKey(const ValueKey('ai_settings_section_media_understanding')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai_settings_cloud_embeddings_switch')),
      findsNothing,
    );
  });

  testWidgets(
      'AI settings advanced section reveals existing low-level controls',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: AiSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openAiAdvancedSettings(tester);

    expect(find.byKey(const ValueKey('ai_settings_section_ask_ai')),
        findsOneWidget);

    final mediaSection =
        find.byKey(const ValueKey('ai_settings_section_media_understanding'));
    await tester.dragUntilVisible(
      mediaSection,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(mediaSection, findsOneWidget);

    final cloudEmbeddingsSwitch =
        find.byKey(const ValueKey('ai_settings_cloud_embeddings_switch'));
    await tester.dragUntilVisible(
      cloudEmbeddingsSwitch,
      find.byType(ListView).first,
      const Offset(0, 220),
    );
    await tester.pumpAndSettle();
    expect(cloudEmbeddingsSwitch, findsOneWidget);
  });
}
