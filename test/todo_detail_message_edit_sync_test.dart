import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('TodoDetailPage reflects edited linked message content',
      (tester) async {
    final backend = _Backend(
      initialMessages: const [
        Message(
          id: 'm1',
          conversationId: 'loop_home',
          role: 'user',
          content: 'before',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
    );

    final engine = SyncEngine(
      syncRunner: _NoopRunner(),
      loadConfig: () async => null,
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            splashFactory: InkRipple.splashFactory,
          ),
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: SyncEngineScope(
                engine: engine,
                child: const TodoDetailPage(
                  initialTodo: Todo(
                    id: 't1',
                    title: 'Task',
                    status: 'open',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(_findPlainText('before'), findsOneWidget);

    await backend.editMessage(
      Uint8List.fromList(List<int>.filled(32, 1)),
      'm1',
      'after',
    );

    engine.notifyLocalMutation();
    await tester.pumpAndSettle();

    expect(_findPlainText('after'), findsOneWidget);
    expect(_findPlainText('before'), findsNothing);
  });
}

Finder _findPlainText(String needle) {
  return find.byWidgetPredicate((widget) {
    if (widget is Text) {
      return widget.data?.contains(needle) == true;
    }
    if (widget is SelectableText) {
      final data = widget.data;
      if (data != null && data.contains(needle)) return true;
      final span = widget.textSpan;
      if (span != null && span.toPlainText().contains(needle)) return true;
      return false;
    }
    if (widget is RichText) {
      return widget.text.toPlainText().contains(needle);
    }
    return false;
  });
}

final class _NoopRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}

final class _Backend extends TestAppBackend {
  _Backend({required super.initialMessages});

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      const [
        TodoActivity(
          id: 'a1',
          todoId: 't1',
          activityType: 'note',
          content: 'before',
          sourceMessageId: 'm1',
          createdAtMs: 0,
        ),
      ];

  @override
  Future<List<Attachment>> listTodoActivityAttachments(
    Uint8List key,
    String activityId,
  ) async =>
      const <Attachment>[];
}
