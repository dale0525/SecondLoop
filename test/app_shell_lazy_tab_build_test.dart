import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/quick_capture/quick_capture_controller.dart';
import 'package:secondloop/core/quick_capture/quick_capture_scope.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
    'AppShell does not build inactive wide-screen tabs before selection',
    (tester) async {
      var chatBuilds = 0;
      var settingsBuilds = 0;

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppShell(
              chatTabBuilder: (context, isActive) {
                chatBuilds += 1;
                return const SizedBox(key: ValueKey('chat_tab'));
              },
              settingsTabBuilder: (context, isActive) {
                settingsBuilds += 1;
                return const SizedBox(key: ValueKey('settings_tab'));
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat_tab')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings_tab')), findsNothing);
      expect(chatBuilds, greaterThan(0));
      expect(settingsBuilds, 0);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('settings_tab')), findsOneWidget);
      expect(settingsBuilds, greaterThan(0));
    },
  );

  testWidgets(
    'AppShell loads chat tab when quick capture requests switching from settings',
    (tester) async {
      final controller = QuickCaptureController();
      var chatBuilds = 0;

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: QuickCaptureScope(
              controller: controller,
              child: AppShell(
                initialTab: AppTab.settings,
                chatTabBuilder: (context, isActive) {
                  chatBuilds += 1;
                  return const SizedBox(
                      key: ValueKey('chat_tab_from_quick_capture'));
                },
                settingsTabBuilder: (context, isActive) {
                  return const SizedBox(key: ValueKey('settings_tab_initial'));
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat_tab_from_quick_capture')),
          findsNothing);
      expect(chatBuilds, 0);

      controller.hide(openChat: true);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('chat_tab_from_quick_capture')),
        findsOneWidget,
      );
      expect(chatBuilds, greaterThan(0));
    },
  );
}
