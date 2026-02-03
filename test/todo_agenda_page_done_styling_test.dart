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
  testWidgets('Done todos are not highlighted as overdue', (tester) async {
    final nowLocal = DateTime.now();
    final yesterdayNoonLocal =
        DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 12)
            .subtract(const Duration(days: 1));

    final backend = _Backend(
      todos: [
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

    final doneItem = find.byKey(const ValueKey('todo_agenda_item_t_done'));
    expect(doneItem, findsOneWidget);

    final dueChip = find.byKey(const ValueKey('todo_agenda_due_t_done'));
    expect(dueChip, findsOneWidget);

    final dueButton = tester.widget<OutlinedButton>(dueChip);
    final dueContext = tester.element(dueChip);
    final scheme = Theme.of(dueContext).colorScheme;

    final foreground =
        dueButton.style?.foregroundColor?.resolve(<MaterialState>{});
    expect(foreground, scheme.onSurfaceVariant);

    expect(
      find.descendant(
        of: doneItem,
        matching: find.byIcon(Icons.warning_rounded),
      ),
      findsNothing,
    );

    final dot = find.descendant(
      of: doneItem,
      matching: find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final constraints = widget.constraints;
        if (constraints == null) return false;
        if (constraints.minWidth != 10 ||
            constraints.maxWidth != 10 ||
            constraints.minHeight != 10 ||
            constraints.maxHeight != 10) {
          return false;
        }
        final decoration = widget.decoration;
        return decoration is BoxDecoration && decoration.color != null;
      }),
    );
    expect(dot, findsOneWidget);

    final dotContainer = tester.widget<Container>(dot);
    final decoration = dotContainer.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFF22C55E));
  });
}

final class _Backend extends TestAppBackend {
  _Backend({required List<Todo> todos}) : _todos = List<Todo>.from(todos);

  final List<Todo> _todos;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(_todos);
}
