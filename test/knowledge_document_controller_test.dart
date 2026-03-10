import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/knowledge_viewer_backend.dart';
import 'package:secondloop/features/knowledge_viewer/knowledge_document_controller.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

final class _FakeKnowledgeViewerBackend implements KnowledgeViewerBackend {
  Completer<KnowledgeViewerPage>? listPageCompleter;
  Completer<List<KnowledgeUnit>>? aroundCompleter;

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledge(
    Uint8List key, {
    required String query,
    String? conversationId,
    String? documentId,
    int limit = 20,
  }) =>
      throw UnimplementedError();

  @override
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) =>
      throw UnimplementedError();

  @override
  Future<KnowledgeViewerPage> listKnowledgeViewerUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) {
    listPageCompleter ??= Completer<KnowledgeViewerPage>();
    return listPageCompleter!.future;
  }

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledgeDocumentUnits(
    Uint8List key, {
    required String documentId,
    required String query,
    int limit = 20,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnitsAroundAnchor(
    Uint8List key, {
    required String documentId,
    required KnowledgeAnchorSet anchor,
    int before = 2,
    int after = 3,
  }) {
    aroundCompleter ??= Completer<List<KnowledgeUnit>>();
    return aroundCompleter!.future;
  }
}

ContentKnowledgeDocument _doc(String id) => ContentKnowledgeDocument(
      documentId: id,
      originType: KnowledgeOriginType.generated,
      sourceKind: KnowledgeSourceKind.rawText,
      role: KnowledgeRole.body,
      language: null,
      qualityScore: 1.0,
      createdAtMs: 0,
      updatedAtMs: 0,
      versions: const KnowledgeVersionSet(
        schemaVersion: 1,
        normalizationVersion: 1,
        segmentationVersion: 1,
        embeddingPolicyVersion: 1,
        retrievalPolicyVersion: 1,
      ),
      anchors: const KnowledgeAnchorSet(),
      title: null,
      summary: null,
      rawText: '',
      normalizedText: '',
    );

KnowledgeUnit _unit(String documentId, String unitId) => KnowledgeUnit(
      unitId: unitId,
      documentId: documentId,
      parentUnitId: null,
      unitKind: KnowledgeUnitKind.chunk,
      sourceKind: KnowledgeSourceKind.rawText,
      role: KnowledgeRole.body,
      ordinal: 0,
      tokenCount: 1,
      rawText: 'unit $unitId',
      normalizedText: 'unit $unitId',
      anchors: const KnowledgeAnchorSet(messageId: 'm1'),
      prevUnitId: null,
      nextUnitId: null,
      createdAtMs: 0,
      updatedAtMs: 0,
    );

void main() {
  test('jumpToResult wins over in-flight reset loadPage', () async {
    const documentId = 'doc1';
    final backend = _FakeKnowledgeViewerBackend();
    final initial = KnowledgeViewerDocument(
      document: _doc(documentId),
      totalUnits: 0,
      sectionCount: 0,
      chunkCount: 0,
    );
    final controller = KnowledgeDocumentController(
      backend: backend,
      sessionKey: Uint8List(32),
      documentId: documentId,
      initialDocument: initial,
      pageSize: 2,
    );

    final pageUnits = <KnowledgeUnit>[_unit(documentId, 'page-unit')];
    final anchorUnits = <KnowledgeUnit>[
      _unit(documentId, 'anchor-unit'),
      _unit(documentId, 'anchor-unit-2'),
    ];

    const result = KnowledgeSearchResult(
      documentId: documentId,
      unitId: 'anchor-unit',
      unitKind: KnowledgeUnitKind.chunk,
      layer: KnowledgeRetrievalLayer.chunk,
      sourceKind: KnowledgeSourceKind.rawText,
      role: KnowledgeRole.body,
      title: null,
      summary: null,
      snippet: 'snippet',
      score: 1.0,
      semanticScore: 0.0,
      lexicalScore: 0.0,
      anchors: KnowledgeAnchorSet(messageId: 'm1'),
      createdAtMs: 0,
      updatedAtMs: 0,
    );

    final loadFuture = controller.loadPage(reset: true);
    expect(controller.loadingPage, isTrue);

    final jumpFuture = controller.jumpToResult(result);
    backend.aroundCompleter!.complete(anchorUnits);
    await jumpFuture;

    expect(controller.anchorMode, isTrue);
    expect(controller.units, anchorUnits);

    backend.listPageCompleter!.complete(
      KnowledgeViewerPage(
        documentId: documentId,
        unitKind: null,
        offset: 0,
        limit: 2,
        total: 10,
        units: pageUnits,
      ),
    );
    await loadFuture;

    expect(controller.anchorMode, isTrue);
    expect(controller.units, anchorUnits);
  });
}
