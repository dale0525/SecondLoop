import '../../src/rust/db.dart';
import 'ai_routing.dart';
import 'todo_followup_generation_runner.dart';

const _kPreviewRefetchLimitMultiplier = 128;
const _kPendingSetupRetryWindow = Duration(minutes: 15);
const _kPendingSetupMediumRetryDelay = Duration(seconds: 30);
const _kPendingSetupLongRetryDelay = Duration(minutes: 1);

final class TodoFollowupGenerationPassPlan {
  const TodoFollowupGenerationPassPlan({
    required this.jobs,
    required this.hasManualRegenerateDueJob,
  });

  final List<TodoFollowupGenerationJob> jobs;
  final bool hasManualRegenerateDueJob;
}

List<TodoFollowupGenerationPassPlan> buildTodoFollowupGenerationPassPlans(
  List<TodoFollowupGenerationJob> previewJobs,
) {
  final manualJobs = previewJobs
      .where((job) => job.triggerKind == 'manual_regenerate')
      .toList(growable: false);
  final autoJobs = previewJobs
      .where((job) => job.triggerKind != 'manual_regenerate')
      .toList(growable: false);

  return <TodoFollowupGenerationPassPlan>[
    if (manualJobs.isNotEmpty)
      TodoFollowupGenerationPassPlan(
        jobs: manualJobs,
        hasManualRegenerateDueJob: true,
      ),
    if (autoJobs.isNotEmpty)
      TodoFollowupGenerationPassPlan(
        jobs: autoJobs,
        hasManualRegenerateDueJob: false,
      ),
  ];
}

bool shouldRefetchTodoFollowupGenerationPreviewJobs(
  List<TodoFollowupGenerationJob> previewJobs, {
  required int batchLimit,
}) {
  if (previewJobs.length < batchLimit) {
    return false;
  }
  return previewJobs.every((job) => job.triggerKind == 'manual_regenerate');
}

List<TodoFollowupGenerationJob> selectTodoFollowupGenerationPreviewJobs(
  List<TodoFollowupGenerationJob> dueJobs, {
  required int batchLimit,
}) {
  if (dueJobs.length <= batchLimit) {
    return dueJobs;
  }

  final manualJobs = dueJobs
      .where((job) => job.triggerKind == 'manual_regenerate')
      .toList(growable: false);
  final autoJobs = dueJobs
      .where((job) => job.triggerKind != 'manual_regenerate')
      .toList(growable: false);

  if (manualJobs.isEmpty || autoJobs.isEmpty || batchLimit <= 1) {
    return dueJobs.take(batchLimit).toList(growable: false);
  }

  final selected = <TodoFollowupGenerationJob>[
    ...manualJobs.take(batchLimit - 1),
    autoJobs.first,
  ];
  var remaining = batchLimit - selected.length;
  if (remaining > 0) {
    selected.addAll(manualJobs.skip(batchLimit - 1).take(remaining));
    remaining = batchLimit - selected.length;
  }
  if (remaining > 0) {
    selected.addAll(autoJobs.skip(1).take(remaining));
  }
  return selected;
}

