import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/backend/knowledge_viewer_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/semantic_search_debug_page.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'Semantic search debug page prepares knowledge index before searching',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final backend = _SemanticSearchPrepBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const SemanticSearchDebugPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'budget freeze');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(backend.calls, contains('processPendingKnowledgeIndexJobs'));
    expect(backend.calls, contains('searchKnowledge'));
    expect(
      backend.calls.indexOf('processPendingKnowledgeIndexJobs'),
      lessThan(backend.calls.indexOf('searchKnowledge')),
    );
    expect(find.text('Speaker Charlie: freeze-signal budget decision'),
        findsOneWidget);
    expect(find.textContaining('attachment_sha256=sha-search'), findsOneWidget);
  });

  testWidgets('Semantic search debug page opens message hits in message viewer',
      (tester) async {
    final backend = _SemanticSearchPrepBackend(
      initialMessages: const <Message>[
        Message(
          id: 'msg-1',
          conversationId: 'loop_home',
          role: 'user',
          content: '## Budget freeze note\n\nFollow up next week.',
          createdAtMs: 1,
          isMemory: true,
        ),
      ],
      results: <KnowledgeSearchResult>[
        const KnowledgeSearchResult(
          documentId: 'message:msg-1',
          unitId: 'message:msg-1:chunk:0',
          unitKind: KnowledgeUnitKind.chunk,
          layer: KnowledgeRetrievalLayer.chunk,
          sourceKind: KnowledgeSourceKind.rawText,
          role: KnowledgeRole.body,
          title: 'Budget freeze note',
          summary: 'Follow up next week.',
          snippet: 'Follow up next week.',
          score: 0.93,
          semanticScore: 0.9,
          lexicalScore: 0.95,
          anchors: KnowledgeAnchorSet(
            messageId: 'msg-1',
            conversationId: 'loop_home',
          ),
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const SemanticSearchDebugPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'budget freeze');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
        const ValueKey('knowledge_search_result_message:msg-1:chunk:0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_viewer_page')), findsOneWidget);
  });
}

