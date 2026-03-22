import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/todo_followup_generation_gate.dart';
import 'package:secondloop/core/ai/todo_followup_generation_runner.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test(
      'unknown entitlement defers automatic needs-setup jobs when cloud may still resolve',
      () {
    final shouldDefer = shouldDeferTodoFollowupGenerationNeedsSetup(
      hasManualRegenerateDueJob: false,
      subscriptionStatus: SubscriptionStatus.unknown,
      gatewayBaseUrl: 'https://example.com',
    );

    expect(shouldDefer, isTrue);
  });

  test(
      'needs-setup defer stays disabled only for manual jobs or terminal setups',
      () {
    expect(
      shouldDeferTodoFollowupGenerationNeedsSetup(
        hasManualRegenerateDueJob: true,
        subscriptionStatus: SubscriptionStatus.unknown,
        gatewayBaseUrl: 'https://example.com',
      ),
      isFalse,
    );
    expect(
      shouldDeferTodoFollowupGenerationNeedsSetup(
        hasManualRegenerateDueJob: false,
        subscriptionStatus: SubscriptionStatus.notEntitled,
        gatewayBaseUrl: 'https://example.com',
      ),
      isFalse,
    );
    expect(
      shouldDeferTodoFollowupGenerationNeedsSetup(
        hasManualRegenerateDueJob: false,
        subscriptionStatus: SubscriptionStatus.unknown,
        gatewayBaseUrl: '',
      ),
      isFalse,
    );
    expect(
      shouldDeferTodoFollowupGenerationNeedsSetup(
        hasManualRegenerateDueJob: false,
        subscriptionStatus: SubscriptionStatus.entitled,
        gatewayBaseUrl: 'https://example.com',
      ),
      isTrue,
    );
    expect(
      shouldDeferTodoFollowupGenerationNeedsSetup(
        hasManualRegenerateDueJob: false,
        subscriptionStatus: SubscriptionStatus.unknown,
        gatewayBaseUrl: 'https://example.com',
      ),
      isTrue,
    );
  });

  test(
      'pending entitlement defer retries automatic jobs instead of draining them',
      () async {
    final store = _RecordingTodoFollowupGenerationStore();

    await deferTodoFollowupGenerationJobsForPendingEntitlement(
      store,
      const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_auto',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 1,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      nowMs: 500,
      retryDelay: const Duration(seconds: 10),
      lastError: 'followup_subscription_pending',
    );

    expect(store.failedTodoIds, const <String>['todo_auto']);
    expect(store.failedAttempts, const <int>[1]);
    expect(store.failedRetryAtMs, const <int>[10500]);
    expect(store.failedErrors, const <String>['followup_subscription_pending']);
    expect(store.skippedTodoIds, isEmpty);
    expect(store.canceledTodoIds, isEmpty);
  });

  test('pending entitlement defer backs off based on job age', () async {
    final store = _RecordingTodoFollowupGenerationStore();

    await deferTodoFollowupGenerationJobsForPendingEntitlement(
      store,
      const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_auto_pending',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 1,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      nowMs: const Duration(minutes: 2).inMilliseconds,
      retryDelay: const Duration(seconds: 10),
      lastError: 'followup_subscription_pending',
    );

    expect(store.failedRetryAtMs, const <int>[180000]);
    expect(store.skippedTodoIds, isEmpty);
  });

  test('pending entitlement defer drains aged automatic jobs after timeout',
      () async {
    final store = _RecordingTodoFollowupGenerationStore();

    await deferTodoFollowupGenerationJobsForPendingEntitlement(
      store,
      const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_auto_pending',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 1,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      nowMs: const Duration(minutes: 16).inMilliseconds,
      retryDelay: const Duration(seconds: 10),
      lastError: 'followup_subscription_pending',
    );

    expect(store.failedTodoIds, isEmpty);
    expect(store.skippedTodoIds, const <String>['todo_auto_pending']);
    expect(store.canceledTodoIds, isEmpty);
  });

  test('next delay honors earliest retry when batch is not saturated', () {
    final delay = computeTodoFollowupGenerationNextDelay(
      nowMs: 1000,
      previewJobCount: 1,
      batchLimit: 5,
      didUpdateJobs: true,
      earliestNextRetryAtMs: 11000,
    );

    expect(delay, const Duration(seconds: 10));
  });

  test('next delay keeps draining when current batch is saturated', () {
    final delay = computeTodoFollowupGenerationNextDelay(
      nowMs: 1000,
      previewJobCount: 5,
      batchLimit: 5,
      didUpdateJobs: true,
      earliestNextRetryAtMs: 11000,
    );

    expect(delay, const Duration(seconds: 2));
  });

  test(
      'next delay waits for retry when a saturated batch only scheduled future retries',
      () {
    final delay = computeTodoFollowupGenerationNextDelay(
      nowMs: 1000,
      previewJobCount: 5,
      batchLimit: 5,
      didUpdateJobs: true,
      earliestNextRetryAtMs: 11000,
      didOnlyScheduleFutureRetries: true,
    );

    expect(delay, const Duration(seconds: 10));
  });

  test('next delay returns zero when retry deadline is already due', () {
    final delay = computeTodoFollowupGenerationNextDelay(
      nowMs: 5000,
      previewJobCount: 1,
      batchLimit: 5,
      didUpdateJobs: false,
      earliestNextRetryAtMs: 5000,
    );

    expect(delay, Duration.zero);
  });

  test('pending entitlement defer reports earliest retry across mixed ages',
      () async {
    final store = _RecordingTodoFollowupGenerationStore();

    final earliestRetryAtMs =
        await deferTodoFollowupGenerationJobsForPendingEntitlement(
      store,
      const <TodoFollowupGenerationJob>[
        TodoFollowupGenerationJob(
          todoId: 'todo_short',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 1,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        TodoFollowupGenerationJob(
          todoId: 'todo_medium',
          triggerKind: 'auto_create',
          status: 'pending',
          attempts: 2,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: false,
          taskTypeHint: 'research',
          createdAtMs: 20000,
          updatedAtMs: 0,
        ),
      ],
      nowMs: const Duration(seconds: 45).inMilliseconds,
      retryDelay: const Duration(seconds: 10),
      lastError: 'followup_subscription_pending',
    );

    expect(earliestRetryAtMs, 55000);
    expect(store.failedRetryAtMs, const <int>[75000, 55000]);
  });
}

