import '../../src/rust/knowledge/models.dart';
import '../../src/rust/knowledge/pages.dart';
import 'chat_answer_evidence_models.dart';

class KnowledgePageCorrectionPatch {
  const KnowledgePageCorrectionPatch({
    this.title,
    this.summary,
    this.body,
  });

  final String? title;
  final String? summary;
  final String? body;

  bool get hasChanges => title != null || summary != null || body != null;
}

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

KnowledgePageCorrectionPatch buildPageBackedEvidenceCorrectionPatch({
  required String currentTitle,
  required String currentSummary,
  required String nextTitle,
  required String nextSummary,
}) {
  return KnowledgePageCorrectionPatch(
    title: nextTitle == currentTitle ? null : nextTitle,
    summary: nextSummary == currentSummary ? null : nextSummary,
  );
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
