import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('NativeAppBackend followup suggestion methods forward args', () async {
    String? capturedTodoIdForList;
    List<String>? capturedSuggestionIdsForApply;
    List<String>? capturedSuggestionIdsForDismiss;
    String? capturedTodoIdForDismissAll;
    String? capturedTodoIdForEnqueueJob;

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      rustLibInit: () async {},
      dbListTodoFollowupSuggestions: ({
        required String appDir,
        required List<int> key,
        required String todoId,
      }) async {
        capturedTodoIdForList = todoId;
        return const <TodoFollowupSuggestion>[
          TodoFollowupSuggestion(
            id: 'f1',
            todoId: 'todo_1',
            content:
                '## Summary\nClaude / GPT / Gemini are still the main hosted options.',
            state: 'pending',
            source: 'cloud',
            generationMode: 'model_knowledge',
            generationKey: 'gen_1',
            citationsJson: null,
            createdAtMs: 1,
            updatedAtMs: 1,
            dismissedAtMs: null,
            appliedActivityId: null,
          ),
        ];
      },
      dbApplyTodoFollowupSuggestions: ({
        required String appDir,
        required List<int> key,
        required String todoId,
        required List<String> suggestionIds,
      }) async {
        capturedSuggestionIdsForApply = List<String>.from(suggestionIds);
        return const <TodoActivity>[];
      },
      dbDismissTodoFollowupSuggestions: ({
        required String appDir,
        required List<int> key,
        required String todoId,
        required List<String> suggestionIds,
      }) async {
        capturedSuggestionIdsForDismiss = List<String>.from(suggestionIds);
      },
      dbDismissAllTodoFollowupSuggestions: ({
        required String appDir,
        required List<int> key,
        required String todoId,
      }) async {
        capturedTodoIdForDismissAll = todoId;
      },
      dbEnqueueTodoFollowupGenerationJob: ({
        required String appDir,
        required List<int> key,
        required String todoId,
        required String triggerKind,
        String? taskTypeHint,
        required int nowMs,
      }) async {
        capturedTodoIdForEnqueueJob = todoId;
      },
    );

    final key = Uint8List.fromList(List<int>.filled(32, 8));
    final suggestions =
        await backend.listTodoFollowupSuggestions(key, 'todo_1');
    await backend.applyTodoFollowupSuggestions(
      key,
      todoId: 'todo_1',
      suggestionIds: const <String>['f1'],
    );
    await backend.dismissTodoFollowupSuggestions(
      key,
      todoId: 'todo_1',
      suggestionIds: const <String>['f1'],
    );
    await backend.dismissAllTodoFollowupSuggestions(key, todoId: 'todo_1');
    await backend.enqueueTodoFollowupGenerationJob(
      key,
      todoId: 'todo_1',
      triggerKind: 'manual_regenerate',
      nowMs: 123,
    );

    expect(capturedTodoIdForList, 'todo_1');
    expect(capturedSuggestionIdsForApply, const <String>['f1']);
    expect(capturedSuggestionIdsForDismiss, const <String>['f1']);
    expect(capturedTodoIdForDismissAll, 'todo_1');
    expect(capturedTodoIdForEnqueueJob, 'todo_1');
    expect(suggestions.single.generationMode, 'model_knowledge');
  });

  test('NativeAppBackend getTodoFollowupGenerationJob forwards args', () async {
    String? capturedTodoId;

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      rustLibInit: () async {},
      dbGetTodoFollowupGenerationJob: ({
        required String appDir,
        required List<int> key,
        required String todoId,
      }) async {
        capturedTodoId = todoId;
        return const TodoFollowupGenerationJob(
          todoId: 'todo_1',
          triggerKind: 'auto_create',
          status: 'running',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'research',
          createdAtMs: 1,
          updatedAtMs: 1,
        );
      },
    );

    final key = Uint8List.fromList(List<int>.filled(32, 8));
    final job = await backend.getTodoFollowupGenerationJob(key, 'todo_1');

    expect(capturedTodoId, 'todo_1');
    expect(job?.todoId, 'todo_1');
    expect(job?.status, 'running');
  });

  test('NativeAppBackend getTodoById forwards args', () async {
    String? capturedTodoId;

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      rustLibInit: () async {},
      dbGetTodoById: ({
        required String appDir,
        required List<int> key,
        required String todoId,
      }) async {
        capturedTodoId = todoId;
        return const Todo(
          id: 'todo_1',
          title: 'Research LLM models',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 1,
          updatedAtMs: 1,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        );
      },
    );

    final key = Uint8List.fromList(List<int>.filled(32, 8));
    final todo = await backend.getTodoById(key, 'todo_1');

    expect(capturedTodoId, 'todo_1');
    expect(todo?.id, 'todo_1');
  });
}
