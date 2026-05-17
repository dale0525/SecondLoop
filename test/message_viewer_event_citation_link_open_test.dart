import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/calendar/event_viewer_page.dart';
import 'package:secondloop/features/chat/message_viewer_page.dart';
import 'package:secondloop/core/models/app_models.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('message viewer secondloop event link opens event viewer',
      (tester) async {
    final backend = _Backend(
      events: const [
        Event(
          id: 'event:budget-review',
          title: 'Budget review with Alice',
          startAtMs: 1000,
          endAtMs: 2000,
          tz: 'UTC',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
              lock: () {},
              child: const MessageViewerPage(
                content: '[Open event](secondloop://event/event:budget-review)',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Open event', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(EventViewerPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('event_viewer_page')),
        matching: find.text('Budget review with Alice'),
      ),
      findsWidgets,
    );
  });

  testWidgets(
      'message viewer secondloop todo link opens agent task detail via get-by-id',
      (tester) async {
    final backend = _Backend(
      todos: const [
        Todo(
          id: 'todo:launch-checklist',
          title: 'Launch checklist',
          status: 'open',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ],
      throwOnListTodos: true,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
              lock: () {},
              child: const MessageViewerPage(
                content: '[Open todo](secondloop://todo/todo:launch-checklist)',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Open todo', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
        find.byKey(const ValueKey('agent_task_detail_sheet')), findsOneWidget);
    expect(find.text('Launch checklist'), findsWidgets);
  });

  testWidgets(
      'message viewer secondloop event link opens event viewer via get-by-id',
      (tester) async {
    final backend = _Backend(
      events: const [
        Event(
          id: 'event:budget-review',
          title: 'Budget review with Alice',
          startAtMs: 1000,
          endAtMs: 2000,
          tz: 'UTC',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ],
      throwOnListEvents: true,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
              lock: () {},
              child: const MessageViewerPage(
                content: '[Open event](secondloop://event/event:budget-review)',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Open event', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(EventViewerPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('event_viewer_page')),
        matching: find.text('Budget review with Alice'),
      ),
      findsWidgets,
    );
  });
}

final class _Backend extends TestAppBackend {
  _Backend({
    List<Event> events = const <Event>[],
    List<Todo> todos = const <Todo>[],
    this.throwOnListEvents = false,
    this.throwOnListTodos = false,
  })  : _events = List<Event>.from(events),
        _todos = List<Todo>.from(todos);

  final List<Event> _events;
  final List<Todo> _todos;
  final bool throwOnListEvents;
  final bool throwOnListTodos;

  @override
  Future<List<Event>> listEvents(Uint8List key) async {
    if (throwOnListEvents) {
      throw StateError('listEvents should not be used');
    }
    return List<Event>.from(_events);
  }

  @override
  Future<Event?> getEventById(Uint8List key, String eventId) async {
    for (final event in _events) {
      if (event.id == eventId) {
        return event;
      }
    }
    return null;
  }

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    if (throwOnListTodos) {
      throw StateError('listTodos should not be used');
    }
    return List<Todo>.from(_todos);
  }

  @override
  Future<Todo?> getTodoById(Uint8List key, String todoId) async {
    for (final todo in _todos) {
      if (todo.id == todoId) {
        return todo;
      }
    }
    return null;
  }
}
