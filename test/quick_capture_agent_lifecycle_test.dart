import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
import 'package:secondloop/core/quick_capture/quick_capture_controller.dart';
import 'package:secondloop/core/quick_capture/quick_capture_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';
import 'package:secondloop/features/quick_capture/quick_capture_overlay.dart';
import 'package:secondloop/core/models/app_models.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('quick capture uses agent conversation lifecycle while pending',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ask_ai_source_preference_v1': 'cloud',
    });
    final backend = TestAppBackend();
    final controller = QuickCaptureController();
    final sender = _DelayedRuntimeConversationSender();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: CloudAuthScope(
            controller: _FakeCloudAuthController(),
            gatewayConfig: const CloudGatewayConfig(
              baseUrl: 'https://gateway.test',
              modelName: 'cloud',
            ),
            child: SubscriptionScope(
              controller: _FakeSubscriptionStatusController(),
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: QuickCaptureScope(
                  controller: controller,
                  child: MaterialApp(
                    navigatorKey: navigatorKey,
                    home: QuickCaptureOverlay(
                      navigatorKey: navigatorKey,
                      child: AgentConversationPage(
                        conversation: const Conversation(
                          id: 'loop_home',
                          title: 'Loop',
                          createdAtMs: 0,
                          updatedAtMs: 0,
                        ),
                        isTabActive: true,
                        runtimeConversationSender: sender,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(
      find.byKey(const ValueKey('quick_capture_input')),
      '记住：我下午 6 点后不接工作电话。',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('quick_capture_input')), findsNothing);
    expect(sender.sentMessages, ['记住：我下午 6 点后不接工作电话。']);
    expect(find.byKey(const ValueKey('agent_thinking_panel')), findsOneWidget);
    expect(find.text('记住：我下午 6 点后不接工作电话。'), findsOneWidget);
  });
}

final class _DelayedRuntimeConversationSender
    implements ChatRuntimeConversationSender {
  final List<String> sentMessages = <String>[];
  final Completer<SecretaryRuntimeConversationResult> completer =
      Completer<SecretaryRuntimeConversationResult>();

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) {
    sentMessages.add(message);
    return completer.future;
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  String? get uid => 'uid_1';

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<String?> getIdToken() async => 'token-1';

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

final class _FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  @override
  SubscriptionStatus get status => SubscriptionStatus.entitled;
}
