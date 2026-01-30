import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/agenda/todo_agenda_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Todo agenda page groups items by status', (tester) async {
    final nowLocal = DateTime.now();
    final todayNoonLocal =
        DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 12);
    final yesterdayNoonLocal = todayNoonLocal.subtract(const Duration(days: 1));
    final tomorrowNoonLocal = todayNoonLocal.add(const Duration(days: 1));

    final backend = _Backend(
      todos: [
        Todo(
          id: 't_in_progress',
          title: 'In progress',
          dueAtMs: tomorrowNoonLocal.toUtc().millisecondsSinceEpoch,
          status: 'in_progress',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        Todo(
          id: 't_open',
          title: 'Not started',
          dueAtMs: todayNoonLocal.toUtc().millisecondsSinceEpoch,
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        Todo(
          id: 't_done',
          title: 'Completed',
          dueAtMs: yesterdayNoonLocal.toUtc().millisecondsSinceEpoch,
          status: 'done',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
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
              child: const TodoAgendaPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inProgress =
        find.byKey(const ValueKey('todo_agenda_item_t_in_progress'));
    final open = find.byKey(const ValueKey('todo_agenda_item_t_open'));
    final done = find.byKey(const ValueKey('todo_agenda_item_t_done'));

    expect(inProgress, findsOneWidget);
    expect(open, findsOneWidget);
    expect(done, findsOneWidget);

    final inProgressY = tester.getTopLeft(inProgress).dy;
    final openY = tester.getTopLeft(open).dy;
    final doneY = tester.getTopLeft(done).dy;

    expect(inProgressY, lessThan(openY));
    expect(openY, lessThan(doneY));
  });
}

final class _Backend extends TestAppBackend {
  _Backend({required List<Todo> todos}) : _todos = List<Todo>.from(todos);

  final List<Todo> _todos;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(_todos);
}
