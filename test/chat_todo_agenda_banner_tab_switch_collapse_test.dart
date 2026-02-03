import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/app/router.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Todo agenda banner collapses on tab switch back to chat',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final nowLocal = DateTime.now();
    final todayNoonLocal =
        DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 12);

    final backend = _Backend(
      todos: [
        Todo(
          id: 'todo:today',
          title: 'Review metrics',
          dueAtMs: todayNoonLocal.toUtc().millisecondsSinceEpoch,
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
              child: const AppShell(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('todo_agenda_banner')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('todo_agenda_preview_list')), findsOneWidget);

    final rail = find.byType(NavigationRail);
    await tester.tap(
      find.descendant(of: rail, matching: find.byIcon(Icons.settings_outlined)),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
          of: rail, matching: find.byIcon(Icons.chat_bubble_outline)),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('todo_agenda_preview_list')), findsNothing);
  });
}

final class _Backend extends TestAppBackend {
  _Backend({required List<Todo> todos}) : _todos = List<Todo>.from(todos);

  final List<Todo> _todos;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(_todos);
}
