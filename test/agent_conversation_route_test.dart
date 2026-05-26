import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/core/cloud/secretary_runtime_client.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_models.dart';
import 'package:secondloop/core/cloud/secretary_runtime_conversation_sender.dart';
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

  testWidgets(
    'self-managed agent chat uses stored runtime profile without managed pro login',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await RuntimeConnectionStore().saveConnection(_selfManagedConnection);
      final sender = _RecordingRuntimeSender();
      final route = ValueNotifier<AskAiRouteKind?>(null);
      final backend = TestAppBackend();
      final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

      await tester.pumpWidget(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: sessionKey,
            lock: () {},
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  return TextButton(
                    onPressed: () async {
                      final result = await sendAgentConversationMessage(
                        context: context,
                        backend: backend,
                        sessionKey: sessionKey,
                        conversationId: 'loop_home',
                        message: '帮我创建一个任务：完成周报。',
                        runtimeConversationSender: sender,
                      );
                      route.value = result.routeKind;
                    },
                    child: const Text('send'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('send'));
      await tester.pumpAndSettle();

      expect(route.value, AskAiRouteKind.cloudGateway);
      expect(sender.vaultIds, ['acct-1']);
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

final class _RecordingRuntimeSender implements ChatRuntimeConversationSender {
  final vaultIds = <String>[];

  @override
  Future<SecretaryRuntimeConversationResult> send({
    required String vaultId,
    required String conversationId,
    required String message,
  }) async {
    vaultIds.add(vaultId);
    return SecretaryRuntimeConversationResult(
      runId: 'run-1',
      conversationId: conversationId,
      assistantContent: '已创建任务。',
      metadata: SecretaryRuntimeResponseMetadata(
        runId: 'run-1',
        turnId: 'turn-1',
        conversationId: conversationId,
        vaultId: vaultId,
        responseType: 'task_created',
        runStatus: 'completed',
        approvalRequired: false,
        proposedMutations: const <Map<String, Object?>>[],
        appliedMutations: const <Map<String, Object?>>[],
        approvalItems: const <SecretaryRuntimeApprovalItem>[],
      ),
    );
  }
}

const _selfManagedConnection = CloudRuntimeConnection(
  profile: CloudRuntimeProfile(
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: 'https://user-runtime.example/',
    authMode: CloudRuntimeAuthMode.runtimeToken,
    authToken: 'runtime-token-1',
    capabilityManifestId: 'manifest-self-1',
    manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
    vaultId: 'acct-1',
  ),
  manifest: CloudRuntimeManifest(
    manifestVersion: RuntimeConnectionStore.supportedManifestVersion,
    runtimeMode: CloudRuntimeMode.selfManaged,
    apiBaseUrl: 'https://user-runtime.example/',
    authMode: CloudRuntimeAuthMode.runtimeToken,
    capabilities: CloudRuntimeRequiredCapabilities.all,
  ),
);
