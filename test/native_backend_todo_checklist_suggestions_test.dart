import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('NativeAppBackend checklist suggestion methods forward args', () async {
    String? capturedTodoIdForList;
    List<String>? capturedSuggestionIdsForApply;
    List<String>? capturedSuggestionIdsForDismiss;
    String? capturedTodoIdForDismissAll;

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      rustLibInit: () async {},
      dbListTodoChecklistSuggestions: ({
        required String appDir,
        required List<int> key,
        required String todoId,
      }) async {
        capturedTodoIdForList = todoId;
        return const <TodoChecklistSuggestion>[
          TodoChecklistSuggestion(
            id: 's1',
            todoId: 'todo_1',
            content: 'Draft launch post',
            sortOrder: 0,
            state: 'pending',
            source: 'cloud',
            generationKey: 'gen_1',
            createdAtMs: 1,
            updatedAtMs: 1,
            dismissedAtMs: null,
            appliedChecklistItemId: null,
          ),
        ];
      },
      dbApplyTodoChecklistSuggestions: ({
        required String appDir,
        required List<int> key,
        required String todoId,
        required List<String> suggestionIds,
      }) async {
        capturedSuggestionIdsForApply = List<String>.from(suggestionIds);
        return const <TodoChecklistItem>[];
      },
      dbDismissTodoChecklistSuggestions: ({
        required String appDir,
        required List<int> key,
        required String todoId,
        required List<String> suggestionIds,
      }) async {
        capturedSuggestionIdsForDismiss = List<String>.from(suggestionIds);
      },
      dbDismissAllTodoChecklistSuggestions: ({
        required String appDir,
        required List<int> key,
        required String todoId,
      }) async {
        capturedTodoIdForDismissAll = todoId;
      },
    );

    final key = Uint8List.fromList(List<int>.filled(32, 8));
    final suggestions =
        await backend.listTodoChecklistSuggestions(key, 'todo_1');
    await backend.applyTodoChecklistSuggestions(
      key,
      todoId: 'todo_1',
      suggestionIds: const <String>['s1'],
    );
    await backend.dismissTodoChecklistSuggestions(
      key,
      todoId: 'todo_1',
      suggestionIds: const <String>['s1'],
    );
    await backend.dismissAllTodoChecklistSuggestions(
      key,
      todoId: 'todo_1',
    );

    expect(capturedTodoIdForList, 'todo_1');
    expect(capturedSuggestionIdsForApply, const <String>['s1']);
    expect(capturedSuggestionIdsForDismiss, const <String>['s1']);
    expect(capturedTodoIdForDismissAll, 'todo_1');
    expect(suggestions.single.state, 'pending');
  });
}
