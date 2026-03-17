import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('TodoDetailPage renders pending follow-up suggestions',
      (tester) async {
    _setLargeDisplay(tester);
    final backend = _Backend();

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_detail_followup_suggestions_section')),
      findsOneWidget,
    );
    expect(find.text('Information follow-up'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.textContaining('未联网核实'), findsOneWidget);
  });

  testWidgets('TodoDetailPage applies pending follow-up suggestions',
      (tester) async {
    _setLargeDisplay(tester);
    final backend = _Backend();

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_apply_pending')),
    );
    await tester.pumpAndSettle();

    expect(backend.appliedSuggestionIds, const <String>['f1']);
  });

  testWidgets('TodoDetailPage renders applied follow-up suggestions',
      (tester) async {
    _setLargeDisplay(tester);
    final backend = _Backend(
      initialSuggestions: const <TodoFollowupSuggestion>[
        TodoFollowupSuggestion(
          id: 'f_applied',
          todoId: 't1',
          content: '已整理主流模型的定价与上下文窗口。',
          state: 'applied',
          source: 'cloud',
          generationMode: 'web_search',
          generationKey: 'gen_a',
          citationsJson: null,
          createdAtMs: 1,
          updatedAtMs: 1,
          dismissedAtMs: null,
          appliedActivityId: 'a1',
        ),
      ],
      initialActivities: const <TodoActivity>[
        TodoActivity(
          id: 'a1',
          todoId: 't1',
          activityType: 'followup_information',
          fromStatus: null,
          toStatus: null,
          content: '已整理主流模型的定价与上下文窗口。',
          sourceMessageId: null,
          createdAtMs: 1,
        ),
      ],
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    expect(find.text('Applied'), findsOneWidget);
    expect(find.text('Web search'), findsOneWidget);
    expect(find.text('AI-collected information'), findsOneWidget);
  });

  testWidgets('TodoDetailPage shows empty follow-up state', (tester) async {
    _setLargeDisplay(tester);
    final backend =
        _Backend(initialSuggestions: const <TodoFollowupSuggestion>[]);

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    expect(find.text('No information follow-up yet.'), findsOneWidget);
  });

  testWidgets(
      'TodoDetailPage dismisses pending follow-up before regenerate enqueue',
      (tester) async {
    _setLargeDisplay(tester);
    final completer = Completer<void>();
    final backend = _Backend(regenerateCompleter: completer);

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pump();

    expect(backend.dismissedSuggestionIds, const <String>['f1']);
    expect(backend.enqueuedRegenerate, isTrue);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('TodoDetailPage shows regenerate loading state', (tester) async {
    _setLargeDisplay(tester);
    final completer = Completer<void>();
    final backend = _Backend(
      initialSuggestions: const <TodoFollowupSuggestion>[],
      regenerateCompleter: completer,
    );

    await tester.pumpWidget(_buildSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('todo_detail_followup_generating_indicator')),
      findsOneWidget,
    );
    expect(find.text('Generating information…'), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_detail_followup_generating_indicator')),
      findsNothing,
    );
    expect(backend.enqueuedRegenerate, isTrue);
  });
}

void _setLargeDisplay(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _buildSubject(_Backend backend) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: const TodoDetailPage(
            initialTodo: Todo(
              id: 't1',
              title: '调研一下当前主流的 llm 模型',
              status: 'open',
              createdAtMs: 0,
              updatedAtMs: 0,
            ),
          ),
        ),
      ),
    ),
  );
}

final class _Backend extends AppBackend {
  _Backend({
    List<TodoFollowupSuggestion>? initialSuggestions,
    List<TodoActivity>? initialActivities,
    this.regenerateCompleter,
  })  : _suggestions = List<TodoFollowupSuggestion>.from(
          initialSuggestions ??
              const <TodoFollowupSuggestion>[
                TodoFollowupSuggestion(
                  id: 'f1',
                  todoId: 't1',
                  content: '以下内容基于模型知识整理，未联网核实。',
                  state: 'pending',
                  source: 'cloud',
                  generationMode: 'model_knowledge',
                  generationKey: 'gen_1',
                  citationsJson: null,
                  createdAtMs: 1,
                  updatedAtMs: 1,
                  dismissedAtMs: null,
                  appliedActivityId: null,
                ),
              ],
        ),
        _activities = List<TodoActivity>.from(
            initialActivities ?? const <TodoActivity>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final List<TodoFollowupSuggestion> _suggestions;
  final List<TodoActivity> _activities;
  final Completer<void>? regenerateCompleter;
  List<String> appliedSuggestionIds = <String>[];
  List<String> dismissedSuggestionIds = <String>[];
  bool enqueuedRegenerate = false;

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
      List<TodoActivity>.from(_activities);

  @override
  Future<List<TodoChecklistItem>> listTodoChecklistItems(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoChecklistItem>[];

  @override
  Future<List<TodoChecklistSuggestion>> listTodoChecklistSuggestions(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoChecklistSuggestion>[];

  @override
  Future<List<TodoFollowupSuggestion>> listTodoFollowupSuggestions(
    Uint8List key,
    String todoId,
  ) async =>
      List<TodoFollowupSuggestion>.from(_suggestions);

  @override
  Future<List<TodoActivity>> applyTodoFollowupSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    appliedSuggestionIds = List<String>.from(suggestionIds);
    for (var index = 0; index < _suggestions.length; index++) {
      final suggestion = _suggestions[index];
      if (!suggestionIds.contains(suggestion.id)) continue;
      _suggestions[index] = TodoFollowupSuggestion(
        id: suggestion.id,
        todoId: suggestion.todoId,
        content: suggestion.content,
        state: 'applied',
        source: suggestion.source,
        generationMode: suggestion.generationMode,
        generationKey: suggestion.generationKey,
        citationsJson: suggestion.citationsJson,
        createdAtMs: suggestion.createdAtMs,
        updatedAtMs: suggestion.updatedAtMs,
        dismissedAtMs: suggestion.dismissedAtMs,
        appliedActivityId: 'a_applied',
      );
    }
    _activities.add(
      const TodoActivity(
        id: 'a_applied',
        todoId: 't1',
        activityType: 'followup_information',
        fromStatus: null,
        toStatus: null,
        content: '以下内容基于模型知识整理，未联网核实。',
        sourceMessageId: null,
        createdAtMs: 1,
      ),
    );
    return List<TodoActivity>.from(_activities);
  }

  @override
  Future<void> dismissTodoFollowupSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    dismissedSuggestionIds = List<String>.from(suggestionIds);
    _suggestions.removeWhere((item) => suggestionIds.contains(item.id));
  }

  @override
  Future<void> enqueueTodoFollowupGenerationJob(
    Uint8List key, {
    required String todoId,
    required String triggerKind,
    String? taskTypeHint,
    required int nowMs,
  }) async {
    enqueuedRegenerate = true;
    final completer = regenerateCompleter;
    if (completer != null) {
      await completer.future;
    }
    if (_suggestions.isEmpty) {
      _suggestions.add(
        const TodoFollowupSuggestion(
          id: 'generated_f1',
          todoId: 't1',
          content: '以下内容基于模型知识整理，未联网核实。',
          state: 'pending',
          source: 'cloud',
          generationMode: 'model_knowledge',
          generationKey: 'regen_1',
          citationsJson: null,
          createdAtMs: 1,
          updatedAtMs: 1,
          dismissedAtMs: null,
          appliedActivityId: null,
        ),
      );
    }
  }
}