final class _RecordingTodoFollowupGenerationStore
    implements TodoFollowupGenerationStore {
  final List<String> failedTodoIds = <String>[];
  final List<int> failedAttempts = <int>[];
  final List<int> failedRetryAtMs = <int>[];
  final List<String> failedErrors = <String>[];
  final List<String> skippedTodoIds = <String>[];
  final List<String> canceledTodoIds = <String>[];

  @override
  Future<Todo?> getTodo(String todoId) async => null;

  @override
  Future<void> dismissTodoFollowupSuggestions({
    required String todoId,
    required List<String> suggestionIds,
  }) async {}

  @override
  Future<List<TodoActivity>> listTodoActivities(String todoId) async =>
      const <TodoActivity>[];

  @override
  Future<List<TodoFollowupGenerationJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async =>
      const <TodoFollowupGenerationJob>[];

  @override
  Future<List<TodoFollowupSuggestion>> listTodoFollowupSuggestions(
    String todoId,
  ) async =>
      const <TodoFollowupSuggestion>[];

  @override
  Future<void> markJobCanceled({
    required String todoId,
    required int nowMs,
  }) async {
    canceledTodoIds.add(todoId);
  }

  @override
  Future<void> markJobFailed({
    required String todoId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    failedTodoIds.add(todoId);
    failedAttempts.add(attempts);
    failedRetryAtMs.add(nextRetryAtMs);
    failedErrors.add(lastError);
  }

  @override
  Future<void> markJobRunning({
    required String todoId,
    required int nowMs,
  }) async {}

  @override
  Future<void> markJobSkipped({
    required String todoId,
    required int nowMs,
  }) async {
    skippedTodoIds.add(todoId);
  }

  @override
  Future<void> markJobSucceeded({
    required String todoId,
    required int nowMs,
  }) async {}

  @override
  Future<void> upsertGeneratedTodoFollowupSuggestions({
    required String todoId,
    required List<TodoFollowupSuggestionDraftInput> suggestions,
    required String source,
    String? generationKey,
  }) async {}
}
