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
    'managed pro conversation prepends older runtime turns without duplicates',
    (tester) async {
      final repository = _PagedRuntimeAgentStateRepository(
        latestPage: _runtimeStateWithTurns(
          turns: const [
            {
              'turn_id': 'turn-newest-page-start',
              'role': 'assistant',
              'content': 'Newest runtime answer.',
              'created_at_ms': 1700000002000,
            },
          ],
          page: const {
            'limit': 1,
            'has_more_before': true,
            'next_before_turn_id': 'turn-newest-page-start',
            'oldest_turn_id': 'turn-newest-page-start',
            'newest_turn_id': 'turn-newest-page-start',
            'total_known_turns': 2,
          },
        ),
        olderPage: _runtimeStateWithTurns(
          turns: const [
            {
              'turn_id': 'turn-older',
              'role': 'user',
              'content': 'Older runtime question.',
              'created_at_ms': 1700000001000,
            },
            {
              'turn_id': 'turn-newest-page-start',
              'role': 'assistant',
              'content': 'Newest runtime answer.',
              'created_at_ms': 1700000002000,
            },
          ],
          page: const {
            'limit': 2,
            'has_more_before': false,
            'next_before_turn_id': null,
            'oldest_turn_id': 'turn-older',
            'newest_turn_id': 'turn-newest-page-start',
            'total_known_turns': 2,
          },
        ),
      );

      await _pumpRuntimeConversation(tester, repository);

      final chatColumn =
          find.byKey(const ValueKey('desktop_workbench_chat_column'));
      final newestRuntimeAnswer = find.descendant(
        of: chatColumn,
        matching: find.text('Newest runtime answer.'),
      );
      final olderRuntimeQuestion = find.descendant(
        of: chatColumn,
        matching: find.text('Older runtime question.'),
      );

      expect(newestRuntimeAnswer, findsOneWidget);
      expect(olderRuntimeQuestion, findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('agent_conversation_load_older_turns')),
      );
      await tester.pumpAndSettle();

      expect(repository.requests.last.turnBefore, 'turn-newest-page-start');
      expect(olderRuntimeQuestion, findsOneWidget);
      expect(newestRuntimeAnswer, findsOneWidget);
      expect(
        tester.getTopLeft(olderRuntimeQuestion).dy,
        lessThan(tester.getTopLeft(newestRuntimeAnswer).dy),
      );
    },
  );

  testWidgets(
    'operating shell prepends older runtime turns',
    (tester) async {
      final repository = _PagedRuntimeAgentStateRepository(
        latestPage: _runtimeStateWithTurns(
          turns: const [
            {
              'turn_id': 'turn-newest-page-start',
              'role': 'assistant',
              'content': 'Newest operating answer.',
              'created_at_ms': 1700000002000,
            },
          ],
          page: const {
            'limit': 1,
            'has_more_before': true,
            'next_before_turn_id': 'turn-newest-page-start',
            'oldest_turn_id': 'turn-newest-page-start',
            'newest_turn_id': 'turn-newest-page-start',
            'total_known_turns': 2,
          },
        ),
        olderPage: _runtimeStateWithTurns(
          turns: const [
            {
              'turn_id': 'turn-older',
              'role': 'user',
              'content': 'Older operating question.',
              'created_at_ms': 1700000001000,
            },
            {
              'turn_id': 'turn-newest-page-start',
              'role': 'assistant',
              'content': 'Newest operating answer.',
              'created_at_ms': 1700000002000,
            },
          ],
          page: const {
            'limit': 2,
            'has_more_before': false,
            'next_before_turn_id': null,
            'oldest_turn_id': 'turn-older',
            'newest_turn_id': 'turn-newest-page-start',
            'total_known_turns': 2,
          },
        ),
      );

      await _pumpRuntimeConversation(
        tester,
        repository,
        surfaceSize: const Size(820, 701),
      );

      expect(find.text('Newest operating answer.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('agent_conversation_load_older_turns')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('agent_conversation_load_older_turns')),
      );
      await tester.pumpAndSettle();

      expect(repository.requests.last.turnBefore, 'turn-newest-page-start');
      expect(find.text('Older operating question.'), findsOneWidget);
      expect(find.text('Newest operating answer.'), findsOneWidget);
    },
  );
}

Future<void> _pumpRuntimeConversation(
  WidgetTester tester,
  RuntimeAgentStateRepository repository, {
  Size surfaceSize = const Size(1012, 701),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
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
}

RuntimeAgentState _runtimeStateWithTurns({
  required List<Map<String, Object?>> turns,
  required Map<String, Object?> page,
}) {
  return RuntimeAgentState.fromJson({
    'vault_id': 'uid_1',
    'conversation_id': 'loop_home',
    'conversation_turns': [
      for (final turn in turns)
        {
          'conversation_id': 'loop_home',
          'vault_id': 'uid_1',
          ...turn,
        },
    ],
    'conversation_turn_page': page,
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

typedef _RuntimeAgentStateRequest = ({
  String vaultId,
  String conversationId,
  int? turnLimit,
  String? turnBefore,
  String? turnOrder,
});

final class _PagedRuntimeAgentStateRepository
    implements RuntimeAgentStateRepository {
  _PagedRuntimeAgentStateRepository({
    required this.latestPage,
    required this.olderPage,
  });

  final RuntimeAgentState latestPage;
  final RuntimeAgentState olderPage;
  final List<_RuntimeAgentStateRequest> requests =
      <_RuntimeAgentStateRequest>[];

  @override
  Future<RuntimeAgentState> fetchAgentState({
    required String vaultId,
    required String conversationId,
    int? turnLimit,
    String? turnBefore,
    String? turnOrder,
  }) async {
    requests.add((
      vaultId: vaultId,
      conversationId: conversationId,
      turnLimit: turnLimit,
      turnBefore: turnBefore,
      turnOrder: turnOrder,
    ));
    return turnBefore == 'turn-newest-page-start' ? olderPage : latestPage;
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
