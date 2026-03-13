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
