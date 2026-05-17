import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/secretary/todo_command_executor.dart';
import 'package:secondloop/core/secretary/todo_command_models.dart';
import 'package:secondloop/features/secretary/todo_command_review_page.dart';
import 'package:secondloop/core/models/app_models.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('review page applies command through TodoCommandExecutor',
      (tester) async {
    final backend = _TodoCommandBackend(
      _todo(id: 'todo:invoice', title: 'Submit invoice'),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: TodoCommandReviewPage(
            commands: [_renameCommand()],
            executor: TodoCommandExecutor(
              backend: backend,
              sessionKey: Uint8List(32),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('todo_command_review_apply_cmd-rename')),
    );
    await tester.pumpAndSettle();

    expect(backend.current.title, 'Submit Stripe invoice');
    expect(backend.upsertTodoCalls, 1);
    expect(find.text('Todo change applied.'), findsOneWidget);
  });

  testWidgets('ignoring delete command does not mutate the todo',
      (tester) async {
    final backend = _TodoCommandBackend(
      _todo(id: 'todo:invoice', title: 'Submit invoice'),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: TodoCommandReviewPage(
            commands: [_deleteCommand()],
            executor: TodoCommandExecutor(
              backend: backend,
              sessionKey: Uint8List(32),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('todo_command_review_ignore_cmd-delete')),
    );
    await tester.pumpAndSettle();

    expect(backend.current.status, 'open');
    expect(backend.transitionTodoCalls, 0);
    expect(find.text('Todo change ignored.'), findsOneWidget);
  });

  testWidgets('explicit confirm applies delete command', (tester) async {
    final backend = _TodoCommandBackend(
      _todo(id: 'todo:invoice', title: 'Submit invoice'),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: TodoCommandReviewPage(
            commands: [_deleteCommand()],
            executor: TodoCommandExecutor(
              backend: backend,
              sessionKey: Uint8List(32),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('todo_command_review_confirm_cmd-delete')),
    );
    await tester.pumpAndSettle();

    expect(backend.current.status, 'dismissed');
    expect(backend.transitionTodoCalls, 1);
  });

  testWidgets('edit action invokes callback without mutating the todo',
      (tester) async {
    final backend = _TodoCommandBackend(
      _todo(id: 'todo:invoice', title: 'Submit invoice'),
    );
    SecretaryTodoCommand? edited;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: TodoCommandReviewPage(
            commands: [_renameCommand()],
            executor: TodoCommandExecutor(
              backend: backend,
              sessionKey: Uint8List(32),
            ),
            onEdit: (command) => edited = command,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('todo_command_review_edit_cmd-rename')),
    );
    await tester.pumpAndSettle();

    expect(edited?.id, 'cmd-rename');
    expect(backend.current.title, 'Submit invoice');
    expect(backend.upsertTodoCalls, 0);
  });

  testWidgets('cancel closes review page without mutating the todo',
      (tester) async {
    final backend = _TodoCommandBackend(
      _todo(id: 'todo:invoice', title: 'Submit invoice'),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  key: const ValueKey('open_review'),
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => TodoCommandReviewPage(
                          commands: [_renameCommand()],
                          executor: TodoCommandExecutor(
                            backend: backend,
                            sessionKey: Uint8List(32),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open review'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open_review')));
    await tester.pumpAndSettle();
    expect(find.text('Todo changes'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo_command_review_cancel')));
    await tester.pumpAndSettle();

    expect(find.text('Open review'), findsOneWidget);
    expect(backend.current.title, 'Submit invoice');
    expect(backend.upsertTodoCalls, 0);
  });
}

SecretaryTodoCommand _renameCommand() {
  return const SecretaryTodoCommand(
    id: 'cmd-rename',
    kind: SecretaryTodoCommandKind.updateTitle,
    route: SecretaryTodoCommandRoute.local,
    confidence: 0.93,
    sourceMessageId: 'm1',
    targetTodoId: 'todo:invoice',
    targetTitle: 'Submit invoice',
    newTitle: 'Submit Stripe invoice',
  );
}

SecretaryTodoCommand _deleteCommand() {
  return const SecretaryTodoCommand(
    id: 'cmd-delete',
    kind: SecretaryTodoCommandKind.dismiss,
    route: SecretaryTodoCommandRoute.local,
    confidence: 0.93,
    sourceMessageId: 'm2',
    targetTodoId: 'todo:invoice',
    targetTitle: 'Submit invoice',
  );
}

Todo _todo({
  required String id,
  required String title,
  String status = 'open',
}) {
  return Todo(
    id: id,
    title: title,
    status: status,
    createdAtMs: 10,
    updatedAtMs: 10,
    sourceEntryId: null,
    dueAtMs: null,
    reviewStage: null,
    nextReviewAtMs: null,
    lastReviewAtMs: null,
    manualImportanceNudgeScore: 0,
    manualUrgencyNudgeScore: 0,
  );
}

final class _TodoCommandBackend extends TestAppBackend {
  _TodoCommandBackend(this.current);

  Todo current;
  var upsertTodoCalls = 0;
  var transitionTodoCalls = 0;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => <Todo>[current];

  @override
  Future<Todo?> getTodoById(Uint8List key, String todoId) async {
    return current.id == todoId ? current : null;
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
    upsertTodoCalls += 1;
    current = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: current.createdAtMs,
      updatedAtMs: current.updatedAtMs + 1,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
      manualImportanceNudgeScore: manualImportanceNudgeScore ?? 0,
      manualUrgencyNudgeScore: manualUrgencyNudgeScore ?? 0,
    );
    return current;
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
    transitionTodoCalls += 1;
    current = Todo(
      id: current.id,
      title: current.title,
      dueAtMs: clearDueAtMs ? null : (dueAtMs ?? current.dueAtMs),
      status: newStatus ?? current.status,
      sourceEntryId: current.sourceEntryId,
      createdAtMs: current.createdAtMs,
      updatedAtMs: current.updatedAtMs + 1,
      reviewStage:
          clearReviewStage ? null : (reviewStage ?? current.reviewStage),
      nextReviewAtMs: clearNextReviewAtMs
          ? null
          : (nextReviewAtMs ?? current.nextReviewAtMs),
      lastReviewAtMs: clearLastReviewAtMs
          ? null
          : (lastReviewAtMs ?? current.lastReviewAtMs),
      manualImportanceNudgeScore: clearManualImportanceNudgeScore
          ? 0
          : (manualImportanceNudgeScore ??
              current.manualImportanceNudgeScore ??
              0),
      manualUrgencyNudgeScore: clearManualUrgencyNudgeScore
          ? 0
          : (manualUrgencyNudgeScore ?? current.manualUrgencyNudgeScore ?? 0),
    );
    return current;
  }
}
