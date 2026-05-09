import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/settings/ai_settings_page.dart';

import 'ai_settings_test_helpers.dart';
import 'test_i18n.dart';

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
      'AI settings advanced section reveals required source controls without opt-out toggles',
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

    final embeddingsSection =
        find.byKey(const ValueKey('ai_settings_section_embeddings'));
    await tester.dragUntilVisible(
      embeddingsSection,
      find.byType(ListView).first,
      const Offset(0, 220),
    );
    await tester.pumpAndSettle();
    expect(embeddingsSection, findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai_settings_embeddings_mode_cloud')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ai_settings_embeddings_mode_byok')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ai_settings_cloud_embeddings_switch')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai_settings_embeddings_mode_local')),
      findsNothing,
    );
  });

  testWidgets(
      'AI settings advanced section does not render removed knowledge controls',
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

    expect(find.byKey(const ValueKey('knowledge_index_status_label')),
        findsNothing);
    expect(find.textContaining('Knowledge Index'), findsNothing);
  });
}
