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

    final listView = find.byType(ListView);
    final rebuildButton =
        find.byKey(const ValueKey('knowledge_index_rebuild_button'));
    await tester.dragUntilVisible(
      rebuildButton,
      listView,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    final rebuildWidget = tester.widget<ElevatedButton>(rebuildButton);
    expect(rebuildWidget.onPressed, isNull);
    expect(backend.rebuildRequests, 0);
    expect(
      find.byKey(
        const ValueKey('knowledge_index_cancel_button'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });
}

final class _KnowledgeBackend extends TestAppBackend
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
