part of 'knowledge_center_page_test.dart';

final class _KnowledgeCenterBackendStub extends TestAppBackend
    implements KnowledgePagesBackend {
  _KnowledgeCenterBackendStub({
    required this.summaries,
    required this.details,
    required this.recentChanges,
  });

  final List<KnowledgePageSummary> summaries;
  final Map<String, KnowledgePageDetail> details;
  final List<KnowledgePageChangeRecord> recentChanges;

  @override
  Future<List<KnowledgePageSummary>> listKnowledgePageSummaries(
    Uint8List key,
  ) async =>
      summaries;

  @override
  Future<List<KnowledgePageSummary>> listMergeableKnowledgePageSummaries(
    Uint8List key, {
    required String pageId,
  }) async =>
      const <KnowledgePageSummary>[];

  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async =>
      details[pageId] ?? (throw StateError('missing detail for $pageId'));

  @override
  Future<List<KnowledgePageChangeRecord>> listRecentKnowledgePageChanges(
    Uint8List key, {
    int limit = 8,
  }) async =>
      recentChanges.take(limit).toList(growable: false);

  @override
  Future<KnowledgePageDetail> archiveKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> removeKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> mergeKnowledgePageInto(
    Uint8List key, {
    required String pageId,
    required String targetPageId,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> correctKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? title,
    String? summary,
    String? body,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> markKnowledgePageWrong(
    Uint8List key, {
    required String pageId,
    required KnowledgeWrongReason reason,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> setKnowledgePageAnswerAllowed(
    Uint8List key, {
    required String pageId,
    required bool allowed,
    String? note,
  }) async =>
      throw UnimplementedError();
}

final class _ConcurrentKnowledgeCenterBackendStub extends TestAppBackend
    implements KnowledgePagesBackend {
  _ConcurrentKnowledgeCenterBackendStub({
    required this.details,
    required this.recentChanges,
  });

  final Map<String, KnowledgePageDetail> details;
  final List<KnowledgePageChangeRecord> recentChanges;
  final List<String> requestedPageIds = <String>[];
  final Map<String, Completer<KnowledgePageDetail>> _completers =
      <String, Completer<KnowledgePageDetail>>{};

  @override
  Future<List<KnowledgePageSummary>> listKnowledgePageSummaries(
    Uint8List key,
  ) async =>
      const <KnowledgePageSummary>[];

  @override
  Future<List<KnowledgePageSummary>> listMergeableKnowledgePageSummaries(
    Uint8List key, {
    required String pageId,
  }) async =>
      const <KnowledgePageSummary>[];

  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) {
    requestedPageIds.add(pageId);
    return _completers
        .putIfAbsent(pageId, Completer<KnowledgePageDetail>.new)
        .future;
  }

  void completeAll() {
    for (final entry in details.entries) {
      final completer = _completers.putIfAbsent(
        entry.key,
        Completer<KnowledgePageDetail>.new,
      );
      if (!completer.isCompleted) {
        completer.complete(entry.value);
      }
    }
  }

  @override
  Future<List<KnowledgePageChangeRecord>> listRecentKnowledgePageChanges(
    Uint8List key, {
    int limit = 8,
  }) async =>
      recentChanges.take(limit).toList(growable: false);

  @override
  Future<KnowledgePageDetail> archiveKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> removeKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> mergeKnowledgePageInto(
    Uint8List key, {
    required String pageId,
    required String targetPageId,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> correctKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? title,
    String? summary,
    String? body,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> markKnowledgePageWrong(
    Uint8List key, {
    required String pageId,
    required KnowledgeWrongReason reason,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> setKnowledgePageAnswerAllowed(
    Uint8List key, {
    required String pageId,
    required bool allowed,
    String? note,
  }) async =>
      throw UnimplementedError();
}

final class _MutableKnowledgeCenterBackendStub extends TestAppBackend
    implements KnowledgePagesBackend {
  _MutableKnowledgeCenterBackendStub({
    required List<KnowledgePageSummary> summaries,
    required Map<String, KnowledgePageDetail> details,
    required this.recentChanges,
  })  : _summaries = List<KnowledgePageSummary>.from(summaries),
        _details = Map<String, KnowledgePageDetail>.from(details);

  final List<KnowledgePageSummary> _summaries;
  final Map<String, KnowledgePageDetail> _details;
  final List<KnowledgePageChangeRecord> recentChanges;

  @override
  Future<List<KnowledgePageSummary>> listKnowledgePageSummaries(
    Uint8List key,
  ) async =>
      List<KnowledgePageSummary>.from(_summaries);

  @override
  Future<List<KnowledgePageSummary>> listMergeableKnowledgePageSummaries(
    Uint8List key, {
    required String pageId,
  }) async =>
      const <KnowledgePageSummary>[];

  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async =>
      _details[pageId] ?? (throw StateError('missing detail for $pageId'));

  @override
  Future<List<KnowledgePageChangeRecord>> listRecentKnowledgePageChanges(
    Uint8List key, {
    int limit = 8,
  }) async =>
      recentChanges.take(limit).toList(growable: false);

  @override
  Future<KnowledgePageDetail> archiveKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async {
    _summaries.removeWhere((page) => page.pageId == pageId);
    final detail = _details[pageId];
    if (detail == null) {
      throw StateError('missing detail for $pageId');
    }
    final archived = KnowledgePageDetail(
      page: KnowledgePage(
        pageId: detail.page.pageId,
        pageType: detail.page.pageType,
        title: detail.page.title,
        currentSummary: detail.page.currentSummary,
        currentBody: detail.page.currentBody,
        state: KnowledgePageState.archived,
        answerPolicy: const KnowledgeAnswerPolicy(
          defaultAllowed: false,
          requiresTemporalFraming: false,
        ),
        confidenceLevel: detail.page.confidenceLevel,
        createdAtMs: detail.page.createdAtMs,
        updatedAtMs: detail.page.updatedAtMs + 1,
        lastUsedAtMs: detail.page.lastUsedAtMs,
        sourceCount: detail.page.sourceCount,
        conflictCount: detail.page.conflictCount,
        humanCorrected: detail.page.humanCorrected,
        tags: detail.page.tags,
        primaryEvidenceIds: detail.page.primaryEvidenceIds,
        relatedPageIds: detail.page.relatedPageIds,
      ),
      sourceDocumentIds: detail.sourceDocumentIds,
      claimIds: detail.claimIds,
      history: detail.history,
      versionSnapshots: detail.versionSnapshots,
      evidenceEntries: detail.evidenceEntries,
      lintRecords: detail.lintRecords,
    );
    _details[pageId] = archived;
    return archived;
  }

  @override
  Future<KnowledgePageDetail> removeKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> mergeKnowledgePageInto(
    Uint8List key, {
    required String pageId,
    required String targetPageId,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> correctKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? title,
    String? summary,
    String? body,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> markKnowledgePageWrong(
    Uint8List key, {
    required String pageId,
    required KnowledgeWrongReason reason,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> setKnowledgePageAnswerAllowed(
    Uint8List key, {
    required String pageId,
    required bool allowed,
    String? note,
  }) async =>
      throw UnimplementedError();
}

KnowledgePageSummary _summary({
  required String pageId,
  required String title,
  required KnowledgePageType pageType,
  required KnowledgePageState state,
  required int updatedAtMs,
  int? lastUsedAtMs,
}) {
  return KnowledgePageSummary(
    pageId: pageId,
    pageType: pageType,
    title: title,
    currentSummary: '$title summary',
    state: state,
    answerPolicy: const KnowledgeAnswerPolicy(
      defaultAllowed: true,
      requiresTemporalFraming: false,
    ),
    updatedAtMs: updatedAtMs,
    lastUsedAtMs: lastUsedAtMs,
    sourceCount: 1,
    conflictCount: 0,
    humanCorrected: false,
    tags: const [],
    primaryEvidenceIds: const [],
  );
}

KnowledgePageDetail _detail({
  required String pageId,
  required String title,
  required KnowledgePageType pageType,
  required KnowledgePageState state,
  required String summary,
  required int updatedAtMs,
  List<KnowledgePageChangeRecord> history = const [],
  List<KnowledgeLintRecord> lintRecords = const [],
}) {
  return KnowledgePageDetail(
    page: KnowledgePage(
      pageId: pageId,
      pageType: pageType,
      title: title,
      currentSummary: summary,
      currentBody: '$summary\nExpanded body.',
      state: state,
      answerPolicy: const KnowledgeAnswerPolicy(
        defaultAllowed: true,
        requiresTemporalFraming: false,
      ),
      confidenceLevel: 0.9,
      createdAtMs: updatedAtMs - 1000,
      updatedAtMs: updatedAtMs,
      lastUsedAtMs: updatedAtMs,
      sourceCount: 1,
      conflictCount: 0,
      humanCorrected: false,
      tags: const [],
      primaryEvidenceIds: const ['doc:1'],
      relatedPageIds: const [],
    ),
    sourceDocumentIds: const ['doc:1'],
    claimIds: const ['claim:1'],
    history: history,
    versionSnapshots: const [],
    evidenceEntries: const [],
    lintRecords: lintRecords,
  );
}
