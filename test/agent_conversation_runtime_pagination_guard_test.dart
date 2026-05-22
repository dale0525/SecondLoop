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
import 'package:secondloop/features/agent_ui/agent_conversation_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
    'managed pro conversation renders latest page for 10k-turn runtime state',
    (tester) async {
      final allTurns = List<Map<String, Object?>>.generate(10000, (index) {
        final turnNumber = index + 1;
        return {
          'turn_id': 'turn-$turnNumber',
          'conversation_id': 'loop_home',
          'vault_id': 'uid_1',
          'role': turnNumber.isOdd ? 'user' : 'assistant',
          'content': 'Runtime guard turn $turnNumber',
          'created_at_ms': 1700000000000 + index,
        };
      });
      final repository = _PagedRuntimeAgentStateRepository(allTurns);

      await tester.binding.setSurfaceSize(const Size(1012, 701));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: TestAppBackend(),
              child: CloudAuthScope(
                controller: _CloudAuthController(),
                gatewayConfig: const CloudGatewayConfig(
                  baseUrl: 'https://gateway.example.test',
                  modelName: 'cloud',
                ),
                child: SessionScope(
                  sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                  lock: () {},
                  child: AgentConversationPage(
                    conversation: const Conversation(
                      id: 'loop_home',
                      title: 'Loop',
                      createdAtMs: 0,
                      updatedAtMs: 0,
                    ),
                    isTabActive: true,
                    runtimeAgentStateRepository: repository,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.allTurns, hasLength(10000));
      expect(repository.fetchRequests.single.vaultId, 'uid_1');
      expect(repository.fetchRequests.single.conversationId, 'loop_home');
      expect(repository.fetchRequests.single.turnLimit, isNull);
      expect(repository.fetchRequests.single.turnBefore, isNull);
      expect(repository.fetchRequests.single.turnOrder, isNull);
      expect(repository.servedTurnIds.single, hasLength(80));
      expect(repository.servedTurnIds.single.first, 'turn-9921');
      expect(repository.servedTurnIds.single.last, 'turn-10000');
      expect(repository.servedTurnIds.single, isNot(contains('turn-9920')));
      expect(
        find.byKey(const ValueKey('agent_conversation_load_older_turns')),
        findsOneWidget,
      );
      expect(find.textContaining('Runtime guard turn '), findsWidgets);
      expect(
        find.textContaining('Runtime guard turn ').evaluate().length,
        lessThanOrEqualTo(80),
      );
      expect(find.text('Runtime guard turn 1'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('agent_conversation_load_older_turns')),
      );
      await tester.pumpAndSettle();

      expect(repository.fetchRequests, hasLength(2));
      expect(repository.fetchRequests.last.turnBefore, 'turn-9921');
      expect(repository.servedTurnIds.last, hasLength(80));
      expect(repository.servedTurnIds.last.first, 'turn-9841');
      expect(repository.servedTurnIds.last.last, 'turn-9920');
    },
  );
}

typedef _RuntimeAgentStateRequest = ({
  String vaultId,
  String conversationId,
  int? turnLimit,
  String? turnBefore,
  String? turnOrder,
});

final class _PagedRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  _PagedRuntimeAgentStateRepository(this.allTurns);

  final List<Map<String, Object?>> allTurns;
  final List<_RuntimeAgentStateRequest> fetchRequests =
      <_RuntimeAgentStateRequest>[];
  final List<List<String>> servedTurnIds = <List<String>>[];

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    fetchRequests.add((
      vaultId: vaultId,
      conversationId: conversationId,
      turnLimit: turnLimit,
      turnBefore: turnBefore,
      turnOrder: turnOrder,
    ));
    const limit = 80;
    final before = turnBefore?.trim() ?? '';
    final beforeIndex = before.isEmpty
        ? allTurns.length
        : allTurns.indexWhere((turn) => turn['turn_id'] == before);
    final end = beforeIndex < 0 ? allTurns.length : beforeIndex;
    final start = end > limit ? end - limit : 0;
    final pageTurns = allTurns.sublist(start, end);
    servedTurnIds.add(
      pageTurns.map((turn) => '${turn['turn_id']}').toList(growable: false),
    );

    return RuntimeAgentState.fromJson({
      'vault_id': vaultId,
      'conversation_id': conversationId,
      'conversation_turns': pageTurns,
      'conversation_turn_page': {
        'limit': limit,
        'has_more_before': start > 0,
        'next_before_turn_id': start > 0 ? pageTurns.first['turn_id'] : null,
        'oldest_turn_id': pageTurns.isEmpty ? null : pageTurns.first['turn_id'],
        'newest_turn_id': pageTurns.isEmpty ? null : pageTurns.last['turn_id'],
        'total_known_turns': allTurns.length,
      },
      'working_set_records': const <Map<String, Object?>>[],
      'tasks': const <Map<String, Object?>>[],
      'memory_records': const <Map<String, Object?>>[],
      'recurring_reminder_rules': const <Map<String, Object?>>[],
      'approval_items': const <Map<String, Object?>>[],
      'recent_entity_refs': const <Map<String, Object?>>[],
      'latest_context_snapshot': null,
      'audit_refs': const <Map<String, Object?>>[],
    });
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
