import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 50),
  int maxPumps = 120,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(step);
    if (condition()) {
      return;
    }
  }
  expect(condition(), isTrue);
}

Future<void> _pumpUntilTaskHubReady(WidgetTester tester) {
  return _pumpUntil(
    tester,
    () =>
        find.byKey(const ValueKey('task_hub_page')).evaluate().isNotEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
}

void main() {
  testWidgets('more quick action matches button height on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'open',
          title: 'Plan next step',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    final tomorrowButton = find.byKey(
      const ValueKey('task_hub_page_quick_open_tomorrow'),
    );
    final moreButton = find.byKey(
      const ValueKey('task_hub_page_quick_open_more'),
    );

    expect(tomorrowButton, findsOneWidget);
    expect(moreButton, findsOneWidget);
    expect(
      tester.getSize(moreButton).height,
      tester.getSize(tomorrowButton).height,
    );
  });
}

Widget _wrap(AppBackend backend) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: const TaskHubPage(),
        ),
      ),
    ),
  );
}

final class _TaskHubBackend extends TestAppBackend {
  _TaskHubBackend({required List<Todo> todos})
      : _todos = {for (final todo in todos) todo.id: todo};

  final Map<String, Todo> _todos;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    return _todos.values.toList(growable: false);
  }
}