Future<List<TodoFollowupGenerationJob>> loadTodoFollowupGenerationPreviewJobs(
  TodoFollowupGenerationStore store, {
  required int nowMs,
  required int batchLimit,
}) async {
  final initialJobs = await store.listDueJobs(nowMs: nowMs, limit: batchLimit);
  if (!shouldRefetchTodoFollowupGenerationPreviewJobs(
    initialJobs,
    batchLimit: batchLimit,
  )) {
    return initialJobs;
  }

  var expandedJobs = initialJobs;
  var requestedLimit = batchLimit * 2;
  final maxRequestedLimit = batchLimit * _kPreviewRefetchLimitMultiplier;
  while (true) {
    final nextJobs = await store.listDueJobs(
      nowMs: nowMs,
      limit: requestedLimit,
    );
    if (nextJobs.length <= expandedJobs.length) {
      break;
    }
    expandedJobs = nextJobs;
    if (!shouldRefetchTodoFollowupGenerationPreviewJobs(
      expandedJobs,
      batchLimit: batchLimit,
    )) {
      break;
    }
    if (expandedJobs.length < requestedLimit) {
      break;
    }
    if (requestedLimit >= maxRequestedLimit) {
      break;
    }
    requestedLimit *= 2;
    if (requestedLimit > maxRequestedLimit) {
      requestedLimit = maxRequestedLimit;
    }
  }

  final selectedJobs = selectTodoFollowupGenerationPreviewJobs(
    expandedJobs,
    batchLimit: batchLimit,
  );
  if (selectedJobs.length < batchLimit ||
      selectedJobs.any((job) => job.triggerKind != 'manual_regenerate')) {
    return selectedJobs;
  }

  final dueAutoJobs = await store.listDueAutoJobs(nowMs: nowMs, limit: 1);
  if (dueAutoJobs.isEmpty) {
    return selectedJobs;
  }

  final firstAutoJob = dueAutoJobs.first;
  if (selectedJobs.any((job) => job.todoId == firstAutoJob.todoId)) {
    return selectedJobs;
  }

  return <TodoFollowupGenerationJob>[
    ...selectedJobs.take(batchLimit - 1),
    firstAutoJob,
  ];
}

Future<List<TodoFollowupGenerationJob>> loadDueAutoFollowupGenerationJobs(
  TodoFollowupGenerationStore store, {
  required int nowMs,
  required int limit,
}) async {
  final requestedLimit = limit <= 0 ? 1 : limit;
  var overfetchLimit = requestedLimit <= 1 ? 2 : requestedLimit;

  while (true) {
    final candidateJobs = await store.listDueJobs(
      nowMs: nowMs,
      limit: overfetchLimit,
    );
    final autoJobs = candidateJobs
        .where((job) => job.triggerKind != 'manual_regenerate')
        .take(requestedLimit)
        .toList(growable: false);
    if (autoJobs.length >= requestedLimit) {
      return autoJobs;
    }
    if (candidateJobs.length < overfetchLimit) {
      return autoJobs;
    }
    overfetchLimit *= 2;
  }
}

Future<void> finalizeTodoFollowupGenerationJobsForNeedsSetup(
  TodoFollowupGenerationStore store,
  List<TodoFollowupGenerationJob> jobs, {
  required int nowMs,
}) async {
  for (final job in jobs) {
    // Product decision: needs-setup should clear background auto jobs, but a
    // user-initiated regenerate must surface as canceled instead of silently
    // disappearing.
    if (job.triggerKind == 'manual_regenerate') {
      await store.markJobCanceled(todoId: job.todoId, nowMs: nowMs);
      continue;
    }
    await store.markJobSkipped(todoId: job.todoId, nowMs: nowMs);
  }
}

Future<int?> deferTodoFollowupGenerationJobsForRetry(
  TodoFollowupGenerationStore store,
  List<TodoFollowupGenerationJob> jobs, {
  required int nowMs,
  required Duration retryDelay,
  required String lastError,
  int maxAttempts = kTodoFollowupGenerationMaxManualAttempts,
}) async {
  int? earliestNextRetryAtMs;
  for (final job in jobs) {
    // Product decision: when the route is temporarily unavailable, manual
    // regenerate jobs stay retryable, while background auto jobs are drained so
    // they do not keep resurfacing without explicit user intent.
    if (job.triggerKind != 'manual_regenerate') {
      await store.markJobSkipped(todoId: job.todoId, nowMs: nowMs);
      continue;
    }
    final attempts = job.attempts.toInt() + 1;
    if (attempts >= maxAttempts) {
      await store.markJobCanceled(todoId: job.todoId, nowMs: nowMs);
      continue;
    }
    final nextRetryAtMs = nowMs + retryDelay.inMilliseconds;
    await store.markJobFailed(
      todoId: job.todoId,
      attempts: attempts,
      nextRetryAtMs: nextRetryAtMs,
      lastError: lastError,
      nowMs: nowMs,
    );
    earliestNextRetryAtMs = minTodoFollowupGenerationRetryAtMs(
      earliestNextRetryAtMs,
      nextRetryAtMs,
    );
  }
  return earliestNextRetryAtMs;
}