final class _SemanticSearchPrepBackend extends TestAppBackend
    implements KnowledgeBackend, KnowledgeViewerBackend {
  _SemanticSearchPrepBackend({
    super.initialMessages,
    List<KnowledgeSearchResult>? results,
  }) : _results = results ??
            <KnowledgeSearchResult>[
              const KnowledgeSearchResult(
                documentId: 'attachment:sha-search:transcript',
                unitId: 'attachment:sha-search:transcript:chunk:0',
                unitKind: KnowledgeUnitKind.chunk,
                layer: KnowledgeRetrievalLayer.chunk,
                sourceKind: KnowledgeSourceKind.transcript,
                role: KnowledgeRole.evidence,
                title: 'Budget meeting transcript',
                summary: 'Speaker Charlie covers the decision.',
                snippet: 'Speaker Charlie: freeze-signal budget decision',
                score: 0.97,
                semanticScore: 0.95,
                lexicalScore: 1.0,
                anchors: KnowledgeAnchorSet(
                  attachmentSha256: 'sha-search',
                  startMs: 44000,
                  endMs: 52000,
                  sectionLabel: 'Speaker Charlie',
                ),
                createdAtMs: 1,
                updatedAtMs: 1,
              ),
            ];

  final List<String> calls = <String>[];
  final List<KnowledgeSearchResult> _results;

  @override
  Future<KnowledgeMemoryFeedback> upsertKnowledgeMemoryFeedback(
    Uint8List key, {
    required String documentId,
    KnowledgeMemoryStatus? status,
    required bool useForAskAi,
    required bool isDeleted,
    required bool markedInaccurate,
    String? correctedTitle,
    String? correctedSummary,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key) async {
    return const KnowledgeIndexStatus(
      status: 'complete',
      rebuildRequired: false,
      staleReason: null,
      lastError: null,
      lastRebuildStartedAtMs: 1,
      lastRebuildCompletedAtMs: 1,
      currentDocumentId: null,
      currentStage: null,
      documentsIndexed: 1,
      unitsIndexed: 3,
      embeddingsIndexed: 3,
      totalDocuments: 1,
      lastIndexedModelName: 'secondloop-default-embed-v0',
      lastIndexedDim: 384,
      versions: KnowledgeVersionSet(
        schemaVersion: 1,
        normalizationVersion: 1,
        segmentationVersion: 1,
        embeddingPolicyVersion: 1,
        retrievalPolicyVersion: 1,
      ),
    );
  }

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {
    calls.add('requestKnowledgeRebuild');
  }

  @override
  Future<int> processPendingKnowledgeIndexJobs(
    Uint8List key, {
    int limit = 8,
  }) async {
    calls.add('processPendingKnowledgeIndexJobs');
    return 0;
  }

  @override
  Future<void> cancelKnowledgeRebuild(Uint8List key) async {}
  @override
  Future<KnowledgeDebugStats> getKnowledgeDebugStats(Uint8List key) async {
    return const KnowledgeDebugStats(
      totalDocuments: 0,
      generatedDocuments: 0,
      sourceDocuments: 0,
      summaryDocuments: 0,
      preferenceDocuments: 0,
      profileDocuments: 0,
      eventDocuments: 0,
      patternDocuments: 0,
      usageStatDocuments: 0,
      lastSynthesisAtMs: null,
      lastRetrievedAtMs: null,
      generatedMemoryRetrievalEnabled: true,
      hotnessRerankEnabled: true,
      sessionDigestEnabled: true,
    );
  }

  @override
  Future<List<ContentKnowledgeDocument>> listKnowledgeDocuments(
    Uint8List key, {
    int limit = 100,
    int offset = 0,
  }) async =>
      const <ContentKnowledgeDocument>[];

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) async =>
      const <KnowledgeUnit>[];

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledge(
    Uint8List key, {
    required String query,
    String? conversationId,
    String? documentId,
    int limit = 20,
  }) async {
    calls.add('searchKnowledge');
    return _results.take(limit).toList(growable: false);
  }

  @override
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) async {
    return KnowledgeViewerDocument(
      document: ContentKnowledgeDocument(
        documentId: documentId,
        originType: documentId.startsWith('message:')
            ? KnowledgeOriginType.message
            : KnowledgeOriginType.attachment,
        sourceKind: documentId.startsWith('message:')
            ? KnowledgeSourceKind.rawText
            : KnowledgeSourceKind.transcript,
        role: documentId.startsWith('message:')
            ? KnowledgeRole.body
            : KnowledgeRole.evidence,
        language: 'en',
        qualityScore: 0.9,
        createdAtMs: 1,
        updatedAtMs: 1,
        versions: const KnowledgeVersionSet(
          schemaVersion: 1,
          normalizationVersion: 1,
          segmentationVersion: 1,
          embeddingPolicyVersion: 1,
          retrievalPolicyVersion: 1,
        ),
        anchors: documentId.startsWith('message:')
            ? const KnowledgeAnchorSet(
                messageId: 'msg-1',
                conversationId: 'loop_home',
              )
            : const KnowledgeAnchorSet(
                attachmentSha256: 'sha-search',
                startMs: 44000,
                endMs: 52000,
                sectionLabel: 'Speaker Charlie',
              ),
        title: 'Viewer document',
        summary: 'Viewer summary',
        rawText: 'Viewer raw text',
        normalizedText: 'viewer raw text',
        memoryFeedback: const KnowledgeMemoryFeedback(
          useForAskAi: true,
          isDeleted: false,
          markedInaccurate: false,
        ),
      ),
      totalUnits: 1,
      sectionCount: 1,
      chunkCount: 1,
    );
  }

  @override
  Future<KnowledgeViewerPage> listKnowledgeViewerUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) async {
    return KnowledgeViewerPage(
      documentId: documentId,
      unitKind: unitKind,
      offset: offset,
      limit: limit,
      total: 1,
      units: <KnowledgeUnit>[
        KnowledgeUnit(
          unitId: '$documentId:chunk:0',
          documentId: documentId,
          parentUnitId: null,
          unitKind: KnowledgeUnitKind.chunk,
          sourceKind: documentId.startsWith('message:')
              ? KnowledgeSourceKind.rawText
              : KnowledgeSourceKind.transcript,
          role: documentId.startsWith('message:')
              ? KnowledgeRole.body
              : KnowledgeRole.evidence,
          ordinal: 0,
          tokenCount: 24,
          rawText: documentId.startsWith('message:')
              ? 'Budget freeze note body'
              : 'Speaker Charlie: freeze-signal budget decision',
          normalizedText: documentId.startsWith('message:')
              ? 'budget freeze note body'
              : 'speaker charlie: freeze-signal budget decision',
          anchors: documentId.startsWith('message:')
              ? const KnowledgeAnchorSet(
                  messageId: 'msg-1',
                  conversationId: 'loop_home',
                )
              : const KnowledgeAnchorSet(
                  attachmentSha256: 'sha-search',
                  startMs: 44000,
                  endMs: 52000,
                  sectionLabel: 'Speaker Charlie',
                ),
          prevUnitId: null,
          nextUnitId: null,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ],
    );
  }

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledgeDocumentUnits(
    Uint8List key, {
    required String documentId,
    required String query,
    int limit = 20,
  }) async =>
      const <KnowledgeSearchResult>[];

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnitsAroundAnchor(
    Uint8List key, {
    required String documentId,
    required KnowledgeAnchorSet anchor,
    int before = 2,
    int after = 3,
  }) async =>
      const <KnowledgeUnit>[];
}
