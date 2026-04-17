import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/knowledge_index_gate.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/backend/knowledge_index_models.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

import 'test_backend.dart';

void main() {
  testWidgets('KnowledgeIndexGate requests rebuild for empty status only',
      (tester) async {
    final backend = _KnowledgeBackendStub(
      statusResponses: const [
        _emptyStatus,
        _requestedStatus,
      ],
      processResults: const <int>[],
    );

    await tester.pumpWidget(_wrapGate(backend));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(backend.requestCalls, 1);
    expect(backend.processCalls, 0);
  });

  testWidgets('KnowledgeIndexGate requests rebuild for stale status only',
      (tester) async {
    final backend = _KnowledgeBackendStub(
      statusResponses: const [
        _staleStatus,
        _requestedStatus,
      ],
      processResults: const <int>[],
    );

    await tester.pumpWidget(_wrapGate(backend));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(backend.requestCalls, 1);
    expect(backend.processCalls, 0);
  });

  testWidgets(
      'KnowledgeIndexGate retries failed backlog on failure interval when processing returns zero',
      (tester) async {
    final backend = _KnowledgeBackendStub(
      statusResponses: const [
        _failedStatus,
        _failedStatus,
        _failedStatus,
        _failedStatus,
      ],
      processResults: const [0, 0],
    );

    await tester.pumpWidget(_wrapGate(backend));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(backend.processCalls, 1);

    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(backend.processCalls, 2);
  });

  testWidgets(
      'KnowledgeIndexGate refreshes post-process status before choosing next backoff',
      (tester) async {
    final backend = _KnowledgeBackendStub(
      statusResponses: const [
        _failedStatus,
        _failedStatus,
        _completeStatus,
      ],
      processResults: const [0],
    );

    await tester.pumpWidget(_wrapGate(backend));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(backend.processCalls, 1);
    expect(backend.statusCalls, 3);

    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(
      backend.processCalls,
      1,
      reason:
          'complete post-process status should switch the gate to idle backoff',
    );
  });
}

Widget _wrapGate(AppBackend backend) {
  return MaterialApp(
    home: AppBackendScope(
      backend: backend,
      child: SessionScope(
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        lock: () {},
        child: const KnowledgeIndexGate(child: SizedBox.shrink()),
      ),
    ),
  );
}

const KnowledgeIndexStatus _emptyStatus = KnowledgeIndexStatus(
  status: 'empty',
  rebuildRequired: true,
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
  lastIndexedModelName: null,
  lastIndexedDim: null,
  versions: _versions,
);

const KnowledgeIndexStatus _staleStatus = KnowledgeIndexStatus(
  status: 'stale',
  rebuildRequired: true,
  staleReason: 'version_mismatch',
  lastError: null,
  lastRebuildStartedAtMs: 10,
  lastRebuildCompletedAtMs: 9,
  currentDocumentId: null,
  currentStage: null,
  documentsIndexed: 1,
  unitsIndexed: 2,
  embeddingsIndexed: 1,
  totalDocuments: 1,
  lastIndexedModelName: 'secondloop-default-embed-v0',
  lastIndexedDim: 384,
  versions: _versions,
);

const KnowledgeIndexStatus _requestedStatus = KnowledgeIndexStatus(
  status: 'requested',
  rebuildRequired: false,
  staleReason: null,
  lastError: null,
  lastRebuildStartedAtMs: 10,
  lastRebuildCompletedAtMs: null,
  currentDocumentId: null,
  currentStage: null,
  documentsIndexed: 0,
  unitsIndexed: 0,
  embeddingsIndexed: 0,
  totalDocuments: 1,
  lastIndexedModelName: 'secondloop-default-embed-v0',
  lastIndexedDim: 384,
  versions: _versions,
);

const KnowledgeIndexStatus _failedStatus = KnowledgeIndexStatus(
  status: 'failed',
  rebuildRequired: false,
  staleReason: null,
  lastError: 'temporary failure',
  lastRebuildStartedAtMs: 10,
  lastRebuildCompletedAtMs: null,
  currentDocumentId: 'message:m1',
  currentStage: 'embed',
  documentsIndexed: 1,
  unitsIndexed: 2,
  embeddingsIndexed: 1,
  totalDocuments: 1,
  lastIndexedModelName: 'secondloop-default-embed-v0',
  lastIndexedDim: 384,
  versions: _versions,
);

const KnowledgeIndexStatus _completeStatus = KnowledgeIndexStatus(
  status: 'complete',
  rebuildRequired: false,
  staleReason: null,
  lastError: null,
  lastRebuildStartedAtMs: 10,
  lastRebuildCompletedAtMs: 20,
  currentDocumentId: null,
  currentStage: null,
  documentsIndexed: 1,
  unitsIndexed: 2,
  embeddingsIndexed: 1,
  totalDocuments: 1,
  lastIndexedModelName: 'secondloop-default-embed-v0',
  lastIndexedDim: 384,
  versions: _versions,
);

const KnowledgeVersionSet _versions = KnowledgeVersionSet(
  schemaVersion: 1,
  normalizationVersion: 1,
  segmentationVersion: 1,
  embeddingPolicyVersion: 1,
  retrievalPolicyVersion: 1,
);

final class _KnowledgeBackendStub extends TestAppBackend
    implements KnowledgeBackend {
  _KnowledgeBackendStub({
    required List<KnowledgeIndexStatus> statusResponses,
    required List<int> processResults,
  })  : _statusResponses = List<KnowledgeIndexStatus>.from(statusResponses),
        _processResults = List<int>.from(processResults);

  final List<KnowledgeIndexStatus> _statusResponses;
  final List<int> _processResults;

  int statusCalls = 0;
  int requestCalls = 0;
  int processCalls = 0;

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
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key) async {
    statusCalls += 1;
    final index = (statusCalls - 1).clamp(0, _statusResponses.length - 1);
    return _statusResponses[index];
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
    processCalls += 1;
    final index = (processCalls - 1).clamp(0, _processResults.length - 1);
    if (_processResults.isEmpty) {
      throw StateError('processPendingKnowledgeIndexJobs should not be called');
    }
    return _processResults[index];
  }

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {
    requestCalls += 1;
  }

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
