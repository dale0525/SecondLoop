import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/task_priority_ai_enhancement_prefs.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('sync changes debounce task priority refresh in chat',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      TaskPriorityAiEnhancementPrefs.prefsKey: false,
    });
    final backend = _TaskPriorityCountingBackend();
    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: SyncEngineScope(
            engine: engine,
            child: wrapWithI18n(
              const MaterialApp(
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
      ),
    );
    await tester.pumpAndSettle();

    final initialListTodosCalls = backend.listTodosCalls;
    expect(initialListTodosCalls, greaterThan(0));

    engine.notifyExternalChange();
    engine.notifyExternalChange();
    engine.notifyExternalChange();
    await tester.pump(const Duration(milliseconds: 100));

    expect(backend.listTodosCalls, initialListTodosCalls);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(backend.listTodosCalls, initialListTodosCalls + 1);
    engine.stop();
  });

  testWidgets('sync-created todo refresh shows secretary planning card',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      TaskPriorityAiEnhancementPrefs.prefsKey: false,
    });
    final backend = _TaskPriorityCountingBackend();
    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: SyncEngineScope(
            engine: engine,
            child: wrapWithI18n(
              const MaterialApp(
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('secretary_planning_card')), findsNothing);

    final dueAtMs =
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch;
    backend.setTodos(<Todo>[
      Todo(
        id: 'todo:m1',
        title: '明天上午提交验收报告',
        dueAtMs: dueAtMs,
        status: 'open',
        sourceEntryId: 'm1',
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    ]);
    engine.notifyExternalChange();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('secretary_planning_card')), findsOneWidget);
    engine.stop();
  });
}

final class _NoopSyncRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}

final class _TaskPriorityCountingBackend extends TestAppBackend {
  final List<Todo> _todos = <Todo>[];
  int listTodosCalls = 0;

  void setTodos(List<Todo> todos) {
    _todos
      ..clear()
      ..addAll(todos);
  }

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    listTodosCalls += 1;
    return List<Todo>.from(_todos, growable: false);
  }
}
