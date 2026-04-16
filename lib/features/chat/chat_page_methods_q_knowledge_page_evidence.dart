part of 'chat_page.dart';

extension _ChatPageStateKnowledgePageEvidence on _ChatPageState {
  Future<void> _disableMemoryFromEvidence(String documentId) async {
    final pagesBackend =
        maybeKnowledgePagesBackendFor(AppBackendScope.of(context));
    final sessionKey = SessionScope.of(context).sessionKey;
    if (documentId.startsWith('page:') && pagesBackend != null) {
      await disablePageBackedEvidenceMemoryCard(
        pagesBackend,
        sessionKey,
        pageId: documentId,
      );
      return;
    }
    final backend = maybeKnowledgeBackendFor(AppBackendScope.of(context));
    final viewerBackend =
        maybeKnowledgeViewerBackendFor(AppBackendScope.of(context));
    if (backend == null || viewerBackend == null) return;
    final document = await viewerBackend.getKnowledgeViewerDocument(
      sessionKey,
      documentId: documentId,
    );
    final feedback = document.document.memoryFeedback;
    await backend.upsertKnowledgeMemoryFeedback(
      sessionKey,
      documentId: documentId,
      status: feedback.status,
      useForAskAi: false,
      isDeleted: feedback.isDeleted,
      markedInaccurate: feedback.markedInaccurate,
      correctedTitle: feedback.correctedTitle,
      correctedSummary: feedback.correctedSummary,
    );
  }

  Future<void> _deleteMemoryFromEvidence(String documentId) async {
    final pagesBackend =
        maybeKnowledgePagesBackendFor(AppBackendScope.of(context));
    final sessionKey = SessionScope.of(context).sessionKey;
    if (documentId.startsWith('page:') && pagesBackend != null) {
      await removePageBackedEvidenceMemoryCard(
        pagesBackend,
        sessionKey,
        pageId: documentId,
      );
      return;
    }
    final backend = maybeKnowledgeBackendFor(AppBackendScope.of(context));
    final viewerBackend =
        maybeKnowledgeViewerBackendFor(AppBackendScope.of(context));
    if (backend == null || viewerBackend == null) return;
    final document = await viewerBackend.getKnowledgeViewerDocument(
      sessionKey,
      documentId: documentId,
    );
    final feedback = document.document.memoryFeedback;
    await backend.upsertKnowledgeMemoryFeedback(
      sessionKey,
      documentId: documentId,
      status: feedback.status,
      useForAskAi: feedback.useForAskAi,
      isDeleted: true,
      markedInaccurate: feedback.markedInaccurate,
      correctedTitle: feedback.correctedTitle,
      correctedSummary: feedback.correctedSummary,
    );
  }

  Future<ChatAnswerEvidenceMemoryCard?> _correctMemoryFromEvidence(
    ChatAnswerEvidenceMemoryCard card, {
    required String title,
    required String summary,
  }) async {
    final pagesBackend =
        maybeKnowledgePagesBackendFor(AppBackendScope.of(context));
    final sessionKey = SessionScope.of(context).sessionKey;
    if (card.documentId.startsWith('page:') && pagesBackend != null) {
      return correctPageBackedEvidenceMemoryCard(
        pagesBackend,
        sessionKey,
        card,
        title: title,
        summary: summary,
      );
    }
    final backend = maybeKnowledgeBackendFor(AppBackendScope.of(context));
    final viewerBackend =
        maybeKnowledgeViewerBackendFor(AppBackendScope.of(context));
    if (backend == null || viewerBackend == null) return null;
    final document = await viewerBackend.getKnowledgeViewerDocument(
      sessionKey,
      documentId: card.documentId,
    );
    final feedback = document.document.memoryFeedback;
    await backend.upsertKnowledgeMemoryFeedback(
      sessionKey,
      documentId: card.documentId,
      status: KnowledgeMemoryStatus.confirmed,
      useForAskAi: feedback.useForAskAi,
      isDeleted: false,
      markedInaccurate: feedback.markedInaccurate,
      correctedTitle: title,
      correctedSummary: summary,
    );
    final refreshed = await viewerBackend.getKnowledgeViewerDocument(
      sessionKey,
      documentId: card.documentId,
    );
    return _memoryCardFromViewerDocument(card, refreshed.document);
  }

  Future<ChatAnswerEvidenceMemoryCard?> _refreshMemoryFromEvidence(
    ChatAnswerEvidenceMemoryCard card,
  ) async {
    final pagesBackend =
        maybeKnowledgePagesBackendFor(AppBackendScope.of(context));
    final sessionKey = SessionScope.of(context).sessionKey;
    if (card.documentId.startsWith('page:') && pagesBackend != null) {
      return refreshPageBackedEvidenceMemoryCard(
        pagesBackend,
        sessionKey,
        card,
      );
    }
    final viewerBackend =
        maybeKnowledgeViewerBackendFor(AppBackendScope.of(context));
    if (viewerBackend == null) return card;
    final refreshed = await viewerBackend.getKnowledgeViewerDocument(
      sessionKey,
      documentId: card.documentId,
    );
    return _memoryCardFromViewerDocument(card, refreshed.document);
  }

  ChatAnswerEvidenceMemoryCard _memoryCardFromViewerDocument(
    ChatAnswerEvidenceMemoryCard card,
    ContentKnowledgeDocument document,
  ) {
    final memoryDisplay = document.memoryDisplay;
    return card.copyWith(
      title: document.title,
      summary: document.summary,
      body: document.rawText,
      status: (memoryDisplay?.status ??
              document.memoryFeedback.status ??
              KnowledgeMemoryStatus.confirmed)
          .name,
      sourceCount: memoryDisplay?.sourceCount.toInt() ?? card.sourceCount,
      updatedAtMs: document.updatedAtMs.toInt(),
      useForAskAi: document.memoryFeedback.useForAskAi,
      isDeleted: document.memoryFeedback.isDeleted,
      markedInaccurate: document.memoryFeedback.markedInaccurate,
    );
  }
}
