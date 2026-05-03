import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/secretary/todo_command_models.dart';

void main() {
  group('SecretaryTodoCommand', () {
    test('round-trips snake-case JSON fields', () {
      const command = SecretaryTodoCommand(
        id: 'cmd-1',
        kind: SecretaryTodoCommandKind.reprioritize,
        route: SecretaryTodoCommandRoute.local,
        confidence: 0.93,
        sourceMessageId: 'message-1',
        targetTodoId: 'todo-1',
        targetTitle: 'Submit invoice',
        manualImportanceNudgeScore: 1,
        manualUrgencyNudgeScore: 1,
        reason: 'User asked to make it more important.',
        rawText: 'Make invoice more important',
      );

      final json = command.toJson();

      expect(json['source_message_id'], 'message-1');
      expect(json['target_todo_id'], 'todo-1');
      expect(json['manual_importance_nudge_score'], 1);
      expect(json['manual_urgency_nudge_score'], 1);
      expect(json, isNot(contains('sourceMessageId')));

      final parsed = SecretaryTodoCommand.fromJson(json);
      expect(parsed.kind, SecretaryTodoCommandKind.reprioritize);
      expect(parsed.route, SecretaryTodoCommandRoute.local);
      expect(parsed.targetTodoId, 'todo-1');
      expect(parsed.manualImportanceNudgeScore, 1);
      expect(parsed.manualUrgencyNudgeScore, 1);
      expect(parsed.isValid, isTrue);
    });

    test('validates required fields for update commands', () {
      const updateTitle = SecretaryTodoCommand(
        id: 'cmd-update',
        kind: SecretaryTodoCommandKind.updateTitle,
        route: SecretaryTodoCommandRoute.local,
        confidence: 0.9,
        sourceMessageId: 'message-1',
        targetTodoId: 'todo-1',
        newTitle: 'Submit Stripe invoice',
      );
      expect(updateTitle.isValid, isTrue);
      expect(updateTitle.copyWith(newTitle: '').isValid, isFalse);

      const reschedule = SecretaryTodoCommand(
        id: 'cmd-reschedule',
        kind: SecretaryTodoCommandKind.reschedule,
        route: SecretaryTodoCommandRoute.local,
        confidence: 0.9,
        sourceMessageId: 'message-1',
        targetTodoId: 'todo-1',
        dueAtMs: 1770000000000,
      );
      expect(reschedule.isValid, isTrue);
      expect(reschedule.copyWith(clearDueAtMs: true).isValid, isFalse);

      const setStatus = SecretaryTodoCommand(
        id: 'cmd-status',
        kind: SecretaryTodoCommandKind.setStatus,
        route: SecretaryTodoCommandRoute.local,
        confidence: 0.9,
        sourceMessageId: 'message-1',
        targetTodoId: 'todo-1',
        newStatus: 'done',
      );
      expect(setStatus.isValid, isTrue);
      expect(setStatus.copyWith(newStatus: '').isValid, isFalse);
    });

    test('validates dismiss and reprioritize requirements', () {
      const dismiss = SecretaryTodoCommand(
        id: 'cmd-dismiss',
        kind: SecretaryTodoCommandKind.dismiss,
        route: SecretaryTodoCommandRoute.local,
        confidence: 0.9,
        sourceMessageId: 'message-1',
        targetTodoId: 'todo-1',
      );
      expect(dismiss.isValid, isTrue);
      expect(dismiss.copyWith(targetTodoId: '').isValid, isFalse);

      const reprioritize = SecretaryTodoCommand(
        id: 'cmd-priority',
        kind: SecretaryTodoCommandKind.reprioritize,
        route: SecretaryTodoCommandRoute.local,
        confidence: 0.9,
        sourceMessageId: 'message-1',
        targetTodoId: 'todo-1',
        manualImportanceNudgeScore: 1,
      );
      expect(reprioritize.isValid, isTrue);
      expect(
        reprioritize
            .copyWith(
              clearManualImportanceNudgeScore: true,
              clearManualUrgencyNudgeScore: true,
            )
            .isValid,
        isFalse,
      );
    });
  });
}
