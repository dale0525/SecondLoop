import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'noop_sync_runner.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Auto-created inbox todo is scheduled for review reminders',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _Backend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const ChatPage(
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

    await tester.enterText(
        find.byKey(const ValueKey('chat_input')), 'todo: Pay rent');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final created = backend.upserted.lastWhere((t) => t.id == 'todo:m1');
    expect(created.status, 'inbox');
    expect(created.dueAtMs, isNull);
    expect(created.reviewStage, 0);
    expect(created.nextReviewAtMs, isNotNull);
  });

  testWidgets('Rolling forward stale review todos notifies sync engine',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final staleNextReviewAtMs =
        nowUtcMs - const Duration(days: 3).inMilliseconds;
    final backend = _Backend(
      todos: <Todo>[
        Todo(
          id: 'todo:stale',
          title: 'stale review',
          status: 'inbox',
          createdAtMs: nowUtcMs - 1000,
          updatedAtMs: nowUtcMs - 1000,
          reviewStage: 0,
          nextReviewAtMs: staleNextReviewAtMs,
        ),
      ],
    );
    final engine = SyncEngine(
      syncRunner: NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );
    var changes = 0;
    engine.changes.addListener(() => changes += 1);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: SyncEngineScope(
            engine: engine,
            child: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const ChatPage(
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
      ),
    );

    await tester.pumpAndSettle();

    expect(backend.upserted, isNotEmpty);
    final rolled = backend.upserted.lastWhere((t) => t.id == 'todo:stale');
    expect(rolled.nextReviewAtMs, isNotNull);
    expect(rolled.nextReviewAtMs, greaterThan(staleNextReviewAtMs));
    expect(changes, 1);
  });
}

final class _Backend extends TestAppBackend {
  _Backend({List<Todo>? todos})
      : _todos = List<Todo>.from(todos ?? const <Todo>[]);

  final List<Todo> _todos;
  final List<Todo> upserted = <Todo>[];

  @override
  Future<List<Todo>> listTodos(Uint8List key) async =>
      List<Todo>.from(_todos, growable: false);

  @override
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final existing = _todos.where((t) => t.id == id).cast<Todo?>().firstWhere(
          (_) => true,
          orElse: () => null,
        );
    final todo = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: existing?.createdAtMs ?? nowMs,
      updatedAtMs: nowMs,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
    _todos.removeWhere((t) => t.id == id);
    _todos.add(todo);
    upserted.add(todo);
    return todo;
  }
}