bool shouldDeferTodoFollowupGenerationNeedsSetup({
  required bool hasManualRegenerateDueJob,
  required SubscriptionStatus subscriptionStatus,
  required String gatewayBaseUrl,
}) {
  if (hasManualRegenerateDueJob) {
    return false;
  }
  if (subscriptionStatus == SubscriptionStatus.notEntitled) {
    return false;
  }
  if (gatewayBaseUrl.trim().isEmpty) {
    return false;
  }
  return true;
}

Future<int?> deferTodoFollowupGenerationJobsForPendingEntitlement(
  TodoFollowupGenerationStore store,
  List<TodoFollowupGenerationJob> jobs, {
  required int nowMs,
  required Duration retryDelay,
  required String lastError,
  Duration maxRetryWindow = _kPendingSetupRetryWindow,
}) async {
  int? earliestNextRetryAtMs;
  for (final job in jobs) {
    final jobAgeMs = nowMs - job.createdAtMs.toInt();
    if (jobAgeMs >= maxRetryWindow.inMilliseconds) {
      await store.markJobSkipped(todoId: job.todoId, nowMs: nowMs);
      continue;
    }
    final nextRetryDelay = _pendingSetupRetryDelay(
      jobAgeMs: jobAgeMs,
      retryDelay: retryDelay,
    );
    final nextRetryAtMs = nowMs + nextRetryDelay.inMilliseconds;
    await store.markJobFailed(
      todoId: job.todoId,
      attempts: job.attempts.toInt(),
      nextRetryAtMs: nextRetryAtMs,
      lastError: lastError,
      nowMs: nowMs,
    );
    earliestNextRetryAtMs = minTodoFollowupGenerationRetryAtMs(
      earliestNextRetryAtMs,
      nextRetryAtMs,
    );
  }
  return earliestNextRetryAtMs;
}

Duration _pendingSetupRetryDelay({
  required int jobAgeMs,
  required Duration retryDelay,
}) {
  if (jobAgeMs >= _kPendingSetupLongRetryDelay.inMilliseconds) {
    return _kPendingSetupLongRetryDelay;
  }
  if (jobAgeMs >= _kPendingSetupMediumRetryDelay.inMilliseconds) {
    return _kPendingSetupMediumRetryDelay;
  }
  return retryDelay;
}

int? minTodoFollowupGenerationRetryAtMs(int? current, int? candidate) {
  if (candidate == null) {
    return current;
  }
  if (current == null || candidate < current) {
    return candidate;
  }
  return current;
}

Duration computeTodoFollowupGenerationNextDelay({
  required int nowMs,
  required int previewJobCount,
  required int batchLimit,
  required bool didUpdateJobs,
  required int? earliestNextRetryAtMs,
  bool didOnlyScheduleFutureRetries = false,
  Duration idleInterval = const Duration(seconds: 30),
  Duration drainInterval = const Duration(seconds: 2),
}) {
  if (didOnlyScheduleFutureRetries && earliestNextRetryAtMs != null) {
    final retryDelayMs = earliestNextRetryAtMs - nowMs;
    if (retryDelayMs <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: retryDelayMs);
  }

  if (didUpdateJobs && previewJobCount >= batchLimit) {
    return drainInterval;
  }

  if (earliestNextRetryAtMs != null) {
    final retryDelayMs = earliestNextRetryAtMs - nowMs;
    if (retryDelayMs <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: retryDelayMs);
  }

  return idleInterval;
}
