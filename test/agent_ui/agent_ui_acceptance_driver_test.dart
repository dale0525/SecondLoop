import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';
import 'package:secondloop/features/agent_ui/agent_ui_acceptance_driver.dart';
import 'package:secondloop/core/models/app_models.dart';

import '../test_backend.dart';
import '../test_i18n.dart';

void main() {
  testWidgets(
      'acceptance driver renders simulated operations in agent workspace',
      (tester) async {
    final controller = AgentUiAcceptanceController();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppPlatformCapabilityScope(
            capabilities: const AppPlatformCapabilities(
              supportsDesktopHotkey: true,
              supportsBiometricUnlock: false,
              supportsAudioRecording: false,
              supportsDesktopDrop: true,
              supportsDesktopBootSettings: true,
              supportsCameraCapture: false,
              usesCloudSessionModel: false,
            ),
            child: AppBackendScope(
              backend: TestAppBackend(),
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: AgentUiAcceptanceScope(
                  controller: controller,
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat_input')), findsOneWidget);
    expect(find.byKey(const ValueKey('media_summary_card')), findsNothing);

    controller.simulateManagedProConversationWorkspace();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('media_summary_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('daily_brief_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar_email_card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('research_budget_confirmation_card')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('research_result_card')), findsOneWidget);
  });
}
