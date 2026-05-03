import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/secretary/todo_command_models.dart';
import 'package:secondloop/core/secretary/todo_command_risk_policy.dart';

void main() {
  group('SecretaryTodoCommandRiskPolicy', () {
    const policy = SecretaryTodoCommandRiskPolicy();

    test('auto-applies low-risk explicit commands', () {
      expect(
        policy.classify(
          _command(
            kind: SecretaryTodoCommandKind.create,
            targetTodoId: null,
            newTitle: 'Submit invoice',
          ),
        ),
        SecretaryTodoCommandRisk.autoApply,
      );
      expect(
        policy.classify(
          _command(
            kind: SecretaryTodoCommandKind.reschedule,
            dueAtMs: 1770000000000,
          ),
        ),
        SecretaryTodoCommandRisk.autoApply,
      );
      expect(
        policy.classify(
          _command(
            kind: SecretaryTodoCommandKind.reprioritize,
            manualImportanceNudgeScore: 1,
            manualUrgencyNudgeScore: 1,
          ),
        ),
        SecretaryTodoCommandRisk.autoApply,
      );
    });

    test('reviews medium-risk title changes', () {
      expect(
        policy.classify(
          _command(
            kind: SecretaryTodoCommandKind.updateTitle,
            newTitle: 'Submit Stripe invoice',
          ),
        ),
        SecretaryTodoCommandRisk.review,
      );
    });

    test('confirms destructive and batch commands', () {
      expect(
        policy.classify(_command(kind: SecretaryTodoCommandKind.dismiss)),
        SecretaryTodoCommandRisk.confirm,
      );
      expect(
        policy.classify(_command(kind: SecretaryTodoCommandKind.batchUpdate)),
        SecretaryTodoCommandRisk.confirm,
      );
    });

    test('low confidence commands are reviewed or rejected', () {
      expect(
        policy.classify(
          _command(
            kind: SecretaryTodoCommandKind.reschedule,
            confidence: 0.7,
            dueAtMs: 1770000000000,
          ),
        ),
        SecretaryTodoCommandRisk.review,
      );
      expect(
        policy.classify(
          _command(
            kind: SecretaryTodoCommandKind.reschedule,
            confidence: 0.5,
            dueAtMs: 1770000000000,
          ),
        ),
        SecretaryTodoCommandRisk.reject,
      );
    });

    test('invalid or none commands are rejected', () {
      expect(
        policy.classify(_command(kind: SecretaryTodoCommandKind.none)),
        SecretaryTodoCommandRisk.reject,
      );
      expect(
        policy.classify(
          _command(kind: SecretaryTodoCommandKind.updateTitle),
        ),
        SecretaryTodoCommandRisk.reject,
      );
    });
  });
}

SecretaryTodoCommand _command({
  required SecretaryTodoCommandKind kind,
  double confidence = 0.9,
  String? targetTodoId = 'todo-1',
  String? newTitle,
  String? newStatus,
  int? dueAtMs,
  int? manualImportanceNudgeScore,
  int? manualUrgencyNudgeScore,
}) {
  return SecretaryTodoCommand(
    id: 'cmd-${kind.name}',
    kind: kind,
    route: SecretaryTodoCommandRoute.local,
    confidence: confidence,
    sourceMessageId: 'message-1',
    targetTodoId: targetTodoId,
    newTitle: newTitle,
    newStatus: newStatus ??
        (kind == SecretaryTodoCommandKind.setStatus ? 'done' : null),
    dueAtMs: dueAtMs,
    manualImportanceNudgeScore: manualImportanceNudgeScore,
    manualUrgencyNudgeScore: manualUrgencyNudgeScore,
  );
}
