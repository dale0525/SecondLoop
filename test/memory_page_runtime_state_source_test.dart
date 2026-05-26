import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_models.dart';
import 'package:secondloop/core/cloud/runtime_agent_state_repository.dart';
import 'package:secondloop/core/cloud/runtime_connection_store.dart';
import 'package:secondloop/core/cloud/runtime_manifest.dart';
import 'package:secondloop/core/cloud/runtime_profile.dart';
import 'package:secondloop/features/memory/memory_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RuntimeConnectionStore.resetCacheForTests();
  });

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
    'self-managed MemoryPage reads approved memories from saved runtime state',
    (tester) async {
      await RuntimeConnectionStore().saveConnection(
        _selfManagedConnection(vaultId: 'CF_D1_PRIMARY_VAULT_APP_QA'),
      );
      final repository = _FakeRuntimeAgentStateRepository(
        RuntimeAgentState.fromJson(const {
          'vault_id': 'CF_D1_PRIMARY_VAULT_APP_QA',
          'conversation_id': 'loop_home',
          'conversation_turns': [],
          'working_set_records': [],
          'tasks': [],
          'memory_records': [
            {
              'id': 'memory-meeting',
              'kind': 'memory',
              'title': '我上午 9 点前不开会',
              'text': '我上午 9 点前不开会',
              'state': 'active',
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
            home: MemoryPage(runtimeAgentStateRepository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
          repository.requests, [('CF_D1_PRIMARY_VAULT_APP_QA', 'loop_home')]);
      expect(find.text('我上午 9 点前不开会'), findsWidgets);
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

CloudRuntimeConnection _selfManagedConnection({required String vaultId}) {
  return CloudRuntimeConnection(
    profile: CloudRuntimeProfile(
      runtimeMode: CloudRuntimeMode.selfManaged,
      apiBaseUrl: 'https://user-runtime.example/',
      authMode: CloudRuntimeAuthMode.runtimeToken,
      authToken: 'runtime-token',
      capabilityManifestId: 'manifest-self-1',
      manifestVersion: 1,
      vaultId: vaultId,
    ),
    manifest: const CloudRuntimeManifest(
      manifestVersion: 1,
      runtimeMode: CloudRuntimeMode.selfManaged,
      apiBaseUrl: 'https://user-runtime.example/',
      authMode: CloudRuntimeAuthMode.runtimeToken,
      capabilities: [CloudRuntimeCapability('chat')],
    ),
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
