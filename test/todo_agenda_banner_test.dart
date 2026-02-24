import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_page.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Chat page shows task hub banner for unscheduled todos',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final backend = _AgendaBackend(
      todos: [
        const Todo(
          id: 'todo:inbox',
          title: 'Plan quarterly review',
          dueAtMs: null,
          status: 'inbox',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const MaterialApp(
              home: ChatPage(
                conversation: Conversation(
                  id: 'main_stream',
                  title: 'Main Stream',
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

    expect(find.byKey(const ValueKey('task_hub_banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo_agenda_banner')), findsNothing);
    expect(
        find.byKey(const ValueKey('todo_undetermined_banner')), findsNothing);
  });

  testWidgets('Task hub banner expands and view all opens task hub page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final nowLocal = DateTime.now();
    final dueLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 12);

    final backend = _AgendaBackend(
      todos: [
        Todo(
          id: 'todo:today',
          title: 'Review metrics',
          dueAtMs: dueLocal.toUtc().millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const MaterialApp(
              home: ChatPage(
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

    await tester.tap(find.byKey(const ValueKey('task_hub_banner')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_hub_preview_list')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task_hub_view_all')));
    await tester.pumpAndSettle();

    expect(find.byType(TaskHubPage), findsOneWidget);
  });

  testWidgets('Task hub banner auto-collapses after 10 seconds',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final nowLocal = DateTime.now();
    final dueLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 12);

    final backend = _AgendaBackend(
      todos: [
        Todo(
          id: 'todo:today',
          title: 'Review metrics',
          dueAtMs: dueLocal.toUtc().millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const MaterialApp(
              home: ChatPage(
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

    await tester.tap(find.byKey(const ValueKey('task_hub_banner')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task_hub_preview_list')), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.byKey(const ValueKey('task_hub_preview_list')), findsNothing);
  });
}

final class _AgendaBackend extends TestAppBackend {
  _AgendaBackend({required List<Todo> todos}) : _todos = List<Todo>.from(todos);

  final List<Todo> _todos;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(_todos);
}
