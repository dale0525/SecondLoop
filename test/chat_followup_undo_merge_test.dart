import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('followup undo preserves concurrent todo title edits',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ask_ai_data_consent_v1': false,
      'semantic_parse_data_consent_v1': false,
    });

    final backend = _Backend(
      todos: <Todo>[
        const Todo(
          id: 'todo:1',
          title: '报销',
          dueAtMs: 1200,
          status: 'open',
          sourceEntryId: 'seed',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          home: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: AppBackendScope(
              backend: backend,
              child: const ChatPage(
                conversation: Conversation(
                  id: 'loop_home',
                  title: 'Loop',
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('chat_input')), '把报销改到明天');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_send')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(SnackBarAction), findsOneWidget);
    expect(backend.todoById('todo:1')!.dueAtMs?.toInt(), isNot(1200));

    backend.renameTodo('todo:1', '报销-已重命名');

    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pumpAndSettle();

    final restored = backend.todoById('todo:1')!;
    expect(backend.transitionCalls, 2);
    expect(restored.title, '报销-已重命名');
    expect(restored.dueAtMs?.toInt(), 1200);
  });

  testWidgets(
      'followup apply uses atomic transition for combined status and due',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ask_ai_data_consent_v1': false,
      'semantic_parse_data_consent_v1': false,
    });

    final backend = _Backend(
      todos: <Todo>[
        const Todo(
          id: 'todo:1',
          title: '报销',
          dueAtMs: 1200,
          status: 'open',
          sourceEntryId: 'seed',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );
    backend.failNonAtomicFollowupApis = true;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          home: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: AppBackendScope(
              backend: backend,
              child: const ChatPage(
                conversation: Conversation(
                  id: 'loop_home',
                  title: 'Loop',
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('chat_input')),
      '把报销完成并改到明天',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_send')));
    await tester.pump();
    await tester.pumpAndSettle();

    final updated = backend.todoById('todo:1')!;
    expect(backend.transitionCalls, 1);
    expect(updated.status, 'done');
    expect(updated.dueAtMs?.toInt(), isNot(1200));
  });
}

final class _Backend extends TestAppBackend {
  _Backend({required List<Todo> todos}) : _todos = List<Todo>.from(todos);

  final List<Todo> _todos;
  bool failNonAtomicFollowupApis = false;
  int transitionCalls = 0;

  Todo? todoById(String id) {
    for (final todo in _todos) {
      if (todo.id == id) return todo;
    }
    return null;
  }

  void renameTodo(String id, String title) {
    for (var i = 0; i < _todos.length; i++) {
      final todo = _todos[i];
      if (todo.id != id) continue;
      _todos[i] = Todo(
        id: todo.id,
        title: title,
        dueAtMs: todo.dueAtMs,
        status: todo.status,
        sourceEntryId: todo.sourceEntryId,
        createdAtMs: todo.createdAtMs,
        updatedAtMs: todo.updatedAtMs,
        reviewStage: todo.reviewStage,
        nextReviewAtMs: todo.nextReviewAtMs,
        lastReviewAtMs: todo.lastReviewAtMs,
        manualImportanceNudgeScore: todo.manualImportanceNudgeScore,
        manualUrgencyNudgeScore: todo.manualUrgencyNudgeScore,
      );
      return;
    }
  }

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(_todos);

  @override
  Future<Todo> updateTodoDueWithScope(
    Uint8List key, {
    required String todoId,
    required int dueAtMs,
    required TodoRecurrenceEditScope scope,
  }) async {
    if (failNonAtomicFollowupApis) {
      throw StateError('non_atomic_due_api_should_not_be_used');
    }
    for (var i = 0; i < _todos.length; i++) {
      final todo = _todos[i];
      if (todo.id != todoId) continue;
      final updated = Todo(
        id: todo.id,
        title: todo.title,
        dueAtMs: dueAtMs,
        status: todo.status,
        sourceEntryId: todo.sourceEntryId,
        createdAtMs: todo.createdAtMs,
        updatedAtMs: todo.updatedAtMs,
        reviewStage: todo.reviewStage,
        nextReviewAtMs: todo.nextReviewAtMs,
        lastReviewAtMs: todo.lastReviewAtMs,
        manualImportanceNudgeScore: todo.manualImportanceNudgeScore,
        manualUrgencyNudgeScore: todo.manualUrgencyNudgeScore,
      );
      _todos[i] = updated;
      return updated;
    }
    throw StateError('todo not found: $todoId');
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    if (failNonAtomicFollowupApis) {
      throw StateError('non_atomic_status_api_should_not_be_used');
    }
    for (var i = 0; i < _todos.length; i++) {
      final todo = _todos[i];
      if (todo.id != todoId) continue;
      final updated = Todo(
        id: todo.id,
        title: todo.title,
        dueAtMs: todo.dueAtMs,
        status: newStatus,
        sourceEntryId: todo.sourceEntryId,
        createdAtMs: todo.createdAtMs,
        updatedAtMs: todo.updatedAtMs,
        reviewStage: todo.reviewStage,
        nextReviewAtMs: todo.nextReviewAtMs,
        lastReviewAtMs: todo.lastReviewAtMs,
        manualImportanceNudgeScore: todo.manualImportanceNudgeScore,
        manualUrgencyNudgeScore: todo.manualUrgencyNudgeScore,
      );
      _todos[i] = updated;
      return updated;
    }
    throw StateError('todo not found: $todoId');
  }

  @override
  Future<Todo> transitionTodo(
    Uint8List key, {
    required String todoId,
    String? newStatus,
    int? dueAtMs,
    bool clearDueAtMs = false,
    int? reviewStage,
    bool clearReviewStage = false,
    int? nextReviewAtMs,
    bool clearNextReviewAtMs = false,
    int? lastReviewAtMs,
    bool clearLastReviewAtMs = false,
    int? manualImportanceNudgeScore,
    bool clearManualImportanceNudgeScore = false,
    int? manualUrgencyNudgeScore,
    bool clearManualUrgencyNudgeScore = false,
    String? sourceMessageId,
  }) async {
    transitionCalls += 1;
    for (var i = 0; i < _todos.length; i++) {
      final todo = _todos[i];
      if (todo.id != todoId) continue;
      final updated = Todo(
        id: todo.id,
        title: todo.title,
        dueAtMs: clearDueAtMs ? null : (dueAtMs ?? todo.dueAtMs?.toInt()),
        status: newStatus ?? todo.status,
        sourceEntryId: todo.sourceEntryId,
        createdAtMs: todo.createdAtMs,
        updatedAtMs: todo.updatedAtMs,
        reviewStage: clearReviewStage ? null : reviewStage ?? todo.reviewStage,
        nextReviewAtMs:
            clearNextReviewAtMs ? null : nextReviewAtMs ?? todo.nextReviewAtMs,
        lastReviewAtMs:
            clearLastReviewAtMs ? null : lastReviewAtMs ?? todo.lastReviewAtMs,
        manualImportanceNudgeScore: clearManualImportanceNudgeScore
            ? null
            : manualImportanceNudgeScore ?? todo.manualImportanceNudgeScore,
        manualUrgencyNudgeScore: clearManualUrgencyNudgeScore
            ? null
            : manualUrgencyNudgeScore ?? todo.manualUrgencyNudgeScore,
      );
      _todos[i] = updated;
      return updated;
    }
    throw StateError('todo not found: $todoId');
  }

  @override
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
  }) async {
    for (var i = 0; i < _todos.length; i++) {
      final todo = _todos[i];
      if (todo.id != id) continue;
      final updated = Todo(
        id: id,
        title: title,
        dueAtMs: dueAtMs,
        status: status,
        sourceEntryId: sourceEntryId,
        createdAtMs: todo.createdAtMs,
        updatedAtMs: todo.updatedAtMs,
        reviewStage: reviewStage,
        nextReviewAtMs: nextReviewAtMs,
        lastReviewAtMs: lastReviewAtMs,
        manualImportanceNudgeScore: manualImportanceNudgeScore,
        manualUrgencyNudgeScore: manualUrgencyNudgeScore,
      );
      _todos[i] = updated;
      return updated;
    }
    throw StateError('todo not found: $id');
  }

  @override
  Future<TodoActivity> appendTodoNote(
    Uint8List key, {
    required String todoId,
    required String content,
    String? sourceMessageId,
  }) async {
    return TodoActivity(
      id: 'activity:$todoId',
      todoId: todoId,
      activityType: 'note',
      content: content,
      createdAtMs: 0,
      sourceMessageId: sourceMessageId,
    );
  }
}
