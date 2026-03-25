import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/features/settings/ai_ask_ai_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'todo_detail_followup_suggestions_test_shared.dart';

void main() {
  testWidgets(
      'TodoDetailPage shows primary regenerate action for information-gathering tasks',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend(
      activeGenerationJob: const TodoFollowupGenerationJob(
        todoId: 't1',
        triggerKind: 'manual_regenerate',
        status: 'failed',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        includeManualFollowups: true,
        manualOverrideFollowup: false,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    );

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
      findsOneWidget,
    );
    expect(
      find.byKey(
          const ValueKey('todo_detail_followup_force_generate_suggestions')),
      findsNothing,
    );
  });

  testWidgets(
      'TodoDetailPage disables manual regenerate while auto generation is active',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend(
      activeGenerationJob: const TodoFollowupGenerationJob(
        todoId: 't1',
        triggerKind: 'auto_create',
        status: 'running',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        includeManualFollowups: false,
        manualOverrideFollowup: false,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    );

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(backend.enqueuedRegenerate, isFalse);
  });

  testWidgets(
      'TodoDetailPage treats running manual regenerate as active generation',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend(
      activeGenerationJob: const TodoFollowupGenerationJob(
        todoId: 't1',
        triggerKind: 'manual_regenerate',
        status: 'running',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        includeManualFollowups: true,
        manualOverrideFollowup: false,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    );

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey('todo_detail_followup_generating_indicator')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(backend.enqueuedRegenerate, isFalse);
  });

  testWidgets(
      'Product intent: TodoDetailPage auto failed follow-up job does not block manual regenerate',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend(
      activeGenerationJob: const TodoFollowupGenerationJob(
        todoId: 't1',
        triggerKind: 'auto_create',
        status: 'failed',
        attempts: 1,
        nextRetryAtMs: 1,
        lastError: 'temporary error',
        includeManualFollowups: false,
        manualOverrideFollowup: false,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    );

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(backend.enqueuedRegenerate, isTrue);
  });

  testWidgets(
      'Product intent: TodoDetailPage failed follow-up job remains manually retryable',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend(
      activeGenerationJob: const TodoFollowupGenerationJob(
        todoId: 't1',
        triggerKind: 'manual_regenerate',
        status: 'failed',
        attempts: 2,
        nextRetryAtMs: 1,
        lastError: 'temporary error',
        includeManualFollowups: true,
        manualOverrideFollowup: false,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    );

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(backend.enqueuedRegenerate, isTrue);
  });

  testWidgets('TodoDetailPage caches follow-up generation job future',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend(
      activeGenerationJob: const TodoFollowupGenerationJob(
        todoId: 't1',
        triggerKind: 'auto_create',
        status: 'running',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        includeManualFollowups: false,
        manualOverrideFollowup: false,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
    );

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(backend.getTodoFollowupGenerationJobCalls, 1);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(backend.getTodoFollowupGenerationJobCalls, 1);
  });

  testWidgets(
      'TodoDetailPage regenerate toggles generating indicator without duplicate AnimatedSwitcher keys',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final completer = Completer<void>();
    final backend = TestBackend(
      initialSuggestions: const <TodoFollowupSuggestion>[],
      regenerateCompleter: completer,
    );

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pump();

    completer.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(
        const ValueKey('todo_detail_followup_generating_indicator_hidden'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('TodoDetailPage shows regenerate loading state', (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final completer = Completer<void>();
    final backend = TestBackend(
      initialSuggestions: const <TodoFollowupSuggestion>[],
      regenerateCompleter: completer,
    );

    await tester.pumpWidget(buildTodoDetailSubject(backend));
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

  testWidgets(
      'TodoDetailPage regenerate opens AI settings when smart organization consent is disabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': false,
    });
    setLargeDisplay(tester);
    final backend = TestBackend();

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pumpAndSettle();

    expect(backend.enqueuedRegenerate, isFalse);
    expect(find.byType(AiAskAiSettingsPage), findsOneWidget);
  });

  testWidgets(
      'TodoDetailPage regenerate opens AI settings when no automation route is configured',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend(llmProfiles: const <LlmProfile>[]);

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pumpAndSettle();

    expect(backend.enqueuedRegenerate, isFalse);
    expect(find.byType(AiAskAiSettingsPage), findsOneWidget);
  });

  testWidgets(
      'TodoDetailPage regenerate shows snackbar when followup route decide throws non-setup error',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = ThrowingLlmProfilesBackend();

    await tester.pumpWidget(buildTodoDetailSubject(backend));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pumpAndSettle();

    expect(backend.enqueuedRegenerate, isFalse);
    expect(find.byType(AiAskAiSettingsPage), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets(
      'TodoDetailPage manual regenerate retries token read after warmup',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend(llmProfiles: const <LlmProfile>[]);

    await tester.pumpWidget(
      buildTodoDetailSubject(
        backend,
        cloudAuthController: WarmupRequiredCloudAuthController(),
        subscriptionController:
            FakeSubscriptionStatusController(SubscriptionStatus.unknown),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pumpAndSettle();

    expect(backend.enqueuedRegenerate, isTrue);
    expect(find.byType(AiAskAiSettingsPage), findsNothing);
  });

  testWidgets(
      'TodoDetailPage manual regenerate allows cloud when subscription is unknown',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    setLargeDisplay(tester);
    final backend = TestBackend(llmProfiles: const <LlmProfile>[]);

    await tester.pumpWidget(
      buildTodoDetailSubject(
        backend,
        cloudAuthController: FakeCloudAuthController(),
        subscriptionController:
            FakeSubscriptionStatusController(SubscriptionStatus.unknown),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('todo_detail_followup_generate_suggestions')),
    );
    await tester.pumpAndSettle();

    expect(backend.enqueuedRegenerate, isTrue);
    expect(find.byType(AiAskAiSettingsPage), findsNothing);
  });
}
