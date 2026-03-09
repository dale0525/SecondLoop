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
  testWidgets(
      'Knowledge Index card shows reload errors instead of staying blank',
      (tester) async {
    final backend = _ErrorKnowledgeBackend(failLoad: true);

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

    expect(find.textContaining('status backend unavailable'), findsOneWidget);
  });

  testWidgets('Knowledge Index card surfaces rebuild action errors',
      (tester) async {
    final backend = _ErrorKnowledgeBackend(failRebuild: true);

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

    await tester.tap(rebuildButton);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('rebuild backend unavailable'), findsOneWidget);
  });

  testWidgets('Knowledge Index card surfaces cancel action errors',
      (tester) async {
    final backend = _ErrorKnowledgeBackend(
      running: true,
      failCancel: true,
    );

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
    final cancelButton = find.byKey(
      const ValueKey('knowledge_index_cancel_button'),
      skipOffstage: false,
    );
    await tester.dragUntilVisible(
      cancelButton,
      listView,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('cancel backend unavailable'), findsOneWidget);
  });
}

final class _ErrorKnowledgeBackend extends TestAppBackend
    implements KnowledgeBackend {
  _ErrorKnowledgeBackend({
    this.running = false,
    this.failLoad = false,
    this.failRebuild = false,
    this.failCancel = false,
  });

  bool running;
  final bool failLoad;
  final bool failRebuild;
  final bool failCancel;

  @override
  Future<void> cancelKnowledgeRebuild(Uint8List key) async {
    if (failCancel) {
      throw StateError('cancel backend unavailable');
    }
    running = false;
  }

  @override
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key) async {
    if (failLoad) {
      throw StateError('status backend unavailable');
    }
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
  }) async {
    if (failRebuild) {
      throw StateError('rebuild backend unavailable');
    }
    running = true;
    return 1;
  }

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {
    if (failRebuild) {
      throw StateError('rebuild backend unavailable');
    }
    running = true;
  }
}
