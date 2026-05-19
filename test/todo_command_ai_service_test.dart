import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/secretary/todo_command_ai_service.dart';
import 'package:secondloop/core/secretary/todo_command_models.dart';

void main() {
  group('TodoCommandAiService', () {
    test('builds structured prompt and parses valid command', () async {
      final client = _PromptClient(
        responseJson: jsonEncode({
          'kind': 'update_title',
          'confidence': 0.91,
          'target_todo_id': 'todo-1',
          'new_title': 'Submit Stripe invoice',
          'requires_confirmation': true,
        }),
      );
      final service = TodoCommandAiService(promptClient: client);

      final command = await service.parseTodoCommand(
        text: 'Rename invoice',
        nowLocal: DateTime(2026, 5, 4, 9),
        localeTag: 'en-US',
        candidates: const [
          TodoCommandAiCandidate(
            id: 'todo-1',
            title: 'invoice',
            status: 'open',
          ),
        ],
        route: TodoCommandAiRoute.cloud,
        sourceMessageId: 'message-1',
      );

      expect(command?.kind, SecretaryTodoCommandKind.updateTitle);
      expect(command?.targetTodoId, 'todo-1');
      expect(command?.newTitle, 'Submit Stripe invoice');
      expect(client.lastPrompt, contains('"purpose":"semantic_parse"'));
      expect(client.lastPrompt, contains('"task":"parse_todo_command"'));
      expect(client.lastPrompt,
          contains('"Only choose target ids from provided candidates."'));
    });

    test('rejects command target ids outside provided candidates', () async {
      final client = _PromptClient(
        responseJson: jsonEncode({
          'kind': 'reschedule',
          'confidence': 0.92,
          'target_todo_id': 'todo-missing',
          'due_local_iso': '2026-05-08T15:00:00',
        }),
      );
      final service = TodoCommandAiService(promptClient: client);

      final command = await service.parseTodoCommand(
        text: 'Move invoice to Friday',
        nowLocal: DateTime(2026, 5, 4, 9),
        localeTag: 'en-US',
        candidates: const [
          TodoCommandAiCandidate(
            id: 'todo-1',
            title: 'invoice',
            status: 'open',
          ),
        ],
        route: TodoCommandAiRoute.cloud,
        sourceMessageId: 'message-1',
      );

      expect(command, isNull);
    });
  });
}

final class _PromptClient implements TodoCommandAiPromptClient {
  _PromptClient({required this.responseJson});

  final String responseJson;
  String? lastPrompt;

  @override
  Future<String> runTodoCommandPrompt({
    required String prompt,
    required TodoCommandAiRoute route,
  }) async {
    lastPrompt = prompt;
    return responseJson;
  }
}
