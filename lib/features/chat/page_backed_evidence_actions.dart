import 'dart:typed_data';

import '../../core/backend/knowledge_backend.dart';
import 'chat_answer_evidence_models.dart';
import 'knowledge_page_memory_card_helpers.dart';

Future<void> disablePageBackedEvidenceMemoryCard(
  KnowledgePagesBackend pagesBackend,
  Uint8List sessionKey, {
  required String pageId,
}) {
  return pagesBackend.setKnowledgePageAnswerAllowed(
    sessionKey,
    pageId: pageId,
    allowed: false,
  );
}

Future<void> removePageBackedEvidenceMemoryCard(
  KnowledgePagesBackend pagesBackend,
  Uint8List sessionKey, {
  required String pageId,
}) {
  return pagesBackend.removeKnowledgePage(
    sessionKey,
    pageId: pageId,
  );
}

Future<ChatAnswerEvidenceMemoryCard> correctPageBackedEvidenceMemoryCard(
  KnowledgePagesBackend pagesBackend,
  Uint8List sessionKey,
  ChatAnswerEvidenceMemoryCard card, {
  required String title,
  required String summary,
}) async {
  final currentDetail = await pagesBackend.getKnowledgePageDetail(
    sessionKey,
    pageId: card.documentId,
  );
  final patch = buildPageBackedEvidenceCorrectionPatch(
    currentTitle: currentDetail.page.title,
    currentSummary: currentDetail.page.currentSummary,
    nextTitle: title,
    nextSummary: summary,
  );
  if (!patch.hasChanges) {
    return knowledgePageMemoryCardFromDetail(card, currentDetail);
  }
  final detail = await pagesBackend.correctKnowledgePage(
    sessionKey,
    pageId: card.documentId,
    title: patch.title,
    summary: patch.summary,
    body: patch.body,
  );
  return knowledgePageMemoryCardFromDetail(card, detail);
}

Future<ChatAnswerEvidenceMemoryCard> refreshPageBackedEvidenceMemoryCard(
  KnowledgePagesBackend pagesBackend,
  Uint8List sessionKey,
  ChatAnswerEvidenceMemoryCard card,
) async {
  final detail = await pagesBackend.getKnowledgePageDetail(
    sessionKey,
    pageId: card.documentId,
  );
  return knowledgePageMemoryCardFromDetail(card, detail);
}
