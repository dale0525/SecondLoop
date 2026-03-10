import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/knowledge_viewer_backend.dart';
import 'package:secondloop/features/knowledge_viewer/knowledge_document_viewer.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Knowledge Viewer paginates, searches and jumps to anchor',
      (tester) async {
    final backend = _FakeKnowledgeViewerBackend();
    final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: KnowledgeDocumentViewer(
              backend: backend,
              sessionKey: sessionKey,
              documentId: backend.documentId,
              initialDocument: backend.viewerDocument,
              fallbackText: backend.viewerDocument.document.rawText,
              pageSize: 2,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('attachment_knowledge_viewer')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('knowledge_viewer_unit_chunk-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('knowledge_viewer_unit_chunk-2')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('knowledge_viewer_unit_chunk-3')),
        findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey('knowledge_viewer_load_more')),
    );
    await tester.tap(find.byKey(const ValueKey('knowledge_viewer_load_more')));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('knowledge_viewer_list')),
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('knowledge_viewer_unit_chunk-4')),
        findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('knowledge_viewer_search_field')),
      'deadline',
    );
    await tester.tap(
      find.byKey(const ValueKey('knowledge_viewer_search_submit')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('knowledge_viewer_search_hit_chunk-5')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('knowledge_viewer_search_hit_chunk-5')),
    );
    await tester.pumpAndSettle();

    expect(backend.anchorReads, 1);
    expect(
      find.byKey(const ValueKey('knowledge_viewer_unit_highlight_chunk-5')),
      findsOneWidget,
    );
    expect(find.textContaining('00:44'), findsWidgets);
  });
}

final class _FakeKnowledgeViewerBackend implements KnowledgeViewerBackend {
  final String documentId = 'attachment:sha-doc:transcript';
  int anchorReads = 0;

  late final ContentKnowledgeDocument document = ContentKnowledgeDocument(
    documentId: documentId,
    originType: KnowledgeOriginType.attachment,
    sourceKind: KnowledgeSourceKind.transcript,
    role: KnowledgeRole.evidence,
    language: 'en',
    qualityScore: 0.92,
    createdAtMs: 100,
    updatedAtMs: 200,
    versions: const KnowledgeVersionSet(
      schemaVersion: 1,
      normalizationVersion: 1,
      segmentationVersion: 1,
      embeddingPolicyVersion: 1,
      retrievalPolicyVersion: 1,
    ),
    anchors: const KnowledgeAnchorSet(
      attachmentSha256: 'sha-doc',
      sourceFilename: 'meeting.m4a',
    ),
    title: 'Team meeting',
    summary: 'Quarterly planning discussion.',
    rawText: 'Chunk one\nChunk two\nChunk three\nChunk four',
    normalizedText: 'chunk one chunk two chunk three chunk four',
  );

  late final KnowledgeViewerDocument viewerDocument = KnowledgeViewerDocument(
    document: document,
    totalUnits: 5,
    sectionCount: 1,
    chunkCount: 5,
  );

  late final List<KnowledgeUnit> units = <KnowledgeUnit>[
    _unit(
      id: 'chunk-1',
      ordinal: 0,
      text: 'Intro and opening notes.',
      startMs: 0,
      endMs: 8000,
      nextId: 'chunk-2',
    ),
    _unit(
      id: 'chunk-2',
      ordinal: 1,
      text: 'Budget review and status.',
      startMs: 8000,
      endMs: 16000,
      prevId: 'chunk-1',
      nextId: 'chunk-3',
    ),
    _unit(
      id: 'chunk-3',
      ordinal: 2,
      text: 'Hiring discussion continues.',
      startMs: 16000,
      endMs: 24000,
      prevId: 'chunk-2',
      nextId: 'chunk-4',
    ),
    _unit(
      id: 'chunk-4',
      ordinal: 3,
      text: 'Decision log and recap.',
      startMs: 30000,
      endMs: 38000,
      prevId: 'chunk-3',
      nextId: 'chunk-5',
    ),
    _unit(
      id: 'chunk-5',
      ordinal: 4,
      text: 'Deadline moves to next Friday.',
      startMs: 44000,
      endMs: 52000,
      prevId: 'chunk-4',
    ),
  ];

  @override
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) async {
    if (documentId != this.documentId) {
      throw StateError('unknown document');
    }
    return viewerDocument;
  }

  @override
  Future<KnowledgeViewerPage> listKnowledgeViewerUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) async {
    final slice = units.skip(offset).take(limit).toList(growable: false);
    return KnowledgeViewerPage(
      documentId: documentId,
      unitKind: unitKind,
      offset: offset,
      limit: limit,
      total: units.length,
      units: slice,
    );
  }

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledge(
    Uint8List key, {
    required String query,
    String? conversationId,
    String? documentId,
    int limit = 20,
  }) async {
    return const <KnowledgeSearchResult>[];
  }

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledgeDocumentUnits(
    Uint8List key, {
    required String documentId,
    required String query,
    int limit = 20,
  }) async {
    if (query.trim().toLowerCase() != 'deadline') {
      return const <KnowledgeSearchResult>[];
    }
    return <KnowledgeSearchResult>[
      KnowledgeSearchResult(
        documentId: documentId,
        unitId: 'chunk-5',
        unitKind: KnowledgeUnitKind.chunk,
        layer: KnowledgeRetrievalLayer.chunk,
        sourceKind: KnowledgeSourceKind.transcript,
        role: KnowledgeRole.evidence,
        title: 'Team meeting',
        summary: 'Quarterly planning discussion.',
        snippet: 'Deadline moves to next Friday.',
        score: 0.97,
        semanticScore: 0.91,
        lexicalScore: 1.0,
        anchors: const KnowledgeAnchorSet(
          attachmentSha256: 'sha-doc',
          startMs: 44000,
          endMs: 52000,
          speaker: 'Dana',
          sectionLabel: 'Timeline',
        ),
        createdAtMs: 100,
        updatedAtMs: 200,
      ),
    ];
  }

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnitsAroundAnchor(
    Uint8List key, {
    required String documentId,
    required KnowledgeAnchorSet anchor,
    int before = 2,
    int after = 3,
  }) async {
    anchorReads += 1;
    return units.sublist(2, 5);
  }

  KnowledgeUnit _unit({
    required String id,
    required int ordinal,
    required String text,
    required int startMs,
    required int endMs,
    String? prevId,
    String? nextId,
  }) {
    return KnowledgeUnit(
      unitId: id,
      documentId: documentId,
      parentUnitId: 'section-1',
      unitKind: KnowledgeUnitKind.chunk,
      sourceKind: KnowledgeSourceKind.transcript,
      role: KnowledgeRole.evidence,
      ordinal: ordinal,
      tokenCount: 12,
      rawText: text,
      normalizedText: text.toLowerCase(),
      anchors: KnowledgeAnchorSet(
        attachmentSha256: 'sha-doc',
        startMs: startMs,
        endMs: endMs,
        speaker: ordinal >= 2 ? 'Dana' : 'Alice',
        sectionLabel: ordinal >= 2 ? 'Timeline' : 'Agenda',
      ),
      prevUnitId: prevId,
      nextUnitId: nextId,
      createdAtMs: 100,
      updatedAtMs: 200,
    );
  }
}
