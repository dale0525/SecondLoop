import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/backend/knowledge_index_models.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

import 'ai_settings_test_helpers.dart';
import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'AI settings home shows task-first entries and hides advanced controls by default',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: AiSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('ai_settings_home_ask_ai')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai_settings_home_smart_organization')),
      findsOneWidget,
    );
    final advancedSettings =
        find.byKey(const ValueKey('ai_settings_home_advanced_settings'));
    await tester.dragUntilVisible(
      advancedSettings,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    expect(advancedSettings, findsOneWidget);

    expect(
        find.byKey(const ValueKey('ai_settings_section_ask_ai')), findsNothing);
    expect(
      find.byKey(const ValueKey('ai_settings_section_media_understanding')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai_settings_cloud_embeddings_switch')),
      findsNothing,
    );
  });

  testWidgets(
      'AI settings advanced section reveals existing low-level controls',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: AiSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openAiAdvancedSettings(tester);

    expect(find.byKey(const ValueKey('ai_settings_section_ask_ai')),
        findsOneWidget);

    final mediaSection =
        find.byKey(const ValueKey('ai_settings_section_media_understanding'));
    await tester.dragUntilVisible(
      mediaSection,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(mediaSection, findsOneWidget);

    final cloudEmbeddingsSwitch =
        find.byKey(const ValueKey('ai_settings_cloud_embeddings_switch'));
    await tester.dragUntilVisible(
      cloudEmbeddingsSwitch,
      find.byType(ListView).first,
      const Offset(0, 220),
    );
    await tester.pumpAndSettle();
    expect(cloudEmbeddingsSwitch, findsOneWidget);
  });

  testWidgets(
      'AI settings advanced section hides knowledge index controls even when backend supports them',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: _KnowledgeBackendStub(),
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

    expect(find.byKey(const ValueKey('knowledge_index_status_label')),
        findsNothing);
    expect(find.textContaining('Knowledge Index'), findsNothing);
  });
}

final class _KnowledgeBackendStub extends TestAppBackend
    implements KnowledgeBackend {
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
      generatedMemoryRetrievalEnabled: false,
      hotnessRerankEnabled: false,
      sessionDigestEnabled: false,
    );
  }

  @override
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key) async {
    return const KnowledgeIndexStatus(
      status: 'complete',
      rebuildRequired: false,
      staleReason: null,
      lastError: null,
      lastRebuildStartedAtMs: null,
      lastRebuildCompletedAtMs: null,
      currentDocumentId: null,
      currentStage: null,
      documentsIndexed: 0,
      unitsIndexed: 0,
      embeddingsIndexed: 0,
      totalDocuments: 0,
      lastIndexedModelName: 'stub',
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
}
