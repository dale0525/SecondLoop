import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/update/update_badge_prefs.dart';

import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();
  });

  testWidgets('desktop AppShell exposes the four agent destinations',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppShell(
            conversationTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_conversation_tab')),
            memoryTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_memory_tab')),
            reviewTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_review_tab')),
            settingsTabBuilder: (_, __) =>
                const SizedBox(key: ValueKey('agent_settings_tab')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('mobile AppShell exposes the four agent destinations',
      (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    try {
      await tester.binding.setSurfaceSize(const Size(390, 844));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppShell(
              conversationTabBuilder: (_, __) =>
                  const SizedBox(key: ValueKey('agent_conversation_tab')),
              memoryTabBuilder: (_, __) =>
                  const SizedBox(key: ValueKey('agent_memory_tab')),
              reviewTabBuilder: (_, __) =>
                  const SizedBox(key: ValueKey('agent_review_tab')),
              settingsTabBuilder: (_, __) =>
                  const SizedBox(key: ValueKey('agent_settings_tab')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('app_shell_bottom_nav')),
        findsOneWidget,
      );
      expect(find.text('Conversation'), findsOneWidget);
      expect(find.text('Memory'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('agent_review_tab')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
      await tester.binding.setSurfaceSize(null);
    }
  });
}
