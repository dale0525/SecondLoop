import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/todo_followup_generation_gate.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('preview selection reserves one auto slot for mixed backlog', () {
    final previewJobs = <TodoFollowupGenerationJob>[
      for (var index = 0; index < 6; index += 1)
        TodoFollowupGenerationJob(
          todoId: 'todo_manual_$index',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: index,
        ),
      const TodoFollowupGenerationJob(
        todoId: 'todo_auto_1',
        triggerKind: 'auto_create',
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        includeManualFollowups: false,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 10,
      ),
    ];

    final selected = selectTodoFollowupGenerationPreviewJobs(
      previewJobs,
      batchLimit: 5,
    );

    expect(selected, hasLength(5));
    expect(
      selected.where((job) => job.triggerKind == 'manual_regenerate'),
      hasLength(4),
    );
    expect(selected.any((job) => job.todoId == 'todo_auto_1'), isTrue);
  });

  test('preview refetch triggers when the initial batch is all manual', () {
    final previewJobs = <TodoFollowupGenerationJob>[
      for (var index = 0; index < 5; index += 1)
        TodoFollowupGenerationJob(
          todoId: 'todo_manual_$index',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: index,
        ),
    ];

    expect(
      shouldRefetchTodoFollowupGenerationPreviewJobs(
        previewJobs,
        batchLimit: 5,
      ),
      isTrue,
    );
  });

  test('generation passes keep one auto slot when manual jobs fill the batch',
      () {
    final previewJobs = <TodoFollowupGenerationJob>[
      for (var index = 0; index < 4; index += 1)
        TodoFollowupGenerationJob(
          todoId: 'todo_manual_$index',
          triggerKind: 'manual_regenerate',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          lastError: null,
          includeManualFollowups: true,
          taskTypeHint: 'research',
          createdAtMs: 0,
          updatedAtMs: index,
        ),
      const TodoFollowupGenerationJob(
        todoId: 'todo_auto_1',
        triggerKind: 'auto_create',
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        includeManualFollowups: false,
        taskTypeHint: 'research',
        createdAtMs: 0,
        updatedAtMs: 10,
      ),
    ];

    final plans = buildTodoFollowupGenerationPassPlans(previewJobs);

    expect(plans, hasLength(2));
    expect(plans[0].hasManualRegenerateDueJob, isTrue);
    expect(plans[0].jobs, hasLength(4));
    expect(plans[1].hasManualRegenerateDueJob, isFalse);
    expect(
      plans[1].jobs.map((job) => job.todoId).toList(growable: false),
      const <String>['todo_auto_1'],
    );
  });
}
