import '../../src/rust/knowledge/models.dart';
import '../../src/rust/knowledge/pages.dart';
import 'chat_answer_evidence_models.dart';

bool isKnowledgePageDocumentId(String documentId) {
  return documentId.trim().startsWith('page:');
}

bool canOpenEvidenceMemoryCard(
  String documentId, {
  required bool hasPagesBackend,
  required bool hasViewerBackend,
}) {
  return isKnowledgePageDocumentId(documentId)
      ? hasPagesBackend
      : hasViewerBackend;
}

bool canMutateEvidenceMemoryCard(
  String documentId, {
  required bool hasPagesBackend,
  required bool hasKnowledgeBackend,
  required bool hasViewerBackend,
}) {
  return isKnowledgePageDocumentId(documentId)
      ? hasPagesBackend
      : (hasKnowledgeBackend && hasViewerBackend);
}

String resolveKnowledgePageCorrectionBody({
  required String? existingBody,
  required String summary,
  String? editedBody,
}) {
  final normalizedEdited = editedBody?.trim();
  if (normalizedEdited != null && normalizedEdited.isNotEmpty) {
    return editedBody!;
  }
  final normalizedExisting = existingBody?.trim();
  if (normalizedExisting != null && normalizedExisting.isNotEmpty) {
    return existingBody!;
  }
  return summary;
}

String _knowledgePageEvidenceStatusName(KnowledgePage page) {
  switch (page.state) {
    case KnowledgePageState.outdated:
      return KnowledgeMemoryStatus.maybeOutdated.name;
    case KnowledgePageState.active:
      return page.humanCorrected
          ? KnowledgeMemoryStatus.confirmed.name
          : KnowledgeMemoryStatus.inferred.name;
    case KnowledgePageState.needsReview:
    case KnowledgePageState.answerMuted:
    case KnowledgePageState.archived:
    case KnowledgePageState.removed:
      return KnowledgeMemoryStatus.inferred.name;
  }
}

ChatAnswerEvidenceMemoryCard knowledgePageMemoryCardFromDetail(
  ChatAnswerEvidenceMemoryCard card,
  KnowledgePageDetail detail,
) {
  final page = detail.page;
  return card.copyWith(
    title: page.title,
    summary: page.currentSummary,
    body: page.currentBody,
    status: _knowledgePageEvidenceStatusName(page),
    sourceCount: page.sourceCount.toInt(),
    updatedAtMs: page.updatedAtMs.toInt(),
    useForAskAi: page.answerPolicy.defaultAllowed,
    isDeleted: page.state == KnowledgePageState.removed,
    markedInaccurate: page.state == KnowledgePageState.needsReview,
  );
}
