import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/backend/knowledge_viewer_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/memory/memory_center_page.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('MemoryCenterPage groups generated memory cards', (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _MemoryBackend(
      documents: [
        _document(
          documentId: 'generated:preference:response-language',
          title: 'Response language',
          summary: 'User prefers Chinese.\nUse concise bullets.',
          updatedAtMs: nowMs,
          memoryDisplay: const KnowledgeMemoryDisplay(
            section: KnowledgeMemorySection.preference,
            sourceCount: 2,
            status: KnowledgeMemoryStatus.inferred,
          ),
        ),
        _document(
          documentId: 'generated:event:trip-plan',
          title: 'Trip plan',
          summary: 'Upcoming trip to Shanghai.',
          updatedAtMs: nowMs - const Duration(days: 2).inMilliseconds,
          memoryDisplay: const KnowledgeMemoryDisplay(
            section: KnowledgeMemorySection.recentEvent,
            sourceCount: 1,
            status: KnowledgeMemoryStatus.inferred,
          ),
        ),
        _document(
          documentId: 'generated:profile:launch-work',
          title: 'Launch work',
          summary:
              'Working on project launch checklist.\nPreparing rollout notes.',
          updatedAtMs: nowMs,
          memoryDisplay: const KnowledgeMemoryDisplay(
            section: KnowledgeMemorySection.project,
            sourceCount: 2,
            status: KnowledgeMemoryStatus.inferred,
          ),
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
              child: const MemoryCenterPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Recent events'), findsOneWidget);
    expect(find.text('Response language'), findsOneWidget);
    expect(find.text('Trip plan'), findsOneWidget);
    expect(find.text('Launch work'), findsOneWidget);
    expect(find.textContaining('2 sources'), findsWidgets);
    expect(find.textContaining('Updated today'), findsWidgets);
  });

  testWidgets('MemoryCenterPage uses backend-native section metadata', (
    tester,
  ) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _MemoryBackend(
      documents: [
        _document(
          documentId: 'generated:profile:release-companion',
          title: 'Release companion',
          summary: 'Shared launch coordination memory.',
          updatedAtMs: nowMs,
          memoryDisplay: const KnowledgeMemoryDisplay(
            section: KnowledgeMemorySection.project,
            sourceCount: 4,
            status: KnowledgeMemoryStatus.confirmed,
          ),
        ),
        _document(
          documentId: 'generated:pattern:weekly-focus',
          title: 'Weekly focus',
          summary: 'Recurring planning topic.',
          updatedAtMs: nowMs - const Duration(days: 3).inMilliseconds,
          memoryDisplay: const KnowledgeMemoryDisplay(
            section: KnowledgeMemorySection.topic,
            sourceCount: 3,
            status: KnowledgeMemoryStatus.maybeOutdated,
          ),
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
              child: const MemoryCenterPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Topics'), findsOneWidget);
    expect(find.text('Release companion'), findsOneWidget);
    expect(find.text('Weekly focus'), findsOneWidget);
    expect(find.textContaining('4 sources'), findsOneWidget);
    expect(find.textContaining('Confirmed'), findsOneWidget);
    expect(find.textContaining('Maybe outdated'), findsOneWidget);
  });
}

final class _MemoryBackend extends TestAppBackend
    implements KnowledgeBackend, KnowledgeViewerBackend {
  _MemoryBackend({required this.documents});

  final List<ContentKnowledgeDocument> documents;

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
  Future<void> cancelKnowledgeRebuild(Uint8List key) async {}

  @override
  Future<KnowledgeDebugStats> getKnowledgeDebugStats(Uint8List key) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<ContentKnowledgeDocument>> listKnowledgeDocuments(
    Uint8List key, {
    int limit = 100,
    int offset = 0,
  }) async =>
      documents;

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
  }) async =>
      throw UnimplementedError();

  @override
  Future<int> processPendingKnowledgeIndexJobs(
    Uint8List key, {
    int limit = 8,
  }) async =>
      0;

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {}

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

ContentKnowledgeDocument _document({
  required String documentId,
  required String title,
  required String summary,
  required int updatedAtMs,
  KnowledgeMemoryDisplay? memoryDisplay,
}) {
  return ContentKnowledgeDocument(
    documentId: documentId,
    originType: KnowledgeOriginType.generated,
    sourceKind: KnowledgeSourceKind.summary,
    role: KnowledgeRole.summary,
    language: 'en',
    qualityScore: 1,
    createdAtMs: 1,
    updatedAtMs: updatedAtMs,
    versions: const KnowledgeVersionSet(
      schemaVersion: 1,
      normalizationVersion: 1,
      segmentationVersion: 1,
      embeddingPolicyVersion: 1,
      retrievalPolicyVersion: 1,
    ),
    anchors: const KnowledgeAnchorSet(),
    title: title,
    summary: summary,
    rawText: summary,
    normalizedText: summary,
    memoryDisplay: memoryDisplay,
    memoryFeedback: const KnowledgeMemoryFeedback(
      useForAskAi: true,
      isDeleted: false,
      markedInaccurate: false,
    ),
  );
}
