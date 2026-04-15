part of 'native_backend.dart';

extension NativeAppBackendKnowledgeExtension on NativeAppBackend {
  Future<rust_knowledge_models.KnowledgeIndexStatus> getKnowledgeIndexStatus(
    Uint8List key,
  ) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbGetKnowledgeIndexStatus(appDir: appDir, key: key);
  }

  Future<rust_knowledge_models.KnowledgeDebugStats> getKnowledgeDebugStats(
    Uint8List key,
  ) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbGetKnowledgeDebugStats(appDir: appDir, key: key);
  }

  Future<void> requestKnowledgeRebuild(Uint8List key) async {
    final appDir = await _getAppDir();
    await rust_knowledge.dbRequestKnowledgeRebuild(appDir: appDir, key: key);
  }

  Future<int> processPendingKnowledgeIndexJobs(
    Uint8List key, {
    int limit = 8,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbProcessPendingKnowledgeIndexJobs(
      appDir: appDir,
      key: key,
      limit: limit,
    );
  }

  Future<void> cancelKnowledgeRebuild(Uint8List key) async {
    final appDir = await _getAppDir();
    await rust_knowledge.dbCancelKnowledgeRebuild(appDir: appDir, key: key);
  }

  Future<List<rust_knowledge_models.ContentKnowledgeDocument>>
      listKnowledgeDocuments(
    Uint8List key, {
    int limit = 100,
    int offset = 0,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbListKnowledgeDocuments(
      appDir: appDir,
      key: key,
      limit: limit,
      offset: offset,
    );
  }

  Future<List<rust_knowledge_pages.KnowledgePageSummary>>
      listKnowledgePageSummaries(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbListKnowledgePageSummaries(
        appDir: appDir, key: key);
  }

  Future<List<rust_knowledge_pages.KnowledgePageSummary>>
      listMergeableKnowledgePageSummaries(
    Uint8List key, {
    required String pageId,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbListMergeableKnowledgePageSummaries(
      appDir: appDir,
      key: key,
      pageId: pageId,
    );
  }

  Future<List<rust_knowledge_history.KnowledgePageChangeRecord>>
      listRecentKnowledgePageChanges(
    Uint8List key, {
    int limit = 8,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbListRecentKnowledgePageChanges(
      appDir: appDir,
      key: key,
      limit: limit,
    );
  }

  Future<rust_knowledge_pages.KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbGetKnowledgePageDetail(
      appDir: appDir,
      key: key,
      pageId: pageId,
    );
  }

  Future<rust_knowledge_pages.KnowledgePageDetail> correctKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? title,
    String? summary,
    String? body,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbCorrectKnowledgePage(
      appDir: appDir,
      key: key,
      pageId: pageId,
      title: title,
      summary: summary,
      body: body,
    );
  }

  Future<rust_knowledge_pages.KnowledgePageDetail> markKnowledgePageWrong(
    Uint8List key, {
    required String pageId,
    required rust_knowledge_pages.KnowledgeWrongReason reason,
    String? note,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbMarkKnowledgePageWrong(
      appDir: appDir,
      key: key,
      pageId: pageId,
      reason: reason,
      note: note,
    );
  }

  Future<rust_knowledge_pages.KnowledgePageDetail>
      setKnowledgePageAnswerAllowed(
    Uint8List key, {
    required String pageId,
    required bool allowed,
    String? note,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbSetKnowledgePageAnswerAllowed(
      appDir: appDir,
      key: key,
      pageId: pageId,
      allowed: allowed,
      note: note,
    );
  }

  Future<rust_knowledge_pages.KnowledgePageDetail> archiveKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbArchiveKnowledgePage(
      appDir: appDir,
      key: key,
      pageId: pageId,
      note: note,
    );
  }

  Future<rust_knowledge_pages.KnowledgePageDetail> removeKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbRemoveKnowledgePage(
      appDir: appDir,
      key: key,
      pageId: pageId,
      note: note,
    );
  }

  Future<rust_knowledge_pages.KnowledgePageDetail> mergeKnowledgePageInto(
    Uint8List key, {
    required String pageId,
    required String targetPageId,
    String? note,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbMergeKnowledgePageInto(
      appDir: appDir,
      key: key,
      pageId: pageId,
      targetPageId: targetPageId,
      note: note,
    );
  }

  Future<List<rust_knowledge_models.ContentKnowledgeDocument>>
      listGeneratedMemoryDocuments(
    Uint8List key, {
    int limit = 100,
    int offset = 0,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbListGeneratedMemoryDocuments(
      appDir: appDir,
      key: key,
      limit: limit,
      offset: offset,
    );
  }

  Future<rust_knowledge_models.KnowledgeMemoryFeedback>
      upsertKnowledgeMemoryFeedback(
    Uint8List key, {
    required String documentId,
    rust_knowledge_models.KnowledgeMemoryStatus? status,
    required bool useForAskAi,
    required bool isDeleted,
    required bool markedInaccurate,
    String? correctedTitle,
    String? correctedSummary,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbUpsertKnowledgeMemoryFeedback(
      appDir: appDir,
      key: key,
      documentId: documentId,
      status: status,
      useForAskAi: useForAskAi,
      isDeleted: isDeleted,
      markedInaccurate: markedInaccurate,
      correctedTitle: correctedTitle,
      correctedSummary: correctedSummary,
    );
  }

  Future<List<rust_knowledge_models.KnowledgeUnit>> listKnowledgeUnits(
    Uint8List key, {
    required String documentId,
    rust_knowledge_models.KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbListKnowledgeUnits(
      appDir: appDir,
      key: key,
      documentId: documentId,
      unitKind: unitKind,
      limit: limit,
      offset: offset,
    );
  }

  Future<List<rust_knowledge_models.KnowledgeSearchResult>> searchKnowledge(
    Uint8List key, {
    required String query,
    String? conversationId,
    String? documentId,
    int limit = 20,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbSearchKnowledge(
      appDir: appDir,
      key: key,
      query: query,
      conversationId: conversationId,
      documentId: documentId,
      limit: limit,
    );
  }

  Future<rust_knowledge_models.KnowledgeViewerDocument>
      getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbGetKnowledgeDocument(
      appDir: appDir,
      key: key,
      documentId: documentId,
    );
  }

  Future<rust_knowledge_models.KnowledgeViewerPage> listKnowledgeViewerUnits(
    Uint8List key, {
    required String documentId,
    rust_knowledge_models.KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbListKnowledgeViewerUnits(
      appDir: appDir,
      key: key,
      documentId: documentId,
      unitKind: unitKind,
      limit: limit,
      offset: offset,
    );
  }

  Future<List<rust_knowledge_models.KnowledgeUnit>>
      listRecentKnowledgeViewerUnits(
    Uint8List key, {
    required String documentId,
    rust_knowledge_models.KnowledgeUnitKind? unitKind,
    int limit = 16,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbListRecentKnowledgeViewerUnits(
      appDir: appDir,
      key: key,
      documentId: documentId,
      unitKind: unitKind,
      limit: limit,
    );
  }

  Future<List<rust_knowledge_models.KnowledgeSearchResult>>
      searchKnowledgeDocumentUnits(
    Uint8List key, {
    required String documentId,
    required String query,
    int limit = 20,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbSearchKnowledgeDocumentUnits(
      appDir: appDir,
      key: key,
      documentId: documentId,
      query: query,
      limit: limit,
    );
  }

  Future<List<rust_knowledge_models.KnowledgeUnit>>
      listKnowledgeUnitsAroundAnchor(
    Uint8List key, {
    required String documentId,
    required rust_knowledge_models.KnowledgeAnchorSet anchor,
    int before = 2,
    int after = 3,
  }) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbListKnowledgeUnitsAroundAnchor(
      appDir: appDir,
      key: key,
      documentId: documentId,
      anchor: anchor,
      before: before,
      after: after,
    );
  }
}
