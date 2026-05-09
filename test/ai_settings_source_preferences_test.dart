import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/task_priority_ai_enhancement_prefs.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';

import 'test_i18n.dart';
import 'ai_settings_test_helpers.dart';

bool _switchValue(WidgetTester tester, Finder finder) {
  return tester.widget<SwitchListTile>(finder).value;
}

void main() {
  testWidgets('AI settings stores cloud/BYOK source preferences',
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

    await openAiAdvancedSettings(tester);

    final listView = find.byType(ListView);

    final embeddingsByok =
        find.byKey(const ValueKey('ai_settings_embeddings_mode_byok'));
    await tester.dragUntilVisible(
      embeddingsByok,
      listView,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    await tester.tap(embeddingsByok);
    await tester.pumpAndSettle();

    final mediaByok = find.byKey(const ValueKey('ai_settings_media_mode_byok'));
    await tester.dragUntilVisible(
      mediaByok,
      listView,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    await tester.tap(mediaByok);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('embeddings_source_preference_v1'), 'byok');
    expect(prefs.getString('media_source_preference_v1'), 'byok');
  });

  testWidgets('AI settings stores image Wi-Fi preference independently',
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

    await openAiAdvancedSettings(tester);

    final listView = find.byType(ListView);
    final imageWifiOnly =
        find.byKey(const ValueKey('ai_settings_media_image_wifi_only'));

    await tester.dragUntilVisible(
      imageWifiOnly,
      listView,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    expect(_switchValue(tester, imageWifiOnly), isTrue);

    await tester.tap(imageWifiOnly);
    await tester.pumpAndSettle();

    expect(_switchValue(tester, imageWifiOnly), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('media_capability_image_wifi_only_v1'), isFalse);
  });

  testWidgets(
      'AI settings keeps task priority enhancement required and non-optional',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      TaskPriorityAiEnhancementPrefs.prefsKey: false,
    });

    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: AiSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openAiAdvancedSettings(tester);

    final taskPrioritySwitch =
        find.byKey(const ValueKey('ai_settings_task_priority_ai_switch'));

    expect(taskPrioritySwitch, findsNothing);
    expect(await TaskPriorityAiEnhancementPrefs.read(), isTrue);
  });

  testWidgets('AI settings does not expose AI capability opt-out toggles',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
      'semantic_parse_data_consent_v1': false,
    });

    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: AiSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openAiAdvancedSettings(tester);

    expect(
      find.byKey(
        const ValueKey('ai_settings_semantic_parse_auto_actions_switch'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai_settings_cloud_embeddings_switch')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai_settings_smart_organization_switch')),
      findsNothing,
    );
  });

  testWidgets(
    'AI settings keeps local source choices out of the user-facing surface',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'semantic_parse_data_consent_v1': false,
      });

      await tester.pumpWidget(
        wrapWithI18n(
          const MaterialApp(
            home: AiSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await openAiAdvancedSettings(tester);

      expect(
        find.byKey(const ValueKey('ai_settings_embeddings_mode_local')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ai_settings_media_mode_local')),
        findsNothing,
      );
    },
  );
}
