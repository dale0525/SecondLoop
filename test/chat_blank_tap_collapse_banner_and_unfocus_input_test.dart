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
  testWidgets('tapping blank area collapses task banner and unfocuses input',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final nowLocal = DateTime.now();
    final todayNoonLocal =
        DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 12);

    await tester.pumpWidget(
      _wrapChat(
        backend: _Backend(
          todos: <Todo>[
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
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task_hub_banner')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task_hub_preview_list')), findsOneWidget);

    final inputFinder = find.byKey(const ValueKey('chat_input'));
    TextField input() => tester.widget<TextField>(inputFinder);

    await tester.tap(inputFinder);
    await tester.pump();
    expect(input().focusNode?.hasFocus, isTrue);

    await tester.tapAt(const Offset(860, 260));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_hub_preview_list')), findsNothing);
    expect(input().focusNode?.hasFocus, isFalse);
  });
}

Widget _wrapChat({required AppBackend backend}) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
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
  );
}

final class _Backend extends TestAppBackend {
  _Backend({required List<Todo> todos}) : _todos = List<Todo>.from(todos);

  final List<Todo> _todos;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(_todos);
}
