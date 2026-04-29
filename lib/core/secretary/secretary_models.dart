enum SecretaryMemoryState {
  active,
  needsReview,
  archived,
}

class SecretaryMemoryProposal {
  const SecretaryMemoryProposal({
    required this.id,
    required this.sourceMessageId,
    required this.kind,
    required this.title,
    required this.body,
    required this.confidence,
    required this.createdAtMs,
    this.actionHint = 'propose',
  });

  final String id;
  final String sourceMessageId;
  final String kind;
  final String title;
  final String body;
  final double confidence;
  final int createdAtMs;
  final String actionHint;
}

class SecretaryMemoryPage {
  const SecretaryMemoryPage({
    required this.id,
    required this.title,
    required this.body,
    required this.state,
    required this.updatedAtMs,
    this.kind = 'fact',
    this.sourceMessageId,
  });

  final String id;
  final String title;
  final String body;
  final SecretaryMemoryState state;
  final int updatedAtMs;
  final String kind;
  final String? sourceMessageId;
}

class SecretaryPlanItem {
  const SecretaryPlanItem({
    required this.id,
    required this.todoId,
    required this.title,
    required this.reason,
    this.dueAtMs,
    this.requiresConfirmation = false,
  });

  final String id;
  final String todoId;
  final String title;
  final String reason;
  final int? dueAtMs;
  final bool requiresConfirmation;
}

class SecretaryPlanSections {
  const SecretaryPlanSections({
    required this.focus,
    required this.dueSoon,
    required this.needsDecision,
    required this.missingNextAction,
  });

  const SecretaryPlanSections.empty()
      : focus = const <SecretaryPlanItem>[],
        dueSoon = const <SecretaryPlanItem>[],
        needsDecision = const <SecretaryPlanItem>[],
        missingNextAction = const <SecretaryPlanItem>[];

  final List<SecretaryPlanItem> focus;
  final List<SecretaryPlanItem> dueSoon;
  final List<SecretaryPlanItem> needsDecision;
  final List<SecretaryPlanItem> missingNextAction;

  bool get isEmpty =>
      focus.isEmpty &&
      dueSoon.isEmpty &&
      needsDecision.isEmpty &&
      missingNextAction.isEmpty;

  int get itemCount =>
      focus.length +
      dueSoon.length +
      needsDecision.length +
      missingNextAction.length;

  Iterable<SecretaryPlanItem> get allItems sync* {
    yield* focus;
    yield* dueSoon;
    yield* needsDecision;
    yield* missingNextAction;
  }
}

class SecretaryPlan {
  const SecretaryPlan({
    required this.id,
    required this.title,
    required this.generatedAtMs,
    required this.route,
    required this.sections,
  });

  final String id;
  final String title;
  final int generatedAtMs;
  final String route;
  final SecretaryPlanSections sections;

  int get itemCount => sections.itemCount;

  int get requiresConfirmationCount =>
      sections.allItems.where((item) => item.requiresConfirmation).length;
}
