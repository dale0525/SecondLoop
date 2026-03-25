import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/src/rust/db.dart';

import 'todo_detail_followup_suggestions_test_shared.dart';

void main() {
  testWidgets(
      'TodoDetailPage hides follow-up section when backend lacks support',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);

    await tester.pumpWidget(buildTodoDetailSubject(UnsupportedBackend()));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_detail_followup_suggestions_section')),
      findsNothing,
    );
    expect(find.text('Information follow-up'), findsNothing);
  });

  testWidgets('TodoDetailPage renders pending follow-up suggestions',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend();

    await tester.pumpWidget(buildTodoDetailSubject(backend));
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
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend();

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_apply_pending')),
    );
    await tester.pumpAndSettle();

    expect(backend.appliedSuggestionIds, const <String>['f1']);
  });

  testWidgets('TodoDetailPage applying follow-up wakes sync listeners',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend();
    final engine = SyncEngine(
      syncRunner: NoopSyncRunner(),
      loadConfig: () async => null,
    );
    var changeCount = 0;
    void onChange() => changeCount += 1;
    engine.changes.addListener(onChange);
    addTearDown(() {
      engine.changes.removeListener(onChange);
      engine.stop();
    });

    await tester
        .pumpWidget(buildTodoDetailSubject(backend, syncEngine: engine));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_apply_pending')),
    );
    await tester.pumpAndSettle();

    expect(backend.appliedSuggestionIds, const <String>['f1']);
    expect(changeCount, greaterThan(0));
  });

  testWidgets('TodoDetailPage dismissing follow-up wakes sync listeners',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend();
    final engine = SyncEngine(
      syncRunner: NoopSyncRunner(),
      loadConfig: () async => null,
    );
    var changeCount = 0;
    void onChange() => changeCount += 1;
    engine.changes.addListener(onChange);
    addTearDown(() {
      engine.changes.removeListener(onChange);
      engine.stop();
    });

    await tester
        .pumpWidget(buildTodoDetailSubject(backend, syncEngine: engine));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_dismiss_pending')),
    );
    await tester.pumpAndSettle();

    expect(backend.dismissedSuggestionIds, const <String>['f1']);
    expect(changeCount, greaterThan(0));
  });

  testWidgets('TodoDetailPage renders applied follow-up suggestions',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend(
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

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pumpAndSettle();

    expect(find.text('Applied'), findsOneWidget);
    expect(find.text('Web search'), findsOneWidget);
    expect(find.text('AI-collected information'), findsOneWidget);
  });

  testWidgets('TodoDetailPage derives citation domain from validated url',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend(
      initialSuggestions: const <TodoFollowupSuggestion>[
        TodoFollowupSuggestion(
          id: 'f_domain',
          todoId: 't1',
          content: '已查询到最新信息。',
          state: 'pending',
          source: 'cloud',
          generationMode: 'web_search',
          generationKey: 'gen_domain',
          citationsJson:
              '[{"title":"Airport","url":"https://airport.example/flight","domain":"trusted.example"}]',
          createdAtMs: 1,
          updatedAtMs: 1,
          dismissedAtMs: null,
          appliedActivityId: null,
        ),
      ],
    );

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pumpAndSettle();

    expect(find.textContaining('airport.example · Airport'), findsOneWidget);
    expect(find.textContaining('trusted.example · Airport'), findsNothing);
  });

  testWidgets('TodoDetailPage shows empty follow-up state', (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend =
        TestBackend(initialSuggestions: const <TodoFollowupSuggestion>[]);

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pumpAndSettle();

    expect(find.text('No information follow-up yet.'), findsOneWidget);
  });

  testWidgets(
      'TodoDetailPage keeps pending follow-up until regenerate finishes',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final completer = Completer<void>();
    final backend = TestBackend(regenerateCompleter: completer);

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pump();

    expect(backend.dismissedSuggestionIds, isEmpty);
    expect(backend.enqueuedRegenerate, isTrue);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('TodoDetailPage regenerate wakes sync listeners immediately',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend();
    final engine = SyncEngine(
      syncRunner: NoopSyncRunner(),
      loadConfig: () async => null,
    );
    var changeCount = 0;
    void onChange() => changeCount += 1;
    engine.changes.addListener(onChange);
    addTearDown(() {
      engine.changes.removeListener(onChange);
      engine.stop();
    });

    await tester
        .pumpWidget(buildTodoDetailSubject(backend, syncEngine: engine));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pump();

    expect(backend.enqueuedRegenerate, isTrue);
    expect(changeCount, greaterThan(0));
  });
}
