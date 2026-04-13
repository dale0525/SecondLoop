import '../../src/rust/knowledge/models.dart';
import '../../src/rust/knowledge/pages.dart';
import 'chat_answer_evidence_models.dart';

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

ChatAnswerEvidenceMemoryCard knowledgePageMemoryCardFromDetail(
  ChatAnswerEvidenceMemoryCard card,
  KnowledgePageDetail detail,
) {
  final page = detail.page;
  final status = page.humanCorrected
      ? KnowledgeMemoryStatus.confirmed.name
      : (page.state == KnowledgePageState.outdated
          ? KnowledgeMemoryStatus.maybeOutdated.name
          : KnowledgeMemoryStatus.inferred.name);
  return card.copyWith(
    title: page.title,
    summary: page.currentSummary,
    body: page.currentBody,
    status: status,
    sourceCount: page.sourceCount.toInt(),
    updatedAtMs: page.updatedAtMs.toInt(),
    useForAskAi: page.answerPolicy.defaultAllowed,
    isDeleted: page.state == KnowledgePageState.removed,
    markedInaccurate: page.state == KnowledgePageState.needsReview,
  );
}
