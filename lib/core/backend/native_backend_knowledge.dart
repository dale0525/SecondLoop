part of 'native_backend.dart';

extension NativeAppBackendKnowledgeExtension on NativeAppBackend {
  Future<rust_knowledge_models.KnowledgeIndexStatus> getKnowledgeIndexStatus(
    Uint8List key,
  ) async {
    final appDir = await _getAppDir();
    return rust_knowledge.dbGetKnowledgeIndexStatus(appDir: appDir, key: key);
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
}
