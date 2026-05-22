import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_models.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_repository.dart';
import 'package:secondloop/features/memory/memory_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
    'managed pro MemoryPage reads approved memories from runtime state',
    (tester) async {
      final repository = _FakeRuntimeAgentStateRepository(
        RuntimeAgentState.fromJson(const {
          'vault_id': 'uid_1',
          'conversation_id': 'loop_home',
          'conversation_turns': [],
          'working_set_records': [],
          'tasks': [],
          'memory_records': [
            {
              'id': 'memory-language',
              'kind': 'memory',
              'text': '任务回复请使用中文',
            }
          ],
          'recurring_reminder_rules': [],
          'approval_items': [],
          'recent_entity_refs': [],
          'latest_context_snapshot': null,
          'audit_refs': [],
        }),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: CloudAuthScope(
              controller: _CloudAuthController(),
              gatewayConfig: const CloudGatewayConfig(
                baseUrl: 'https://gateway.example.test',
                modelName: 'cloud',
              ),
              child: MemoryPage(runtimeAgentStateRepository: repository),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.requests, [('uid_1', 'loop_home')]);
      expect(find.text('任务回复请使用中文'), findsWidgets);
      expect(find.text('No knowledge pages yet.'), findsNothing);
    },
  );

  testWidgets(
    'managed pro MemoryPage reads memories from the runtime context snapshot',
    (tester) async {
      final repository = _FakeRuntimeAgentStateRepository(
        RuntimeAgentState.fromJson(const {
          'vault_id': 'uid_1',
          'conversation_id': 'loop_home',
          'conversation_turns': [],
          'working_set_records': [],
          'tasks': [],
          'memory_records': [],
          'recurring_reminder_rules': [],
          'approval_items': [],
          'recent_entity_refs': [],
          'latest_context_snapshot': {
            'id': 'context-snapshot-1',
            'generated_at_ms': 1700000000000,
            'packet': {
              'conversation_id': 'loop_home',
              'working_set': {'records': []},
              'memory_records': [
                {
                  'id': 'memory-focus-time',
                  'kind': 'memory',
                  'text': '下午 4 点后再安排深度会议',
                  'state': 'active',
                }
              ],
            },
          },
          'audit_refs': [],
        }),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: CloudAuthScope(
              controller: _CloudAuthController(),
              gatewayConfig: const CloudGatewayConfig(
                baseUrl: 'https://gateway.example.test',
                modelName: 'cloud',
              ),
              child: MemoryPage(runtimeAgentStateRepository: repository),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.requests, [('uid_1', 'loop_home')]);
      expect(find.text('下午 4 点后再安排深度会议'), findsWidgets);
      expect(find.text('No knowledge pages yet.'), findsNothing);
    },
  );
}

final class _FakeRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  _FakeRuntimeAgentStateRepository(this.state);

  final RuntimeAgentState state;
  final List<(String, String)> requests = <(String, String)>[];

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    requests.add((vaultId, conversationId));
    return state;
  }
}

final class _CloudAuthController implements CloudAuthController {
  @override
  String? get uid => 'uid_1';

  @override
  String? get email => 'qa@example.com';

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
