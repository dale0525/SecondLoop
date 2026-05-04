import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/dynamic_app_harness.dart';
import 'support/dynamic_test_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chat message can drive a todo command card and apply it',
      (tester) async {
    final backend = DynamicTestBackend(
      todos: [
        DynamicTestBackend.todo(
          id: 'todo:invoice',
          title: 'Submit invoice',
        ),
      ],
    );
    final harness = await DynamicAppHarness.launch(
      tester,
      backend: backend,
    );

    await harness.sendChatMessage(
      'rename Submit invoice to Submit Stripe invoice',
    );
    await harness.waitForTodoCommandCard('todo-command-m1');

    expect(backend.insertedUserMessages.map((message) => message.content), [
      'rename Submit invoice to Submit Stripe invoice',
    ]);

    await harness.tapByKey('secretary_todo_command_apply_todo-command-m1');
    await harness.waitForBackend(
      'todo command title update',
      () => backend.todoById('todo:invoice')?.title == 'Submit Stripe invoice',
    );

    expect(backend.upsertTodoCalls, 1);
  });

  testWidgets('todo command can be reviewed before applying', (tester) async {
    final backend = DynamicTestBackend(
      todos: [
        DynamicTestBackend.todo(
          id: 'todo:invoice',
          title: 'Submit invoice',
        ),
      ],
    );
    final harness = await DynamicAppHarness.launch(
      tester,
      backend: backend,
    );

    await harness.sendChatMessage(
      'rename Submit invoice to Submit Stripe invoice',
    );
    await harness.waitForTodoCommandCard('todo-command-m1');

    expect(
      find.byKey(
        const ValueKey('secretary_todo_command_apply_todo-command-m1'),
      ),
      findsOneWidget,
    );

    await harness.tapByKey('secretary_todo_command_review_todo-command-m1');
    await harness.pumpUntilFound(
      find.byKey(const ValueKey('todo_command_review_apply_todo-command-m1')),
      description: 'todo command review apply action',
    );
    expect(backend.todoById('todo:invoice')?.title, 'Submit invoice');

    await harness.tapByKey('todo_command_review_apply_todo-command-m1');
    await harness.waitForBackend(
      'reviewed todo command title update',
      () => backend.todoById('todo:invoice')?.title == 'Submit Stripe invoice',
    );

    expect(backend.upsertTodoCalls, 1);
  });

  testWidgets('memory preference message persists and renders a proposal',
      (tester) async {
    final backend = DynamicTestBackend();
    final harness = await DynamicAppHarness.launch(
      tester,
      backend: backend,
    );

    await harness.sendChatMessage('Remember that I prefer morning meetings.');
    await harness.waitForMemoryCard('m1');
    await harness.waitForBackend(
      'pending memory proposal',
      () => backend.memoryProposals.any((proposal) {
        return proposal.sourceMessageId == 'm1' && proposal.state == 'pending';
      }),
    );

    final pendingForMessage = backend.memoryProposals.where((proposal) {
      return proposal.sourceMessageId == 'm1' && proposal.state == 'pending';
    }).toList(growable: false);

    expect(
      pendingForMessage,
      hasLength(1),
      reason: backend.debugTrace.join('\n'),
    );
    expect(pendingForMessage.single.title, contains('morning meetings'));
  });

  testWidgets('planning card opens review and handles a suggestion',
      (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = DynamicTestBackend(
      todos: [
        DynamicTestBackend.todo(
          id: 'todo:plan',
          title: 'Write launch plan',
          dueAtMs: nowMs,
        ),
      ],
    );
    final harness = await DynamicAppHarness.launch(
      tester,
      backend: backend,
    );

    await harness.tapByKey('secretary_plan_view');
    await harness.pumpUntilFound(
      find.byKey(const ValueKey('secretary_plan_accept_plan-item-todo:plan')),
      description: 'planning review accept action',
    );

    await harness.waitForBackend(
      'persisted planning output',
      () => backend.planningOutputs.isNotEmpty,
    );
    await harness.tapByKey('secretary_plan_accept_plan-item-todo:plan');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('secretary_plan_accept_plan-item-todo:plan')),
      findsNothing,
    );
    expect(backend.upsertPlanningOutputCalls, greaterThanOrEqualTo(1));
  });
}
