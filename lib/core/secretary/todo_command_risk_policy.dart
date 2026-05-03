import 'todo_command_models.dart';

enum SecretaryTodoCommandRisk {
  autoApply,
  review,
  confirm,
  reject,
}

final class SecretaryTodoCommandRiskPolicy {
  const SecretaryTodoCommandRiskPolicy();

  SecretaryTodoCommandRisk classify(SecretaryTodoCommand command) {
    if (!command.isValid) return SecretaryTodoCommandRisk.reject;
    if (command.confidence < 0.65) return SecretaryTodoCommandRisk.reject;

    final base = switch (command.kind) {
      SecretaryTodoCommandKind.create => SecretaryTodoCommandRisk.autoApply,
      SecretaryTodoCommandKind.reschedule => SecretaryTodoCommandRisk.autoApply,
      SecretaryTodoCommandKind.setStatus => SecretaryTodoCommandRisk.autoApply,
      SecretaryTodoCommandKind.reprioritize =>
        SecretaryTodoCommandRisk.autoApply,
      SecretaryTodoCommandKind.updateTitle => SecretaryTodoCommandRisk.review,
      SecretaryTodoCommandKind.dismiss => SecretaryTodoCommandRisk.confirm,
      SecretaryTodoCommandKind.batchUpdate => SecretaryTodoCommandRisk.confirm,
      SecretaryTodoCommandKind.none => SecretaryTodoCommandRisk.reject,
    };

    if (command.confidence < 0.82 &&
        base == SecretaryTodoCommandRisk.autoApply) {
      return SecretaryTodoCommandRisk.review;
    }
    return base;
  }
}
