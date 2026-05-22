import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_models.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_repository.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/agent_ui/agent_task_summary.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
    'managed pro AgentTasksPage reads tasks from runtime state',
    (tester) async {
      final repository = _FakeRuntimeAgentStateRepository(
        RuntimeAgentState.fromJson(const {
          'vault_id': 'uid_1',
          'conversation_id': 'loop_home',
          'conversation_turns': [],
          'working_set_records': [],
          'tasks': [
            {
              'id': 'task-weekly',
              'kind': 'task',
              'title': '完成周报',
              'status': 'open',
            }
          ],
          'memory_records': [],
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
            home: AppBackendScope(
              backend: _ThrowingTodoBackend(),
              child: CloudAuthScope(
                controller: _CloudAuthController(),
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://gateway.example.test',
                  modelName: 'cloud',
                ),
                child: SessionScope(
                  sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                  lock: () {},
                  child: AgentTasksPage(
                    runtimeAgentStateRepository: repository,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.requests, [('uid_1', 'loop_home')]);
      expect(find.text('完成周报'), findsOneWidget);
      expect(find.text('No open tasks yet.'), findsNothing);
    },
  );

  testWidgets(
    'managed pro AgentTasksPage reads approved recurring reminder rules from runtime state',
    (tester) async {
      final repository = _FakeRuntimeAgentStateRepository(
        RuntimeAgentState.fromJson(const {
          'vault_id': 'uid_1',
          'conversation_id': 'loop_home',
          'conversation_turns': [],
          'working_set_records': [],
          'tasks': [],
          'memory_records': [],
          'recurring_reminder_rules': [
            {
              'id': 'recurring-child-birthday-gift',
              'kind': 'recurring_reminder_rule',
              'title': '给孩子买生日礼物',
              'status': 'active',
              'approval_status': 'approved',
              'next_fire_at_ms': 1780185600000,
            }
          ],
          'approval_items': [],
          'recent_entity_refs': [],
          'latest_context_snapshot': null,
          'audit_refs': [],
        }),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: _ThrowingTodoBackend(),
              child: CloudAuthScope(
                controller: _CloudAuthController(),
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://gateway.example.test',
                  modelName: 'cloud',
                ),
                child: SessionScope(
                  sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                  lock: () {},
                  child: AgentTasksPage(
                    runtimeAgentStateRepository: repository,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.requests, [('uid_1', 'loop_home')]);
      expect(find.text('给孩子买生日礼物'), findsOneWidget);
      expect(find.text('No open tasks yet.'), findsNothing);
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

final class _ThrowingTodoBackend extends TestAppBackend {
  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    throw StateError('listTodos should not be used');
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
