import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';
import 'noop_sync_runner.dart';

void main() {
  testWidgets('TodoDetailPage renders checklist section and supports item CRUD',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = _Backend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const TodoDetailPage(
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
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

    expect(find.byKey(const ValueKey('todo_detail_checklist_section')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('todo_detail_checklist_input')),
        findsOneWidget);
    expect(find.text('Draft launch post'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('todo_detail_checklist_input')),
      'Draft launch post',
    );
    await tester.tap(find.byKey(const ValueKey('todo_detail_checklist_add')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('todo_detail_checklist_input')),
      'Share with team',
    );
    await tester.tap(find.byKey(const ValueKey('todo_detail_checklist_add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_detail_checklist_item_item_1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('todo_detail_checklist_item_item_2')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('todo_detail_checklist_progress')),
        findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_toggle_item_1')),
    );
    await tester.pumpAndSettle();
    expect(backend.items.first.isDone, isTrue);
    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_edit_item_1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('todo_detail_checklist_edit_input')),
      'Draft updated post',
    );
    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_edit_save')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Draft updated post'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_move_up_item_2')),
    );
    await tester.pumpAndSettle();
    expect(backend.items.first.id, 'item_2');

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_delete_item_1')),
    );
    await tester.pumpAndSettle();
    expect(backend.items.map((item) => item.id), <String>['item_2']);
  });

  testWidgets('TodoDetailPage shows snackbar when checklist toggle fails',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = _Backend(
      initialItems: const <TodoChecklistItem>[
        TodoChecklistItem(
          id: 'item_1',
          todoId: 't1',
          content: 'Draft launch post',
          isDone: false,
          sortOrder: 0,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ],
      toggleError: StateError('toggle failed'),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const TodoDetailPage(
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
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

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_toggle_item_1')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('toggle failed'), findsOneWidget);
    expect(backend.items.first.isDone, isFalse);
  });

  testWidgets('TodoDetailPage shows snackbar when checklist creation fails',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = _Backend(createError: StateError('create failed'));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const TodoDetailPage(
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
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
      find.byKey(const ValueKey('todo_detail_checklist_input')),
      'Draft launch post',
    );
    await tester.tap(find.byKey(const ValueKey('todo_detail_checklist_add')));
    await tester.pumpAndSettle();

    expect(find.textContaining('create failed'), findsOneWidget);
    expect(backend.items, isEmpty);
  });

  testWidgets('TodoDetailPage shows snackbar when checklist edit fails',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = _Backend(
      initialItems: const <TodoChecklistItem>[
        TodoChecklistItem(
          id: 'item_1',
          todoId: 't1',
          content: 'Draft launch post',
          isDone: false,
          sortOrder: 0,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ],
      updateError: StateError('edit failed'),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const TodoDetailPage(
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
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

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_edit_item_1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('todo_detail_checklist_edit_input')),
      'Updated content',
    );
    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_edit_save')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('edit failed'), findsOneWidget);
    expect(backend.items.first.content, 'Draft launch post');
  });

  testWidgets('TodoDetailPage shows snackbar when checklist delete fails',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = _Backend(
      initialItems: const <TodoChecklistItem>[
        TodoChecklistItem(
          id: 'item_1',
          todoId: 't1',
          content: 'Draft launch post',
          isDone: false,
          sortOrder: 0,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ],
      deleteError: StateError('delete failed'),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const TodoDetailPage(
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
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

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_delete_item_1')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('delete failed'), findsOneWidget);
    expect(backend.items, hasLength(1));
  });

  testWidgets(
      'TodoDetailPage clears stale checklist suggestion selection after sync refresh',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = _Backend(
      initialSuggestions: const <TodoChecklistSuggestion>[
        TodoChecklistSuggestion(
          id: 'suggestion_1',
          todoId: 't1',
          content: 'Draft launch post',
          sortOrder: 0,
          state: 'pending',
          source: 'cloud',
          generationKey: 'gen_1',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
        TodoChecklistSuggestion(
          id: 'suggestion_2',
          todoId: 't1',
          content: 'Share with team',
          sortOrder: 1,
          state: 'pending',
          source: 'cloud',
          generationKey: 'gen_1',
          createdAtMs: 2,
          updatedAtMs: 2,
        ),
      ],
    );
    final engine = SyncEngine(
      syncRunner: NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );

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
                child: const TodoDetailPage(
                  initialTodo: Todo(
                    id: 't1',
                    title: 'Task',
                    status: 'open',
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

    await tester.tap(
      find.byKey(
        const ValueKey('todo_detail_checklist_suggestion_select_suggestion_1'),
      ),
    );
    await tester.pumpAndSettle();

    var applyButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('todo_detail_checklist_apply_selected')),
    );
    expect(applyButton.onPressed, isNotNull);

    backend.suggestions
      ..clear()
      ..add(
        const TodoChecklistSuggestion(
          id: 'suggestion_2',
          todoId: 't1',
          content: 'Share with team',
          sortOrder: 1,
          state: 'pending',
          source: 'cloud',
          generationKey: 'gen_1',
          createdAtMs: 2,
          updatedAtMs: 2,
        ),
      );
    engine.notifyExternalChange();
    await tester.pumpAndSettle();

    applyButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('todo_detail_checklist_apply_selected')),
    );
    expect(applyButton.onPressed, isNull);
  });

  testWidgets(
      'TodoDetailPage re-shows reverted checklist suggestion after deleting applied item',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = _Backend(
      initialItems: const <TodoChecklistItem>[
        TodoChecklistItem(
          id: 'item_1',
          todoId: 't1',
          content: 'Draft launch post',
          isDone: false,
          sortOrder: 0,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ],
      initialSuggestions: const <TodoChecklistSuggestion>[
        TodoChecklistSuggestion(
          id: 'suggestion_1',
          todoId: 't1',
          content: 'Draft launch post',
          sortOrder: 0,
          state: 'applied',
          source: 'cloud',
          generationKey: 'gen_1',
          createdAtMs: 1,
          updatedAtMs: 1,
          dismissedAtMs: null,
          appliedChecklistItemId: 'item_1',
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const TodoDetailPage(
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
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

    expect(find.text('Draft launch post'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_delete_item_1')),
    );
    await tester.pumpAndSettle();

    expect(backend.items, isEmpty);
    expect(find.text('Draft launch post'), findsOneWidget);
    expect(
      backend.suggestions.single.state,
      'pending',
    );
    expect(
      backend.suggestions.single.appliedChecklistItemId,
      isNull,
    );
  });

  testWidgets('TodoDetailPage shows snackbar when checklist reorder fails',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = _Backend(
      initialItems: const <TodoChecklistItem>[
        TodoChecklistItem(
          id: 'item_1',
          todoId: 't1',
          content: 'Draft launch post',
          isDone: false,
          sortOrder: 0,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
        TodoChecklistItem(
          id: 'item_2',
          todoId: 't1',
          content: 'Share with team',
          isDone: false,
          sortOrder: 1,
          createdAtMs: 2,
          updatedAtMs: 2,
        ),
      ],
      reorderError: StateError('reorder failed'),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const TodoDetailPage(
                initialTodo: Todo(
                  id: 't1',
                  title: 'Task',
                  status: 'open',
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

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_checklist_move_up_item_2')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('reorder failed'), findsOneWidget);
    expect(backend.items.map((item) => item.id), <String>['item_1', 'item_2']);
  });
}

final class _Backend extends AppBackend {
  _Backend({
    List<TodoChecklistItem>? initialItems,
    List<TodoChecklistSuggestion>? initialSuggestions,
    this.createError,
    this.toggleError,
    this.updateError,
    this.deleteError,
    this.reorderError,
  }) {
    if (initialItems != null) {
      items.addAll(initialItems);
    }
    if (initialSuggestions != null) {
      suggestions.addAll(initialSuggestions);
    }
  }

  final List<TodoChecklistItem> items = <TodoChecklistItem>[];
  final List<TodoChecklistSuggestion> suggestions = <TodoChecklistSuggestion>[];
  final Object? createError;
  final Object? toggleError;
  final Object? updateError;
  final Object? deleteError;
  final Object? reorderError;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async => null;

  @override
  Future<void> saveSessionKey(Uint8List key) async {}

  @override
  Future<void> clearSavedSessionKey() async {}

  @override
  Future<void> validateKey(Uint8List key) async {}

  @override
  Future<Uint8List> initMasterPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<Uint8List> unlockWithPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoActivity>[];

  @override
  Future<List<TodoChecklistSuggestion>> listTodoChecklistSuggestions(
    Uint8List key,
    String todoId,
  ) async =>
      List<TodoChecklistSuggestion>.from(suggestions);

  @override
  Future<TodoChecklistItem> createTodoChecklistItem(
    Uint8List key, {
    required String todoId,
    required String content,
  }) async {
    if (createError != null) throw createError!;
    final item = TodoChecklistItem(
      id: 'item_${items.length + 1}',
      todoId: todoId,
      content: content,
      isDone: false,
      sortOrder: items.length,
      createdAtMs: items.length + 1,
      updatedAtMs: items.length + 1,
    );
    items.add(item);
    return item;
  }

  @override
  Future<List<TodoChecklistItem>> listTodoChecklistItems(
    Uint8List key,
    String todoId,
  ) async =>
      List<TodoChecklistItem>.from(items);

  @override
  Future<TodoChecklistItem> setTodoChecklistItemDone(
    Uint8List key, {
    required String itemId,
    required bool isDone,
  }) async {
    if (toggleError != null) throw toggleError!;
    final index = items.indexWhere((item) => item.id == itemId);
    final updated = TodoChecklistItem(
      id: items[index].id,
      todoId: items[index].todoId,
      content: items[index].content,
      isDone: isDone,
      sortOrder: items[index].sortOrder,
      createdAtMs: items[index].createdAtMs,
      updatedAtMs: items[index].updatedAtMs + 1,
    );
    items[index] = updated;
    return updated;
  }

  @override
  Future<TodoChecklistItem> updateTodoChecklistItemContent(
    Uint8List key, {
    required String itemId,
    required String content,
  }) async {
    if (updateError != null) throw updateError!;
    final index = items.indexWhere((item) => item.id == itemId);
    final updated = TodoChecklistItem(
      id: items[index].id,
      todoId: items[index].todoId,
      content: content,
      isDone: items[index].isDone,
      sortOrder: items[index].sortOrder,
      createdAtMs: items[index].createdAtMs,
      updatedAtMs: items[index].updatedAtMs + 1,
    );
    items[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteTodoChecklistItem(
    Uint8List key, {
    required String itemId,
  }) async {
    if (deleteError != null) throw deleteError!;
    items.removeWhere((item) => item.id == itemId);
    for (var index = 0; index < suggestions.length; index++) {
      final suggestion = suggestions[index];
      if (suggestion.appliedChecklistItemId != itemId) continue;
      suggestions[index] = TodoChecklistSuggestion(
        id: suggestion.id,
        todoId: suggestion.todoId,
        content: suggestion.content,
        sortOrder: suggestion.sortOrder,
        state: 'pending',
        source: suggestion.source,
        generationKey: suggestion.generationKey,
        createdAtMs: suggestion.createdAtMs,
        updatedAtMs: suggestion.updatedAtMs + 1,
        dismissedAtMs: suggestion.dismissedAtMs,
        appliedChecklistItemId: null,
      );
    }
  }

  @override
  Future<void> reorderTodoChecklistItems(
    Uint8List key, {
    required String todoId,
    required List<String> orderedItemIds,
  }) async {
    if (reorderError != null) throw reorderError!;
    final reordered = <TodoChecklistItem>[];
    for (var index = 0; index < orderedItemIds.length; index++) {
      final item =
          items.firstWhere((entry) => entry.id == orderedItemIds[index]);
      reordered.add(
        TodoChecklistItem(
          id: item.id,
          todoId: item.todoId,
          content: item.content,
          isDone: item.isDone,
          sortOrder: index,
          createdAtMs: item.createdAtMs,
          updatedAtMs: item.updatedAtMs,
        ),
      );
    }
    items
      ..clear()
      ..addAll(reordered);
  }
}
