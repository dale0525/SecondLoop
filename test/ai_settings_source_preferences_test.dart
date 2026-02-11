import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/features/settings/ai_settings_page.dart';

import 'test_i18n.dart';

bool _switchValue(WidgetTester tester, Finder finder) {
  return tester.widget<SwitchListTile>(finder).value;
}

void main() {
  testWidgets('AI settings stores embeddings and media source preferences',
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

    final listView = find.byType(ListView);

    final embeddingsLocal =
        find.byKey(const ValueKey('ai_settings_embeddings_mode_local'));
    await tester.dragUntilVisible(
      embeddingsLocal,
      listView,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    await tester.tap(embeddingsLocal);
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
    expect(prefs.getString('embeddings_source_preference_v1'), 'local');
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
}
