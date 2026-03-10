import 'dart:typed_data';

import 'app_backend.dart';
import 'knowledge_index_models.dart';
import 'native_backend.dart';

abstract interface class KnowledgeViewerBackend {
  Future<List<KnowledgeSearchResult>> searchKnowledge(
    Uint8List key, {
    required String query,
    String? conversationId,
    String? documentId,
    int limit = 20,
  });

  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  });

  Future<KnowledgeViewerPage> listKnowledgeViewerUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  });

  Future<List<KnowledgeSearchResult>> searchKnowledgeDocumentUnits(
    Uint8List key, {
    required String documentId,
    required String query,
    int limit = 20,
  });

  Future<List<KnowledgeUnit>> listKnowledgeUnitsAroundAnchor(
    Uint8List key, {
    required String documentId,
    required KnowledgeAnchorSet anchor,
    int before = 2,
    int after = 3,
  });
}

KnowledgeViewerBackend? maybeKnowledgeViewerBackendFor(AppBackend backend) {
  if (backend is KnowledgeViewerBackend) {
    return backend as KnowledgeViewerBackend;
  }
  if (backend is NativeAppBackend) {
    return NativeKnowledgeViewerBackend(backend);
  }
  return null;
}

final class NativeKnowledgeViewerBackend implements KnowledgeViewerBackend {
  NativeKnowledgeViewerBackend(this._backend);

  final NativeAppBackend _backend;

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledge(
    Uint8List key, {
    required String query,
    String? conversationId,
    String? documentId,
    int limit = 20,
  }) =>
      _backend.searchKnowledge(
        key,
        query: query,
        conversationId: conversationId,
        documentId: documentId,
        limit: limit,
      );

  @override
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) =>
      _backend.getKnowledgeViewerDocument(key, documentId: documentId);

  @override
  Future<KnowledgeViewerPage> listKnowledgeViewerUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) =>
      _backend.listKnowledgeViewerUnits(
        key,
        documentId: documentId,
        unitKind: unitKind,
        limit: limit,
        offset: offset,
      );

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledgeDocumentUnits(
    Uint8List key, {
    required String documentId,
    required String query,
    int limit = 20,
  }) =>
      _backend.searchKnowledgeDocumentUnits(
        key,
        documentId: documentId,
        query: query,
        limit: limit,
      );

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnitsAroundAnchor(
    Uint8List key, {
    required String documentId,
    required KnowledgeAnchorSet anchor,
    int before = 2,
    int after = 3,
  }) =>
      _backend.listKnowledgeUnitsAroundAnchor(
        key,
        documentId: documentId,
        anchor: anchor,
        before: before,
        after: after,
      );
}
