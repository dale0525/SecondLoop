import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/app/app_shell_style.dart';
import 'package:secondloop/app/theme.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('agent conversation desktop workspace follows dark app theme',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_conversationUnderTest(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final workspace = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('agent_conversation_workspace')),
    );
    expect(workspace.color, AppShellPalette.darkSoft);

    final chatColumn = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('desktop_workbench_chat_column')),
    );
    expect(chatColumn.color, AppShellPalette.darkSoft);

    final composer = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('desktop_workbench_composer_box')),
    );
    final decoration = composer.decoration;
    expect(decoration, isA<BoxDecoration>());
    expect((decoration as BoxDecoration).color, AppShellPalette.darkPanel);
  });

  testWidgets('agent conversation mobile composer follows dark app theme',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_conversationUnderTest(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final workspace = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('agent_conversation_workspace')),
    );
    expect(workspace.color, AppShellPalette.darkSoft);

    final composer = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('operating_composer_box')),
    );
    final decoration = composer.decoration;
    expect(decoration, isA<BoxDecoration>());
    expect((decoration as BoxDecoration).color, AppShellPalette.darkPanel);

    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('chat_input')),
    );
    expect(input.style?.color, AppShellPalette.darkInk);
    expect(input.decoration?.hintStyle?.color, isNot(Colors.white));
  });
}

Widget _conversationUnderTest({required ThemeMode themeMode}) {
  return wrapWithI18n(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: AppBackendScope(
        backend: TestAppBackend(),
        child: AppPlatformCapabilityScope(
          capabilities: const AppPlatformCapabilities(
            supportsDesktopHotkey: true,
            supportsAudioRecording: true,
            supportsDesktopDrop: true,
            supportsDesktopBootSettings: true,
            supportsCameraCapture: false,
            usesCloudSessionModel: false,
          ),
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: SubscriptionScope(
              controller: _SubscriptionController(),
              child: const AgentConversationPage(
                conversation: Conversation(
                  id: 'loop_home',
                  title: 'Loop',
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
                isTabActive: true,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _SubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  @override
  SubscriptionStatus get status => SubscriptionStatus.entitled;
}
