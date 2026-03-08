import 'dart:typed_data';

import 'app_backend.dart';
import 'knowledge_index_models.dart';
import 'native_backend.dart';

abstract interface class KnowledgeBackend {
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key);

  Future<void> requestKnowledgeRebuild(Uint8List key);

  Future<int> processPendingKnowledgeIndexJobs(
    Uint8List key, {
    int limit = 8,
  });

  Future<void> cancelKnowledgeRebuild(Uint8List key);

  Future<List<ContentKnowledgeDocument>> listKnowledgeDocuments(
    Uint8List key, {
    int limit = 100,
    int offset = 0,
  });

  Future<List<KnowledgeUnit>> listKnowledgeUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  });
}

KnowledgeBackend? maybeKnowledgeBackendFor(AppBackend backend) {
  if (backend is KnowledgeBackend) return backend as KnowledgeBackend;
  if (backend is NativeAppBackend) return NativeKnowledgeBackend(backend);
  return null;
}

final class NativeKnowledgeBackend implements KnowledgeBackend {
  NativeKnowledgeBackend(this._backend);

  final NativeAppBackend _backend;

  @override
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key) =>
      _backend.getKnowledgeIndexStatus(key);

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) =>
      _backend.requestKnowledgeRebuild(key);

  @override
  Future<int> processPendingKnowledgeIndexJobs(
    Uint8List key, {
    int limit = 8,
  }) =>
      _backend.processPendingKnowledgeIndexJobs(key, limit: limit);

  @override
  Future<void> cancelKnowledgeRebuild(Uint8List key) =>
      _backend.cancelKnowledgeRebuild(key);

  @override
  Future<List<ContentKnowledgeDocument>> listKnowledgeDocuments(
    Uint8List key, {
    int limit = 100,
    int offset = 0,
  }) =>
      _backend.listKnowledgeDocuments(key, limit: limit, offset: offset);

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) =>
      _backend.listKnowledgeUnits(
        key,
        documentId: documentId,
        unitKind: unitKind,
        limit: limit,
        offset: offset,
      );
}
