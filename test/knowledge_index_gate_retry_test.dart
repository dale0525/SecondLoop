import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/knowledge_index_gate.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/backend/knowledge_index_models.dart';
import 'package:secondloop/core/session/session_scope.dart';

import 'test_backend.dart';

void main() {
  testWidgets('KnowledgeIndexGate retries failed jobs after failure status',
      (tester) async {
    final backend = _RetryingKnowledgeBackend();

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const KnowledgeIndexGate(child: SizedBox.shrink()),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(backend.processCalls, 0);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(backend.processCalls, 1);

    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    expect(backend.processCalls, 2);
  });

  testWidgets(
      'KnowledgeIndexGate does not request rebuild while active rebuild is already in progress',
      (tester) async {
    final backend = _ActiveRebuildKnowledgeBackend();

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const KnowledgeIndexGate(child: SizedBox.shrink()),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(backend.requestCalls, 0);
    expect(backend.processCalls, greaterThanOrEqualTo(1));
  });

  testWidgets(
      'KnowledgeIndexGate keeps failed backlog on failure interval when process returns zero',
      (tester) async {
    final backend = _FailedBackoffKnowledgeBackend();

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const KnowledgeIndexGate(child: SizedBox.shrink()),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(backend.processCalls, 1);

    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    expect(backend.processCalls, 2);
  });

  testWidgets(
      'KnowledgeIndexGate refreshes status after processing before choosing backoff',
      (tester) async {
    final backend = _PostProcessStatusKnowledgeBackend();

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const KnowledgeIndexGate(child: SizedBox.shrink()),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(backend.processCalls, 1);
    expect(backend.statusCalls, 3);

    await tester.pump(const Duration(seconds: 9));
    await tester.pump();

    expect(backend.processCalls, 1);
    expect(backend.statusCalls, 3);
  });

  testWidgets('KnowledgeIndexGate does not process empty status directly',
      (tester) async {
    final backend = _AlwaysEmptyKnowledgeBackend();

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const KnowledgeIndexGate(child: SizedBox.shrink()),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(backend.requestCalls, 1);
    expect(backend.processCalls, 0);
  });

  testWidgets('KnowledgeIndexGate does not process stale status directly',
      (tester) async {
    final backend = _AlwaysStaleKnowledgeBackend();

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const KnowledgeIndexGate(child: SizedBox.shrink()),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(backend.requestCalls, 1);
    expect(backend.processCalls, 0);
  });

  testWidgets('KnowledgeIndexGate logs backend failures in debug mode',
      (tester) async {
    final backend = _AlwaysFailingKnowledgeBackend();
    final captured = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        captured.add(message);
      }
    };

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgeIndexGate(child: SizedBox.shrink()),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(
        captured.any(
          (message) =>
              message.contains('KnowledgeIndexGate: background tick failed'),
        ),
        isTrue,
      );
    } finally {
      debugPrint = previousDebugPrint;
    }
  });
}

final class _RetryingKnowledgeBackend extends TestAppBackend
    implements KnowledgeBackend {
  int processCalls = 0;
  String status = 'running';

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
    return KnowledgeIndexStatus(
      status: status,
      rebuildRequired: false,
      staleReason: null,
      lastError: status == 'failed' ? 'temporary failure' : null,
      lastRebuildStartedAtMs: 10,
      lastRebuildCompletedAtMs: status == 'complete' ? 20 : null,
      currentDocumentId: status == 'running' ? 'message:m1' : null,
      currentStage: status == 'running' ? 'embed' : null,
      documentsIndexed: 1,
      unitsIndexed: 2,
      embeddingsIndexed: 1,
      totalDocuments: 1,
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
  }) async {
    processCalls += 1;
    if (processCalls == 1) {
      status = 'failed';
      throw StateError('temporary failure');
    }
    status = 'complete';
    return 1;
  }

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {
    status = 'requested';
  }
}

final class _ActiveRebuildKnowledgeBackend extends TestAppBackend
    implements KnowledgeBackend {
  int requestCalls = 0;
  int processCalls = 0;

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
      status: 'running',
      rebuildRequired: true,
      staleReason: null,
      lastError: null,
      lastRebuildStartedAtMs: 10,
      lastRebuildCompletedAtMs: null,
      currentDocumentId: 'message:m1',
      currentStage: 'embed',
      documentsIndexed: 1,
      unitsIndexed: 2,
      embeddingsIndexed: 1,
      totalDocuments: 3,
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
  }) async {
    processCalls += 1;
    return 1;
  }

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {
    requestCalls += 1;
  }
}

final class _AlwaysFailingKnowledgeBackend extends TestAppBackend
    implements KnowledgeBackend {
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
      status: 'running',
      rebuildRequired: false,
      staleReason: null,
      lastError: null,
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
      throw StateError('boom');

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {}
}

final class _FailedBackoffKnowledgeBackend extends TestAppBackend
    implements KnowledgeBackend {
  int processCalls = 0;

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
      status: 'failed',
      rebuildRequired: false,
      staleReason: null,
      lastError: 'temporary failure',
      lastRebuildStartedAtMs: 10,
      lastRebuildCompletedAtMs: null,
      currentDocumentId: 'message:m1',
      currentStage: 'normalize',
      documentsIndexed: 0,
      unitsIndexed: 0,
      embeddingsIndexed: 0,
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
  }) async {
    processCalls += 1;
    return 0;
  }

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {}
}

final class _PostProcessStatusKnowledgeBackend extends TestAppBackend
    implements KnowledgeBackend {
  int processCalls = 0;
  int statusCalls = 0;
  String status = 'failed';

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
    statusCalls += 1;
    return KnowledgeIndexStatus(
      status: status,
      rebuildRequired: false,
      staleReason: null,
      lastError: status == 'failed' ? 'temporary failure' : null,
      lastRebuildStartedAtMs: 10,
      lastRebuildCompletedAtMs: status == 'complete' ? 20 : null,
      currentDocumentId: status == 'failed' ? 'message:m1' : null,
      currentStage: status == 'failed' ? 'embed' : null,
      documentsIndexed: 1,
      unitsIndexed: 2,
      embeddingsIndexed: 1,
      totalDocuments: 1,
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
  }) async {
    processCalls += 1;
    status = 'complete';
    return 0;
  }

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {}
}

final class _AlwaysEmptyKnowledgeBackend extends TestAppBackend
    implements KnowledgeBackend {
  int requestCalls = 0;
  int processCalls = 0;

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
  }) async {
    processCalls += 1;
    return 0;
  }

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {
    requestCalls += 1;
  }
}

final class _AlwaysStaleKnowledgeBackend extends TestAppBackend
    implements KnowledgeBackend {
  int requestCalls = 0;
  int processCalls = 0;

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
  }) async {
    processCalls += 1;
    return 0;
  }

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {
    requestCalls += 1;
  }
}
