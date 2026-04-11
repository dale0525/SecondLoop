import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/backend/knowledge_viewer_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/memory/memory_detail_page.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('MemoryDetailPage shows conclusion and evidence timeline',
      (tester) async {
    final backend = _MemoryDetailBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const MemoryDetailPage(
                documentId: 'generated:preference:response-language',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Current conclusion'), findsOneWidget);
    expect(find.text('Response language'), findsWidgets);
    expect(find.text('User prefers Chinese.'), findsWidgets);
    expect(find.text('Evidence timeline'), findsOneWidget);
    expect(find.text('Chat message'), findsOneWidget);
    expect(find.text('Message source'), findsOneWidget);
    expect(find.text('Updated today'), findsWidgets);
    expect(find.text('Kickoff note confirms the user prefers Chinese.'),
        findsOneWidget);
    expect(find.text('View original'), findsOneWidget);
  });

  testWidgets('MemoryDetailPage edits memory and toggles usage actions',
      (tester) async {
    final backend = _MemoryDetailBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const MemoryDetailPage(
                documentId: 'generated:preference:response-language',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit memory'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('memory_correction_title_field')),
      'Preferred reply language',
    );
    await tester.enterText(
      find.byKey(const ValueKey('memory_correction_summary_field')),
      'Always reply in Chinese unless I ask for another language.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Preferred reply language'), findsWidgets);
    expect(
      find.text('Always reply in Chinese unless I ask for another language.'),
      findsWidgets,
    );
    expect(find.text('Confirmed'), findsOneWidget);

    await tester.tap(find.text('Stop using for Ask AI'));
    await tester.pumpAndSettle();
    expect(find.text('Not used by Ask AI'), findsOneWidget);

    await tester.tap(find.text('Delete memory'));
    await tester.pumpAndSettle();
    expect(find.text('Memory deleted'), findsOneWidget);
    expect(find.text('Restore memory'), findsOneWidget);
  });
}

final class _MemoryDetailBackend extends TestAppBackend
    implements KnowledgeBackend, KnowledgeViewerBackend {
  KnowledgeViewerDocument _document(String documentId) =>
      KnowledgeViewerDocument(
        document: ContentKnowledgeDocument(
          documentId: documentId,
          originType: KnowledgeOriginType.generated,
          sourceKind: KnowledgeSourceKind.summary,
          role: KnowledgeRole.summary,
          language: 'en',
          qualityScore: 1,
          createdAtMs: 1,
          updatedAtMs: 2,
          versions: const KnowledgeVersionSet(
            schemaVersion: 1,
            normalizationVersion: 1,
            segmentationVersion: 1,
            embeddingPolicyVersion: 1,
            retrievalPolicyVersion: 1,
          ),
          anchors: const KnowledgeAnchorSet(),
          title: _title,
          summary: _summary,
          rawText: _summary ?? 'Prefer Chinese when replying.',
          normalizedText: _summary ?? 'Prefer Chinese when replying.',
          memoryFeedback: KnowledgeMemoryFeedback(
            status: _status,
            useForAskAi: _useForAskAi,
            isDeleted: _isDeleted,
            markedInaccurate: _markedInaccurate,
            correctedTitle: _title,
            correctedSummary: _summary,
            updatedAtMs: 3,
          ),
        ),
        totalUnits: 1,
        sectionCount: 1,
        chunkCount: 1,
      );

  String? _title = 'Response language';
  String? _summary = 'User prefers Chinese.';
  KnowledgeMemoryStatus? _status = KnowledgeMemoryStatus.inferred;
  bool _useForAskAi = true;
  bool _isDeleted = false;
  bool _markedInaccurate = false;

  @override
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) async =>
      _document(documentId);

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
  }) async {
    _status = status;
    _useForAskAi = useForAskAi;
    _isDeleted = isDeleted;
    _markedInaccurate = markedInaccurate;
    _title = correctedTitle;
    _summary = correctedSummary;
    return KnowledgeMemoryFeedback(
      status: _status,
      useForAskAi: _useForAskAi,
      isDeleted: _isDeleted,
      markedInaccurate: _markedInaccurate,
      correctedTitle: _title,
      correctedSummary: _summary,
      updatedAtMs: 3,
    );
  }

  @override
  Future<void> cancelKnowledgeRebuild(Uint8List key) async {}

  @override
  Future<KnowledgeDebugStats> getKnowledgeDebugStats(Uint8List key) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key) async =>
      throw UnimplementedError();

  @override
  Future<List<ContentKnowledgeDocument>> listKnowledgeDocuments(
    Uint8List key, {
    int limit = 100,
    int offset = 0,
  }) async =>
      <ContentKnowledgeDocument>[
        _document('generated:preference:response-language').document
      ];

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
  Future<int> processPendingKnowledgeIndexJobs(
    Uint8List key, {
    int limit = 8,
  }) async =>
      0;

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {}

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnitsAroundAnchor(
    Uint8List key, {
    required String documentId,
    required KnowledgeAnchorSet anchor,
    int before = 2,
    int after = 3,
  }) async =>
      const <KnowledgeUnit>[];

  @override
  Future<KnowledgeViewerPage> listKnowledgeViewerUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return KnowledgeViewerPage(
      documentId: documentId,
      unitKind: KnowledgeUnitKind.segment,
      offset: 0,
      limit: 20,
      total: 1,
      units: [
        KnowledgeUnit(
          unitId: 'u1',
          documentId: 'generated:preference:response-language',
          parentUnitId: null,
          unitKind: KnowledgeUnitKind.segment,
          sourceKind: KnowledgeSourceKind.summary,
          role: KnowledgeRole.evidence,
          ordinal: 0,
          tokenCount: 12,
          rawText: 'Kickoff note confirms the user prefers Chinese.',
          normalizedText: 'Kickoff note confirms the user prefers Chinese.',
          anchors: const KnowledgeAnchorSet(messageId: 'history-1'),
          prevUnitId: null,
          nextUnitId: null,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      ],
    );
  }

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledge(
    Uint8List key, {
    required String query,
    String? conversationId,
    String? documentId,
    int limit = 20,
  }) async =>
      const <KnowledgeSearchResult>[];

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledgeDocumentUnits(
    Uint8List key, {
    required String documentId,
    required String query,
    int limit = 20,
  }) async =>
      const <KnowledgeSearchResult>[];
}
