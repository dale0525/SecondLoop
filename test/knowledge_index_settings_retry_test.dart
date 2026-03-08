import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/backend/knowledge_index_models.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Knowledge Index card shows failed state and retry rebuild',
      (tester) async {
    final backend = _RetryKnowledgeBackend();

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

    final listView = find.byType(ListView);
    final rebuildButton =
        find.byKey(const ValueKey('knowledge_index_rebuild_button'));
    await tester.dragUntilVisible(
        rebuildButton, listView, const Offset(0, -220));
    await tester.pumpAndSettle();

    expect(find.textContaining('rebuild failed'), findsOneWidget);
    expect(find.textContaining('vector provider timeout'), findsOneWidget);
    expect(find.textContaining('documents: 2/5'), findsOneWidget);

    await tester.tap(rebuildButton);
    await tester.pumpAndSettle();

    expect(backend.rebuildRequests, 1);
    final cancelButton = find.byKey(
      const ValueKey('knowledge_index_cancel_button'),
      skipOffstage: false,
    );
    await tester.dragUntilVisible(
        cancelButton, listView, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('knowledge_index_cancel_button')),
        findsOneWidget);
  });
}

final class _RetryKnowledgeBackend extends TestAppBackend
    implements KnowledgeBackend {
  int rebuildRequests = 0;
  bool running = false;

  @override
  Future<void> cancelKnowledgeRebuild(Uint8List key) async {
    running = false;
  }

  @override
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key) async {
    return KnowledgeIndexStatus(
      status: running ? 'running' : 'failed',
      rebuildRequired: !running,
      staleReason: running ? null : 'embedding_model_changed',
      lastError: running ? null : 'vector provider timeout',
      lastRebuildStartedAtMs: 10,
      lastRebuildCompletedAtMs: running ? null : 11,
      currentDocumentId: running ? 'message:m1' : null,
      currentStage: running ? 'embed' : null,
      documentsIndexed: 2,
      unitsIndexed: 6,
      embeddingsIndexed: 4,
      totalDocuments: 5,
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
