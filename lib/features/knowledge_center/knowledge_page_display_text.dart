import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/history.dart';
import '../../src/rust/knowledge/lint.dart';
import '../../src/rust/knowledge/pages.dart';
import '../memory/memory_display_text.dart';

String knowledgePageStateLabel(Translations t, KnowledgePageState state) {
  return switch (state) {
    KnowledgePageState.active => t.memory.pageStates.active,
    KnowledgePageState.needsReview => t.memory.pageStates.needsReview,
    KnowledgePageState.outdated => t.memory.pageStates.outdated,
    KnowledgePageState.answerMuted => t.memory.pageStates.answerMuted,
    KnowledgePageState.archived => t.memory.pageStates.archived,
    KnowledgePageState.removed => t.memory.pageStates.removed,
  };
}

String knowledgePageTypeLabel(Translations t, KnowledgePageType type) {
  return switch (type) {
    KnowledgePageType.aboutMe => t.memory.sections.aboutMe,
    KnowledgePageType.preferences => t.memory.sections.preferences,
    KnowledgePageType.currentFocus => t.memory.sections.currentFocus,
    KnowledgePageType.activeThreads => t.memory.sections.activeThreads,
    KnowledgePageType.recentEvents => t.memory.sections.recentEvents,
    KnowledgePageType.people => t.memory.sections.people,
    KnowledgePageType.topics => t.memory.sections.topics,
    KnowledgePageType.openQuestions => t.memory.sections.openQuestions,
  };
}

bool knowledgePageSupportsMerge(KnowledgePageType type) {
  return switch (type) {
    KnowledgePageType.people ||
    KnowledgePageType.topics ||
    KnowledgePageType.openQuestions =>
      true,
    _ => false,
  };
}

String knowledgePageUpdatedLabel(Translations t, int updatedAtMs) {
  return formatMemoryUpdatedLabel(t, updatedAtMs: updatedAtMs);
}

String knowledgePageChangeTypeLabel(
  Translations t,
  KnowledgePageChangeType changeType,
) {
  return switch (changeType) {
    KnowledgePageChangeType.created => t.memory.history.created,
    KnowledgePageChangeType.updated => t.memory.history.updated,
    KnowledgePageChangeType.corrected => t.memory.history.corrected,
    KnowledgePageChangeType.downgraded => t.memory.history.downgraded,
    KnowledgePageChangeType.muted => t.memory.history.muted,
    KnowledgePageChangeType.archived => t.memory.history.archived,
    KnowledgePageChangeType.removed => t.memory.history.removed,
    KnowledgePageChangeType.merged => t.memory.history.merged,
  };
}

String knowledgeLintKindLabel(Translations t, KnowledgeLintKind kind) {
  return switch (kind) {
    KnowledgeLintKind.conflict => t.memory.lintKinds.conflict,
    KnowledgeLintKind.staleness => t.memory.lintKinds.staleness,
    KnowledgeLintKind.fragmentation => t.memory.lintKinds.fragmentation,
    KnowledgeLintKind.unusedKnowledge => t.memory.lintKinds.unusedKnowledge,
    KnowledgeLintKind.evidenceWeakness => t.memory.lintKinds.evidenceWeakness,
    KnowledgeLintKind.regenerationRisk => t.memory.lintKinds.regenerationRisk,
  };
}

String knowledgePageEvidenceKindLabel(
  Translations t,
  KnowledgePageEvidenceKind kind,
) {
  return switch (kind) {
    KnowledgePageEvidenceKind.support => t.memory.evidenceKinds.support,
    KnowledgePageEvidenceKind.conflict => t.memory.evidenceKinds.conflict,
    KnowledgePageEvidenceKind.supplement => t.memory.evidenceKinds.supplement,
  };
}
