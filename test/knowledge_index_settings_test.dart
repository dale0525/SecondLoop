import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/backend/knowledge_index_models.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';
import 'package:secondloop/features/settings/knowledge_index_debug_page.dart';
import 'package:secondloop/features/settings/knowledge_index_settings_card.dart';

import 'test_backend.dart';
import 'test_i18n.dart';
import 'ai_settings_test_helpers.dart';

void main() {
  testWidgets('Knowledge Index settings card shows status and rebuild action',
      (tester) async {
    final backend = _KnowledgeBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const AiSettingsPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openAiAdvancedSettings(tester);

    final listView = find.byType(ListView);
    final rebuildButton =
        find.byKey(const ValueKey('knowledge_index_rebuild_button'));
    await tester.dragUntilVisible(
        rebuildButton, listView, const Offset(0, -220));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('knowledge_index_status_label')),
        findsOneWidget);
    expect(find.textContaining('Knowledge Index'), findsOneWidget);

    await tester.tap(rebuildButton);
    await tester.pumpAndSettle();

    expect(backend.rebuildRequests, 1);
  });

  testWidgets('Knowledge Index rebuild button is disabled while running',
      (tester) async {
    final backend = _KnowledgeBackend()..running = true;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const AiSettingsPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openAiAdvancedSettings(tester);

    final listView = find.byType(ListView);
    final rebuildButton =
        find.byKey(const ValueKey('knowledge_index_rebuild_button'));
    await tester.dragUntilVisible(
        rebuildButton, listView, const Offset(0, -220));
    await tester.pumpAndSettle();

    final elevated = tester.widget<ElevatedButton>(rebuildButton);
    expect(elevated.onPressed, isNull);
  });

  testWidgets('Knowledge Index card polls rebuild progress while running',
      (tester) async {
    final backend = _PollingKnowledgeBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const Scaffold(body: KnowledgeIndexSettingsCard()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('documents: 1/4'), findsOneWidget);
    expect(backend.statusRequests, 1);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.textContaining('documents: 2/4'), findsOneWidget);
    expect(backend.statusRequests, 2);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.textContaining('documents: 4/4'), findsOneWidget);
    expect(backend.statusRequests, 3);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(backend.statusRequests, 3);
  });

  testWidgets('Knowledge Index debug page caps document pagination',
      (tester) async {
    final backend = _CappedDebugKnowledgeBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgeIndexDebugPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(backend.listRequests, 10);
  });
}

final class _KnowledgeBackend extends TestAppBackend
    implements KnowledgeBackend {
  int rebuildRequests = 0;
  bool running = false;

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
  Future<void> cancelKnowledgeRebuild(Uint8List key) async {
    running = false;
  }

  @override
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key) async {
    return KnowledgeIndexStatus(
      status: running ? 'running' : 'stale',
      rebuildRequired: !running,
      staleReason: running ? null : 'embedding_model_changed',
      lastError: null,
      lastRebuildStartedAtMs: running ? 10 : null,
      lastRebuildCompletedAtMs: running ? null : 5,
      currentDocumentId: running ? 'message:m1' : null,
      currentStage: running ? 'embed' : null,
      documentsIndexed: 1,
      unitsIndexed: 3,
      embeddingsIndexed: 2,
      totalDocuments: 4,
      lastIndexedModelName: 'secondloop-default-embed-v0',
      lastIndexedDim: 384,
      versions: const KnowledgeVersionSet(
        schemaVersion: 1,
        normalizationVersion: 1,
        segmentationVersion: 1,
        embeddingPolicyVersion: 1,
        retrievalPolicyVersion: 1,
      ),
    );
  }

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
  Future<int> processPendingKnowledgeIndexJobs(
    Uint8List key, {
    int limit = 8,
  }) async =>
      1;

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {
    rebuildRequests += 1;
    running = true;
  }
}

final class _PollingKnowledgeBackend extends TestAppBackend
    implements KnowledgeBackend {
  int statusRequests = 0;

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
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key) async {
    statusRequests += 1;
    return switch (statusRequests) {
      1 => _status('running', 1, 3, 2, currentStage: 'normalize'),
      2 => _status('running', 2, 6, 5, currentStage: 'embed'),
      _ => _status('complete', 4, 10, 9),
    };
  }

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
  Future<int> processPendingKnowledgeIndexJobs(
    Uint8List key, {
    int limit = 8,
  }) async =>
      0;

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {}

  KnowledgeIndexStatus _status(
    String status,
    int documentsIndexed,
    int unitsIndexed,
    int embeddingsIndexed, {
    String? currentStage,
  }) {
    return KnowledgeIndexStatus(
      status: status,
      rebuildRequired: false,
      staleReason: null,
      lastError: null,
      lastRebuildStartedAtMs: 10,
      lastRebuildCompletedAtMs: status == 'complete' ? 20 : null,
      currentDocumentId: status == 'complete' ? null : 'message:m1',
      currentStage: currentStage,
      documentsIndexed: documentsIndexed,
      unitsIndexed: unitsIndexed,
      embeddingsIndexed: embeddingsIndexed,
      totalDocuments: 4,
      lastIndexedModelName: 'secondloop-default-embed-v0',
      lastIndexedDim: 384,
      versions: const KnowledgeVersionSet(
        schemaVersion: 1,
        normalizationVersion: 1,
        segmentationVersion: 1,
        embeddingPolicyVersion: 1,
        retrievalPolicyVersion: 1,
      ),
    );
  }
}

final class _CappedDebugKnowledgeBackend extends TestAppBackend
    implements KnowledgeBackend {
  int listRequests = 0;

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
      documentsIndexed: 5000,
      unitsIndexed: 5000,
      embeddingsIndexed: 5000,
      totalDocuments: 5000,
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
  Future<KnowledgeDebugStats> getKnowledgeDebugStats(Uint8List key) async {
    return const KnowledgeDebugStats(
      totalDocuments: 5000,
      generatedDocuments: 0,
      sourceDocuments: 5000,
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
  }) async {
    listRequests += 1;
    return List<ContentKnowledgeDocument>.generate(
      limit,
      (index) => ContentKnowledgeDocument(
        documentId: 'doc-${offset + index}',
        originType: KnowledgeOriginType.message,
        sourceKind: KnowledgeSourceKind.rawText,
        role: KnowledgeRole.body,
        title: 'Doc ${offset + index}',
        summary: 'Summary ${offset + index}',
        language: null,
        qualityScore: 1,
        createdAtMs: 1,
        updatedAtMs: 1,
        versions: const KnowledgeVersionSet(
          schemaVersion: 1,
          normalizationVersion: 1,
          segmentationVersion: 1,
          embeddingPolicyVersion: 1,
          retrievalPolicyVersion: 1,
        ),
        anchors: const KnowledgeAnchorSet(),
        rawText: 'Raw ${offset + index}',
        normalizedText: 'Raw ${offset + index}',
        memoryFeedback: const KnowledgeMemoryFeedback(
          useForAskAi: true,
          isDeleted: false,
          markedInaccurate: false,
        ),
      ),
      growable: false,
    );
  }

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
}
