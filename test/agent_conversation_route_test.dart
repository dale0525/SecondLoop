import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/agent_ui/agent_conversation_send.dart';

import 'test_backend.dart';

void main() {
  testWidgets(
    'managed pro agent chat ignores stale byok source preference',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'ask_ai_source_preference_v1': 'byok',
      });
      final route = ValueNotifier<AskAiRouteKind?>(null);
      final backend = TestAppBackend();
      final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

      await tester.pumpWidget(
        AppBackendScope(
          backend: backend,
          child: CloudAuthScope(
            controller: _CloudAuthController(),
            gatewayConfig: const CloudGatewayConfig(
              baseUrl: 'https://gateway.example.test',
              modelName: 'cloud',
            ),
            child: SubscriptionScope(
              controller: _SubscriptionController(SubscriptionStatus.entitled),
              child: SessionScope(
                sessionKey: sessionKey,
                lock: () {},
                child: MaterialApp(
                  home: Builder(
                    builder: (context) {
                      return TextButton(
                        onPressed: () async {
                          final resolved = await resolveAgentConversationRoute(
                            context: context,
                            backend: backend,
                            sessionKey: sessionKey,
                          );
                          route.value = resolved.route;
                        },
                        child: const Text('resolve'),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('resolve'));
      await tester.pumpAndSettle();

      expect(route.value, AskAiRouteKind.cloudGateway);
    },
  );
}

final class _CloudAuthController implements CloudAuthController {
  @override
  String? get uid => 'uid_1';

  @override
  String? get email => 'qa@example.test';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'id-token';

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
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}

final class _SubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  _SubscriptionController(this.status);

  @override
  final SubscriptionStatus status;
}
