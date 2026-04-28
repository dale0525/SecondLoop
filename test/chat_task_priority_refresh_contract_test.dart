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
}

final class _NoopSyncRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}

final class _TaskPriorityCountingBackend extends TestAppBackend {
  int listTodosCalls = 0;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    listTodosCalls += 1;
    return const <Todo>[
      Todo(
        id: 'focus',
        title: 'Fix prod issue',
        dueAtMs: null,
        status: 'open',
        sourceEntryId: null,
        createdAtMs: 0,
        updatedAtMs: 10,
        reviewStage: null,
        nextReviewAtMs: null,
        lastReviewAtMs: null,
      ),
    ];
  }
}
