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
  testWidgets('Todo agenda page lazily loads done section', (tester) async {
    final base = DateTime(2024, 1, 1, 12);
    final todos = [
      for (var i = 0; i < 45; i++)
        Todo(
          id: 'done_$i',
          title: 'Done $i',
          dueAtMs: base.add(Duration(days: i)).toUtc().millisecondsSinceEpoch,
          status: 'done',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
    ];

    final backend = _Backend(todos: todos);

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

    final list = find.byType(ListView);
    expect(list, findsOneWidget);

    int itemCount() {
      final listView = tester.widget<ListView>(list);
      final delegate = listView.childrenDelegate as SliverChildBuilderDelegate;
      final childCount = delegate.childCount;
      if (childCount == null) return 0;
      return (childCount + 1) ~/ 2;
    }

    final initial = itemCount();
    expect(initial, 22);

    var loaded = initial;
    for (var i = 0; i < 20 && loaded == initial; i++) {
      await tester.drag(list, const Offset(0, -1200));
      await tester.pumpAndSettle();
      loaded = itemCount();
    }

    expect(loaded, greaterThan(initial));
  });
}

final class _Backend extends TestAppBackend {
  _Backend({required List<Todo> todos}) : _todos = List<Todo>.from(todos);

  final List<Todo> _todos;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(_todos);
}
